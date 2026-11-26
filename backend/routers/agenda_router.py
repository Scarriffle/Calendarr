"""Read-only agenda for external integrations.

Built for a morning-briefing app: one request returns the events of a day
across every calendar an API key is allowed to see. Authenticated by a key
created in Settings, never by a session, so the calendar scope attached to the
key cannot be bypassed.

The events come from the same aggregator the web app uses
(``caldav_router.get_events``), which already merges CalDAV, local calendars
including shared and group ones, iCal subscriptions, Google and Home Assistant,
and already applies the privacy rules for other people's private events. The
briefing therefore cannot drift from what the calendar shows, and a new source
added there appears here with no change.

The response is a deliberately small, stable shape - not the internal event
dict. A key is long-lived, so what it serves is also what a leaked key exposes;
and an external contract should not change because an internal field is
renamed.
"""

import json
import logging
from datetime import date as date_cls, datetime, time, timedelta, timezone
from typing import Optional
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

import models
from auth import get_api_key
from database import get_db

logger = logging.getLogger(__name__)
router = APIRouter()

MAX_DAYS = 31


def _brief(ev: dict) -> dict:
    """The one shape this API promises.

    ``display_title`` wins over ``title`` where the server set it: group events
    carry their group prefix there and birthdays their age, and that decoration
    belongs to the server, not to each client.
    """
    return {
        "title": ev.get("display_title") or ev.get("title") or "",
        "start": ev.get("start"),
        "end": ev.get("end"),
        "all_day": bool(ev.get("allDay")),
        "location": ev.get("location") or "",
        "calendar": ev.get("calendar_name") or "",
        "color": ev.get("color") or ev.get("calendarColor") or None,
        "source": ev.get("source") or "",
    }


def _sort_key(ev: dict):
    # All-day events first, then by start. Start is an ISO string from every
    # source, so lexicographic order is chronological - except that all-day
    # values are date-only ("2026-11-26") and would otherwise sort before the
    # same day's timed events anyway. Made explicit rather than relied upon.
    return (0 if ev["all_day"] else 1, str(ev["start"] or ""))


@router.get("")
def agenda(
    date: Optional[str] = Query(
        None, description="YYYY-MM-DD. Defaults to today in `tz`."
    ),
    tz: str = Query("UTC", description="IANA name, e.g. Europe/Berlin."),
    days: int = Query(1, ge=1, le=MAX_DAYS),
    start: Optional[str] = Query(None, description="ISO 8601. Overrides date/days."),
    end: Optional[str] = Query(None, description="ISO 8601. Required with start."),
    db: Session = Depends(get_db),
    api_key: models.ApiKey = Depends(get_api_key),
):
    if (start is None) != (end is None):
        raise HTTPException(400, "start and end must be given together")

    if start is not None:
        try:
            start_dt = datetime.fromisoformat(start.replace("Z", "+00:00"))
            end_dt = datetime.fromisoformat(end.replace("Z", "+00:00"))
        except ValueError:
            raise HTTPException(400, "Invalid start/end — use ISO 8601")
        if start_dt.tzinfo is None:
            start_dt = start_dt.replace(tzinfo=timezone.utc)
        if end_dt.tzinfo is None:
            end_dt = end_dt.replace(tzinfo=timezone.utc)
        if (end_dt - start_dt) > timedelta(days=MAX_DAYS):
            raise HTTPException(400, f"Range must not exceed {MAX_DAYS} days")
        zone_name = None
        day = None
    else:
        # A briefing asks for "today", and today only exists in a timezone. The
        # server stores none for a user, so the caller names one.
        try:
            zone = ZoneInfo(tz)
        except (ZoneInfoNotFoundError, ValueError):
            raise HTTPException(400, f"Unknown timezone: {tz}")
        if date is not None:
            try:
                day = date_cls.fromisoformat(date)
            except ValueError:
                raise HTTPException(400, "Invalid date — use YYYY-MM-DD")
        else:
            day = datetime.now(zone).date()
        start_dt = datetime.combine(day, time.min, tzinfo=zone)
        end_dt = datetime.combine(day + timedelta(days=days), time.min, tzinfo=zone)
        zone_name = tz

    if end_dt <= start_dt:
        raise HTTPException(400, "end must be after start")

    # Imported here, not at module level: caldav_router imports a good part of
    # the app, and the top-level cycle is what the other routers avoid the same
    # way (see caldav_router's own google/HA imports).
    from routers.caldav_router import get_events

    payload = get_events(
        start=start_dt.isoformat(),
        end=end_dt.isoformat(),
        db=db,
        current_user=api_key.user,
    )
    events = payload.get("events") or []

    # NULL scope means every calendar the owner can read, today and after they
    # add one. A stored list is matched against the same calendar keys the event
    # payload carries.
    allowed = None
    if api_key.calendars:
        try:
            parsed = json.loads(api_key.calendars)
            if isinstance(parsed, list):
                allowed = {str(c) for c in parsed}
        except (ValueError, TypeError):
            logger.error("API key %s has unreadable calendar scope", api_key.id)
            raise HTTPException(500, "Key scope is corrupt — recreate the key")
    if allowed is not None:
        events = [e for e in events if str(e.get("calendar_id")) in allowed]

    out = [_brief(e) for e in events]
    out.sort(key=_sort_key)
    return {
        "date": day.isoformat() if day is not None else None,
        "timezone": zone_name,
        "start": start_dt.isoformat(),
        "end": end_dt.isoformat(),
        "days": days if start is None else None,
        "count": len(out),
        # Upstream sources that failed. A briefing should be able to say "one
        # calendar did not answer" rather than silently showing a short day.
        "errors": [
            {"source": e.get("source"), "name": e.get("name")}
            for e in (payload.get("errors") or [])
        ],
        "events": out,
    }
