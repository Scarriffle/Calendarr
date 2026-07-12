"""Shared builders for local-event API dicts.

Every local event returned by the API (the local router, the unified event
merge in caldav_router, and the group combined view) must look identical and
carry the additive collaboration fields: ``creator``, ``private``, ``type``,
and — in the group view — ``owner`` and ``is_group_event``.

Centralising this avoids the three near-duplicate dict constructions that used
to live in caldav_router.py.
"""

import logging
from datetime import datetime as dt_datetime, date as dt_date, timedelta, timezone as dt_timezone
from typing import Optional

from dateutil.rrule import rrulestr
from sqlalchemy.orm import Session

import models

logger = logging.getLogger(__name__)


def resolve_creator(ev: models.LocalEvent, *, name_cache: Optional[dict] = None) -> Optional[dict]:
    """Build the ``creator`` payload for an event.

    Returns ``{"id": int, "display_name": username}`` for a local creator,
    ``{"id": None, "display_name": "<name> (importiert)"}`` for an imported
    event, or ``None`` when no creator info exists (legacy events).

    ``name_cache`` maps user_id -> username to avoid per-event DB lookups; the
    creator relationship is used as a fallback.
    """
    if ev.creator_id:
        display = None
        if name_cache is not None:
            display = name_cache.get(ev.creator_id)
        if display is None and ev.creator is not None:
            display = ev.creator.display_name or ev.creator.username
        if display is not None:
            return {"id": ev.creator_id, "display_name": display}
    if ev.creator_name_external:
        return {"id": None, "display_name": f"{ev.creator_name_external} (importiert)"}
    return None


def private_visibility_for(db: Session, user_id: int) -> str:
    """A user's chosen visibility for their private events ('hidden' | 'busy')."""
    s = db.query(models.UserSettings).filter(models.UserSettings.user_id == user_id).first()
    return (s.private_event_visibility if s else None) or "busy"


# Only these fields survive 'busy' anonymisation — a whitelist, so no content
# field (title/location/description/creator/calendar name/recurrence) can leak.
_BUSY_KEEP = {
    "id", "url", "start", "end", "allDay", "calendar_id", "calendarColor",
    "source", "type", "owner", "is_group_event", "display_color", "read_only",
}


def mask_busy_event(event: dict) -> dict:
    """Anonymise a private event for 'busy' visibility: keep only timing /
    identity / render fields, drop ALL content."""
    masked = {k: event[k] for k in _BUSY_KEEP if k in event}
    masked["title"] = "Beschäftigt"
    masked["location"] = ""
    masked["description"] = ""
    masked["calendar_name"] = ""
    masked["creator"] = None
    masked["color"] = None
    masked["rrule"] = None
    masked["exdate"] = None
    masked["private"] = True
    return masked


def apply_event_privacy(
    event: dict, *, owner_id, is_private: bool, requester_id: int, visibility: str
) -> Optional[dict]:
    """Enforce another user's private-event visibility on a built event dict.

    Returns the event unchanged for the requester's own events or non-private
    events, ``None`` when the owner chose 'hidden', or a busy-masked copy when
    the owner chose 'busy'. Used by BOTH the merge read and the combined view so
    the privacy rule can never drift between them.
    """
    if not is_private or owner_id == requester_id:
        return event
    if visibility == "hidden":
        return None
    return mask_busy_event(event)


def build_local_event_dict(
    ev: models.LocalEvent,
    cal: models.LocalCalendar,
    *,
    start: Optional[str] = None,
    end: Optional[str] = None,
    all_day: Optional[bool] = None,
    rrule: Optional[str] = ...,
    creator: Optional[dict] = None,
    owner: Optional[dict] = None,
    is_group_event: bool = False,
    read_only: bool = False,
) -> dict:
    """Build the unified dict for a single local event (or occurrence).

    ``start``/``end``/``all_day`` override the stored values (used when emitting
    an expanded recurrence occurrence). ``owner``/``is_group_event`` are only set
    by the group combined view. ``read_only`` marks events the requester may not
    edit (someone else's calendar), so clients can hide edit/delete.
    """
    d = {
        "id": ev.uid,
        "url": f"local://{ev.uid}",
        "title": ev.title,
        "start": ev.start if start is None else start,
        "end": ev.end if end is None else end,
        "allDay": ev.all_day if all_day is None else all_day,
        "location": ev.location or "",
        "description": ev.description or "",
        "color": ev.color,
        "rrule": ev.rrule if rrule is ... else rrule,
        "exdate": ev.exdate,
        "calendar_id": f"local-{cal.id}",
        "calendar_name": cal.name,
        "calendarColor": cal.color,
        "source": "local",
        "type": "local",
        "creator": creator,
        "private": bool(ev.is_private),
        "reminders": [int(x) for x in (ev.reminders or "").split(",") if x.strip().lstrip("-").isdigit()],
    }
    # Birthday calendars: the server owns the presentation. It flags the event so
    # clients can show a cake icon, appends the age computed for THIS occurrence
    # (so it stays correct as years pass), and — when the calendar defines a
    # "notify N days before" — injects a reminder so the mobile schedulers fire
    # it. Web has no notification delivery, so the reminder is display-only there.
    if getattr(cal, "is_birthday", False):
        d["is_birthday"] = True
        display = ev.title
        if ev.birth_year:
            try:
                occ_year = int(str(d["start"])[:4])
                age = occ_year - int(ev.birth_year)
                if age >= 0:
                    display = f"{ev.title} ({age})"
            except (ValueError, TypeError):
                pass
        d["display_title"] = display
        if not d["reminders"] and cal.birthday_notify_days_before is not None:
            d["reminders"] = [int(cal.birthday_notify_days_before) * 1440]
    if owner is not None:
        d["owner"] = owner
    if is_group_event:
        d["is_group_event"] = True
    if read_only:
        d["read_only"] = True
    return d


