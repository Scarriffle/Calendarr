import logging
from datetime import datetime as dt_datetime, date as dt_date, timedelta, timezone as dt_timezone
from typing import Optional
from urllib.parse import urlparse

from dateutil.rrule import rrulestr
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import or_

import caldav_client
import models
from auth import get_current_user
from database import get_db
from routers.ical_router import _refresh_if_needed, get_events_for_subscription

logger = logging.getLogger(__name__)
router = APIRouter()

PALETTE = ["#4285f4", "#ea4335", "#fbbc04", "#34a853", "#ff6d00", "#46bdc6", "#8e24aa"]


class AccountCreate(BaseModel):
    name: str
    url: str
    username: str
    password: str
    color: str = "#4285f4"


class CalendarUpdate(BaseModel):
    enabled: Optional[bool] = None
    color: Optional[str] = None
    name: Optional[str] = None
    sidebar_hidden: Optional[bool] = None


class EventCreate(BaseModel):
    calendar_id: int
    title: str
    start: str
    end: str
    allDay: bool = False
    location: Optional[str] = None
    description: Optional[str] = None
    color: Optional[str] = None
    rrule: Optional[str] = None


class EventUpdate(BaseModel):
    title: Optional[str] = None
    start: Optional[str] = None
    end: Optional[str] = None
    allDay: Optional[bool] = None
    location: Optional[str] = None
    description: Optional[str] = None
    color: Optional[str] = None
    rrule: Optional[str] = None
    exdate: Optional[str] = None


def _account_dict(a: models.CalDAVAccount) -> dict:
    return {
        "id": a.id,
        "name": a.name,
        "url": a.url,
        "username": a.username,
        "color": a.color,
        "enabled": a.enabled,
        "calendars": [
            {
                "id": c.id,
                "name": c.name,
                "color": c.color or a.color,
                "enabled": c.enabled,
                "cal_id": c.cal_id,
                "sidebar_hidden": bool(c.sidebar_hidden),
            }
            for c in a.calendars
        ],
    }


def _expand_recurring_local(ev, local_cal, range_start, range_end):
    """Expand a recurring LocalEvent into individual occurrences within the date range."""
    results = []
    # Parse excluded dates
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
                results.append({
                    "id": ev.uid,
                    "url": f"local://{ev.uid}",
                    "title": ev.title,
                    "start": occ_start.isoformat(),
                    "end": occ_end.isoformat(),
                    "allDay": True,
                    "location": ev.location or "",
                    "description": ev.description or "",
                    "color": ev.color,
                    "rrule": ev.rrule,
                    "calendar_id": f"local-{local_cal.id}",
                    "calendar_name": local_cal.name,
                    "calendarColor": local_cal.color,
                    "source": "local",
                })
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
                results.append({
                    "id": ev.uid,
                    "url": f"local://{ev.uid}",
                    "title": ev.title,
                    "start": occ.isoformat(),
                    "end": occ_end.isoformat(),
                    "allDay": False,
                    "location": ev.location or "",
                    "description": ev.description or "",
                    "color": ev.color,
                    "rrule": ev.rrule,
                    "calendar_id": f"local-{local_cal.id}",
                    "calendar_name": local_cal.name,
                    "calendarColor": local_cal.color,
                    "source": "local",
                })
    except Exception as exc:
        logger.warning("Error expanding recurring event %s: %s", ev.uid, exc)
        # Fall back to single event
        results.append({
            "id": ev.uid, "url": f"local://{ev.uid}", "title": ev.title,
            "start": ev.start, "end": ev.end, "allDay": ev.all_day,
            "location": ev.location or "", "description": ev.description or "",
            "color": ev.color, "rrule": ev.rrule,
            "calendar_id": f"local-{local_cal.id}", "calendar_name": local_cal.name,
            "calendarColor": local_cal.color, "source": "local",
        })
    return results


def _normalize_url(url: str) -> str:
    """Normalize URL for comparison: lowercase scheme/host, strip trailing slash."""
    parsed = urlparse(url)
    scheme = parsed.scheme.lower()
    host = (parsed.hostname or '').lower()
    port = parsed.port
    if (scheme == 'https' and port == 443) or (scheme == 'http' and port == 80):
        port = None
    netloc = f"{host}:{port}" if port else host
    path = parsed.path.rstrip('/')
    return f"{scheme}://{netloc}{path}"