def expand_recurring_local(
    ev: models.LocalEvent,
    local_cal: models.LocalCalendar,
    range_start,
    range_end,
    *,
    creator: Optional[dict] = None,
    owner: Optional[dict] = None,
    is_group_event: bool = False,
    read_only: bool = False,
) -> list:
    """Expand a recurring LocalEvent into individual occurrences in the range."""
    results = []
    excluded = set()
    if ev.exdate:
        for d in ev.exdate.split(","):
            d = d.strip()
            if d:
                excluded.add(d)
    try:
        ev_start_str = ev.start.replace("Z", "+00:00")
        ev_end_str = ev.end.replace("Z", "+00:00")

        if ev.all_day:
            ev_start = dt_date.fromisoformat(ev_start_str[:10])
            ev_end = dt_date.fromisoformat(ev_end_str[:10])
            duration = ev_end - ev_start
            rule = rrulestr(f"RRULE:{ev.rrule}", dtstart=dt_datetime.combine(ev_start, dt_datetime.min.time()))
            r_start = dt_datetime.combine(range_start if isinstance(range_start, dt_date) else range_start.date(), dt_datetime.min.time())
            r_end = dt_datetime.combine(range_end if isinstance(range_end, dt_date) else range_end.date(), dt_datetime.min.time())
            occurrences = rule.between(r_start - timedelta(days=1), r_end + timedelta(days=1), inc=True)
            for occ in occurrences:
                occ_start = occ.date()
                occ_key = occ_start.strftime("%Y%m%d")
                if occ_key in excluded:
                    continue
                occ_end = occ_start + duration
                results.append(build_local_event_dict(
                    ev, local_cal,
                    start=occ_start.isoformat(), end=occ_end.isoformat(), all_day=True,
                    creator=creator, owner=owner, is_group_event=is_group_event,
                    read_only=read_only,
                ))
        else:
            ev_start = dt_datetime.fromisoformat(ev_start_str)
            ev_end = dt_datetime.fromisoformat(ev_end_str)
            if ev_start.tzinfo is None:
                ev_start = ev_start.replace(tzinfo=dt_timezone.utc)
            if ev_end.tzinfo is None:
                ev_end = ev_end.replace(tzinfo=dt_timezone.utc)
            duration = ev_end - ev_start
            rule = rrulestr(f"RRULE:{ev.rrule}", dtstart=ev_start)
            r_start = range_start if isinstance(range_start, dt_datetime) else dt_datetime.combine(range_start, dt_datetime.min.time(), tzinfo=dt_timezone.utc)
            r_end = range_end if isinstance(range_end, dt_datetime) else dt_datetime.combine(range_end, dt_datetime.min.time(), tzinfo=dt_timezone.utc)
            if r_start.tzinfo is None:
                r_start = r_start.replace(tzinfo=dt_timezone.utc)
            if r_end.tzinfo is None:
                r_end = r_end.replace(tzinfo=dt_timezone.utc)
            occurrences = rule.between(r_start - timedelta(days=1), r_end + timedelta(days=1), inc=True)
            for occ in occurrences:
                occ_key = occ.strftime("%Y%m%d")
                if occ_key in excluded:
                    continue
                occ_end = occ + duration
                results.append(build_local_event_dict(
                    ev, local_cal,
                    start=occ.isoformat(), end=occ_end.isoformat(), all_day=False,
                    creator=creator, owner=owner, is_group_event=is_group_event,
                    read_only=read_only,
                ))
    except Exception as exc:
        logger.warning("Error expanding recurring event %s: %s", ev.uid, exc)
        # Fall back to a single event.
        results.append(build_local_event_dict(
            ev, local_cal, creator=creator, owner=owner, is_group_event=is_group_event,
            read_only=read_only,
        ))
    return results