def _find_account_for_event_url(
    event_url: str, accounts: list[models.CalDAVAccount]
) -> Optional[models.CalDAVAccount]:
    norm_event = _normalize_url(event_url)
    # Primary: match against normalized account URL
    for acc in accounts:
        if norm_event.startswith(_normalize_url(acc.url)):
            return acc
    # Fallback: match against normalized calendar URLs
    for acc in accounts:
        for cal in acc.calendars:
            if norm_event.startswith(_normalize_url(cal.cal_id)):
                return acc
    # Second fallback: path-only matching
    event_path = urlparse(event_url).path.rstrip('/')
    for acc in accounts:
        acc_path = urlparse(acc.url).path.rstrip('/')
        if acc_path and event_path.startswith(acc_path):
            return acc
    for acc in accounts:
        for cal in acc.calendars:
            cal_path = urlparse(cal.cal_id).path.rstrip('/')
            if cal_path and event_path.startswith(cal_path):
                return acc
    return None


@router.get("/accounts")
def list_accounts(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    accounts = (
        db.query(models.CalDAVAccount)
        .filter(models.CalDAVAccount.user_id == current_user.id)
        .all()
    )
    return [_account_dict(a) for a in accounts]


@router.post("/accounts")
def add_account(
    data: AccountCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    try:
        remote_cals = caldav_client.fetch_calendars(data.url, data.username, data.password)
    except ValueError as e:
        raise HTTPException(400, str(e))

    account = models.CalDAVAccount(
        user_id=current_user.id,
        name=data.name,
        url=data.url,
        username=data.username,
        password=data.password,
        color=data.color,
    )
    db.add(account)
    db.flush()

    for idx, cal in enumerate(remote_cals):
        db.add(
            models.Calendar(
                account_id=account.id,
                cal_id=cal["url"],
                name=cal["name"],
                color=cal.get("color") or PALETTE[idx % len(PALETTE)],
                enabled=True,
            )
        )

    db.commit()
    db.refresh(account)
    return _account_dict(account)


@router.delete("/accounts/{account_id}")
def delete_account(
    account_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    account = (
        db.query(models.CalDAVAccount)
        .filter(
            models.CalDAVAccount.id == account_id,
            models.CalDAVAccount.user_id == current_user.id,
        )
        .first()
    )
    if not account:
        raise HTTPException(404, "Account not found")
    db.delete(account)
    db.commit()
    return {"ok": True}


@router.post("/accounts/{account_id}/sync")
def sync_account(
    account_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    account = (
        db.query(models.CalDAVAccount)
        .filter(
            models.CalDAVAccount.id == account_id,
            models.CalDAVAccount.user_id == current_user.id,
        )
        .first()
    )
    if not account:
        raise HTTPException(404, "Account not found")
    try:
        remote_cals = caldav_client.fetch_calendars(
            account.url, account.username, account.password
        )
    except ValueError as e:
        raise HTTPException(400, str(e))

    existing = {c.cal_id: c for c in account.calendars}
    for idx, cal in enumerate(remote_cals):
        if cal["url"] not in existing:
            db.add(
                models.Calendar(
                    account_id=account.id,
                    cal_id=cal["url"],
                    name=cal["name"],
                    color=cal.get("color") or PALETTE[idx % len(PALETTE)],
                    enabled=True,
                )
            )
        else:
            existing[cal["url"]].name = cal["name"]
    db.commit()
    db.refresh(account)
    return _account_dict(account)


@router.put("/calendars/{calendar_id}")
def update_calendar(
    calendar_id: int,
    data: CalendarUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    calendar = (
        db.query(models.Calendar)
        .join(models.CalDAVAccount)
        .filter(
            models.Calendar.id == calendar_id,
            models.CalDAVAccount.user_id == current_user.id,
        )
        .first()
    )
    if not calendar:
        raise HTTPException(404, "Calendar not found")
    if data.enabled is not None:
        calendar.enabled = data.enabled
    if data.color is not None:
        calendar.color = data.color
    if data.name is not None:
        calendar.name = data.name
    if data.sidebar_hidden is not None:
        calendar.sidebar_hidden = data.sidebar_hidden
    db.commit()
    return {"ok": True}


@router.get("/events")
def get_events(
    start: str = Query(...),
    end: str = Query(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    from datetime import datetime, timezone

    try:
        start_dt = datetime.fromisoformat(start.replace("Z", "+00:00"))
        end_dt = datetime.fromisoformat(end.replace("Z", "+00:00"))
    except ValueError:
        raise HTTPException(400, "Invalid date format — use ISO 8601")

    # Make timezone-aware
    if start_dt.tzinfo is None:
        start_dt = start_dt.replace(tzinfo=timezone.utc)
    if end_dt.tzinfo is None:
        end_dt = end_dt.replace(tzinfo=timezone.utc)

    all_events = []
    accounts = (
        db.query(models.CalDAVAccount)
        .filter(
            models.CalDAVAccount.user_id == current_user.id,
            models.CalDAVAccount.enabled == True,
        )
        .all()
    )

    for account in accounts:
        for calendar in account.calendars:
            if not calendar.enabled or calendar.sidebar_hidden:
                continue
            try:
                events = caldav_client.fetch_events(
                    account.url,
                    account.username,
                    account.password,
                    calendar.cal_id,
                    start_dt,
                    end_dt,
                )
                cal_color = calendar.color or account.color
                for ev in events:
                    ev["calendar_id"] = calendar.id
                    ev["calendar_name"] = calendar.name
                    ev["calendarColor"] = cal_color
                    ev["source"] = "caldav"
                    all_events.append(ev)
            except Exception as exc:
                logger.error(
                    "Error fetching calendar %s: %s", calendar.id, exc
                )

    # ── Local calendar events ─────────────────────────────
    local_calendars = (
        db.query(models.LocalCalendar)
        .filter(
            models.LocalCalendar.user_id == current_user.id,
            models.LocalCalendar.enabled == True,
        )
        .all()
    )
    for local_cal in local_calendars:
        local_events = (
            db.query(models.LocalEvent)
            .filter(
                models.LocalEvent.calendar_id == local_cal.id,
                or_(
                    # Non-recurring events in range
                    (models.LocalEvent.rrule == None) & (models.LocalEvent.start < end) & (models.LocalEvent.end > start),
                    # Recurring events: always include so we can expand
                    models.LocalEvent.rrule != None,
                ),
            )
            .all()
        )
        for ev in local_events:
            if ev.rrule:
                all_events.extend(_expand_recurring_local(ev, local_cal, start_dt, end_dt))
            else:
                all_events.append({
                    "id": ev.uid,
                    "url": f"local://{ev.uid}",
                    "title": ev.title,
                    "start": ev.start,
                    "end": ev.end,
                    "allDay": ev.all_day,
                    "location": ev.location or "",
                    "description": ev.description or "",
                    "color": ev.color,
                    "rrule": None,
                    "calendar_id": f"local-{local_cal.id}",
                    "calendar_name": local_cal.name,
                    "calendarColor": local_cal.color,
                    "source": "local",
                })

    # ── iCal subscription events ──────────────────────────
    ical_subs = (
        db.query(models.ICalSubscription)
        .filter(
            models.ICalSubscription.user_id == current_user.id,
            models.ICalSubscription.enabled == True,
        )
        .all()
    )
    for sub in ical_subs:
        try:
            _refresh_if_needed(sub, db)
            all_events.extend(get_events_for_subscription(sub, start_dt, end_dt, db))
        except Exception as exc:
            logger.error("Error fetching iCal subscription %s: %s", sub.id, exc)

    # ── Google Calendar events ───────────────────────────
    from routers.google_router import get_google_events
    google_accounts = (
        db.query(models.GoogleAccount)
        .filter(models.GoogleAccount.user_id == current_user.id)
        .all()
    )
    google_errors = []
    for g_acc in google_accounts:
        try:
            all_events.extend(get_google_events(g_acc, start_dt, end_dt, db))
        except Exception as exc:
            logger.error("Error fetching Google Calendar for %s: %s", g_acc.email, exc)
            google_errors.append({"email": g_acc.email})

    # ── Home Assistant events ─────────────────────────────
    from routers.homeassistant_router import get_ha_events
    ha_accounts = (
        db.query(models.HomeAssistantAccount)
        .filter(models.HomeAssistantAccount.user_id == current_user.id)
        .all()
    )
    for ha_acc in ha_accounts:
        try:
            all_events.extend(get_ha_events(ha_acc, start_dt, end_dt, db))
        except Exception as exc:
            logger.error("Error fetching HA events for %s: %s", ha_acc.name, exc)

    return {"events": all_events, "errors": google_errors}


@router.post("/events")
def create_event(
    data: EventCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    calendar = (
        db.query(models.Calendar)
        .join(models.CalDAVAccount)
        .filter(
            models.Calendar.id == data.calendar_id,
            models.CalDAVAccount.user_id == current_user.id,
        )
        .first()
    )
    if not calendar:
        raise HTTPException(404, "Calendar not found")
    account = calendar.account
    try:
        uid = caldav_client.create_event(
            account.url,
            account.username,
            account.password,
            calendar.cal_id,
            {
                "title": data.title,
                "start": data.start,
                "end": data.end,
                "allDay": data.allDay,
                "location": data.location,
                "description": data.description,
                "color": data.color,
                "rrule": data.rrule,
            },
        )
        return {"uid": uid, "calendar_id": data.calendar_id}
    except Exception as exc:
        raise HTTPException(500, f"Could not create event: {exc}")


@router.put("/events/{event_id}")
def update_event(
    event_id: str,
    event_url: str = Query(...),
    calendar_id: Optional[int] = Query(None),
    data: EventUpdate = None,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    accounts = (
        db.query(models.CalDAVAccount)
        .filter(models.CalDAVAccount.user_id == current_user.id)
        .all()
    )
    account = None
    cal_url = None
    if calendar_id is not None:
        cal = (
            db.query(models.Calendar)
            .join(models.CalDAVAccount)
            .filter(models.Calendar.id == calendar_id, models.CalDAVAccount.user_id == current_user.id)
            .first()
        )
        if cal:
            account = next((a for a in accounts if a.id == cal.account_id), None)
            cal_url = cal.cal_id
    if not account:
        account = _find_account_for_event_url(event_url, accounts)
        # Try to find the calendar URL for the account
        if account and not cal_url:
            for c in account.calendars:
                if event_url.startswith(c.cal_id) or event_url.startswith(_normalize_url(c.cal_id)):
                    cal_url = c.cal_id
                    break
    if not account:
        raise HTTPException(404, "Event not found or not authorized")
    try:
        caldav_client.update_event(
            account.url,
            account.username,
            account.password,
            event_url,
            data.model_dump(exclude_none=True) if data else {},
            calendar_url=cal_url,
        )
        return {"ok": True}
    except Exception as exc:
        raise HTTPException(500, f"Could not update event: {exc}")


@router.delete("/events/{event_id}")
def delete_event(
    event_id: str,
    event_url: str = Query(...),
    calendar_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    accounts = (
        db.query(models.CalDAVAccount)
        .filter(models.CalDAVAccount.user_id == current_user.id)
        .all()
    )
    account = None
    cal_url = None
    if calendar_id is not None:
        cal = (
            db.query(models.Calendar)
            .join(models.CalDAVAccount)
            .filter(models.Calendar.id == calendar_id, models.CalDAVAccount.user_id == current_user.id)
            .first()
        )
        if cal:
            account = next((a for a in accounts if a.id == cal.account_id), None)
            cal_url = cal.cal_id
    if not account:
        account = _find_account_for_event_url(event_url, accounts)
        if account and not cal_url:
            for c in account.calendars:
                if event_url.startswith(c.cal_id) or event_url.startswith(_normalize_url(c.cal_id)):
                    cal_url = c.cal_id
                    break
    if not account:
        raise HTTPException(404, "Event not found or not authorized")
    try:
        caldav_client.delete_event(
            account.url, account.username, account.password, event_url,
            calendar_url=cal_url,
        )
        return {"ok": True}
    except Exception as exc:
        raise HTTPException(500, f"Could not delete event: {exc}")
