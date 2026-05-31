import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Form, HTTPException, Query, UploadFile, File
from fastapi.responses import Response
from pydantic import BaseModel
from sqlalchemy.orm import Session

import ical_io
import models
import permissions
from auth import get_current_user
from database import get_db
from local_events_util import build_local_event_dict, resolve_creator

router = APIRouter()


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class CalendarCreate(BaseModel):
    name: str
    color: str = "#34a853"


class CalendarUpdate(BaseModel):
    name: Optional[str] = None
    color: Optional[str] = None
    enabled: Optional[bool] = None


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
    private: bool = False


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
    private: Optional[bool] = None


class ShareCreate(BaseModel):
    user_id: int
    permission: str = "read"


def _cal_dict(cal: models.LocalCalendar, *, owned: bool = True,
              shared_by: Optional[str] = None, permission: Optional[str] = None) -> dict:
    d = {
        "id": cal.id,
        "name": cal.name,
        "color": cal.color,
        "enabled": cal.enabled,
        "type": "local",
        "owned": owned,
    }
    if shared_by is not None:
        d["shared_by"] = shared_by
    if permission is not None:
        d["permission"] = permission
    return d


def _event_dict(ev: models.LocalEvent, cal: models.LocalCalendar, db: Session) -> dict:
    return build_local_event_dict(ev, cal, creator=resolve_creator(ev))


# ── Calendar CRUD ─────────────────────────────────────────

@router.get("/calendars")
def list_calendars(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    # Own calendars
    own = (
        db.query(models.LocalCalendar)
        .filter(models.LocalCalendar.user_id == current_user.id)
        .all()
    )
    result = [_cal_dict(c, owned=True) for c in own]

    # Calendars shared with this user
    shares = (
        db.query(models.CalendarShare)
        .filter(models.CalendarShare.user_id == current_user.id)
        .all()
    )
    seen_ids = {c.id for c in own}
    for share in shares:
        cal = share.calendar
        if cal is None or cal.id in seen_ids:
            continue
        seen_ids.add(cal.id)
        owner = db.query(models.User).filter(models.User.id == cal.user_id).first()
        result.append(_cal_dict(
            cal, owned=False,
            shared_by=owner.username if owner else None,
            permission=share.permission,
        ))

    # Group calendars the user can reach via membership (read_write), so members
    # can select the group calendar in the editor and see it in their list.
    group_cals = (
        db.query(models.LocalCalendar, models.Group.name)
        .join(models.GroupCalendar, models.GroupCalendar.calendar_id == models.LocalCalendar.id)
        .join(models.Group, models.Group.id == models.GroupCalendar.group_id)
        .join(models.GroupMember, models.GroupMember.group_id == models.GroupCalendar.group_id)
        .filter(models.GroupMember.user_id == current_user.id)
        .all()
    )
    for cal, group_name in group_cals:
        if cal.id in seen_ids:
            continue
        seen_ids.add(cal.id)
        d = _cal_dict(cal, owned=False, shared_by=group_name, permission="read_write")
        d["group"] = True
        result.append(d)
    return result


@router.post("/calendars")
def create_calendar(
    data: CalendarCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    cal = models.LocalCalendar(
        user_id=current_user.id,
        name=data.name,
        color=data.color,
    )
    db.add(cal)
    db.commit()
    db.refresh(cal)
    return _cal_dict(cal)


@router.put("/calendars/{calendar_id}")
def update_calendar(
    calendar_id: int,
    data: CalendarUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    cal = (
        db.query(models.LocalCalendar)
        .filter(
            models.LocalCalendar.id == calendar_id,
            models.LocalCalendar.user_id == current_user.id,
        )
        .first()
    )
    if not cal:
        raise HTTPException(404, "Calendar not found")
    if data.name is not None:
        cal.name = data.name
    if data.color is not None:
        cal.color = data.color
    if data.enabled is not None:
        cal.enabled = data.enabled
    db.commit()
    return {"ok": True}


@router.delete("/calendars/{calendar_id}")
def delete_calendar(
    calendar_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    cal = (
        db.query(models.LocalCalendar)
        .filter(
            models.LocalCalendar.id == calendar_id,
            models.LocalCalendar.user_id == current_user.id,
        )
        .first()
    )
    if not cal:
        raise HTTPException(404, "Calendar not found")
    db.delete(cal)
    db.commit()
    return {"ok": True}


# ── Event CRUD ────────────────────────────────────────────

@router.post("/events")
def create_event(
    data: EventCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    # Owner, shared (read_write), or group-member calendars are writable.
    cal = permissions.accessible_local_calendar(
        db, current_user, data.calendar_id, require_write=True
    )

    ev = models.LocalEvent(
        calendar_id=cal.id,
        uid=str(uuid.uuid4()),
        title=data.title,
        start=data.start,
        end=data.end,
        all_day=data.allDay,
        location=data.location,
        description=data.description,
        color=data.color,
        rrule=data.rrule,
        is_private=data.private,
        creator_id=current_user.id,  # server-side, never from the client
    )
    db.add(ev)
    db.commit()
    db.refresh(ev)
    return _event_dict(ev, cal, db)


def _writable_event(db: Session, current_user: models.User, uid: str) -> models.LocalEvent:
    ev = db.query(models.LocalEvent).filter(models.LocalEvent.uid == uid).first()
    if not ev:
        raise HTTPException(404, "Event not found")
    # Raises 404/403 unless the user may write this event's calendar.
    permissions.accessible_local_calendar(db, current_user, ev.calendar_id, require_write=True)
    return ev


@router.put("/events/{uid}")
def update_event(
    uid: str,
    data: EventUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    ev = _writable_event(db, current_user, uid)
    if data.private is not None:
        ev.is_private = data.private
    if data.title is not None:
        ev.title = data.title
    if data.start is not None:
        ev.start = data.start
    if data.end is not None:
        ev.end = data.end
    if data.allDay is not None:
        ev.all_day = data.allDay
    if data.location is not None:
        ev.location = data.location
    if data.description is not None:
        ev.description = data.description
    if data.color is not None:
        ev.color = data.color
    if data.rrule is not None:
        ev.rrule = data.rrule if data.rrule else None
    if data.exdate is not None:
        existing = ev.exdate or ""
        dates = [d for d in existing.split(",") if d]
        if data.exdate not in dates:
            dates.append(data.exdate)
        ev.exdate = ",".join(dates)
    db.commit()
    return {"ok": True}


@router.delete("/events/{uid}")
def delete_event(
    uid: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    ev = _writable_event(db, current_user, uid)
    db.delete(ev)
    db.commit()
    return {"ok": True}


# ── Sharing (owner only) ──────────────────────────────────

@router.get("/calendars/{calendar_id}/shares")
def list_shares(
    calendar_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    permissions.is_calendar_owner(db, current_user, calendar_id)
    shares = (
        db.query(models.CalendarShare)
        .filter(models.CalendarShare.calendar_id == calendar_id)
        .all()
    )
    out = []
    for s in shares:
        u = db.query(models.User).filter(models.User.id == s.user_id).first()
        out.append({
            "user_id": s.user_id,
            "display_name": u.username if u else None,
            "permission": s.permission,
            "created_at": s.created_at,
        })
    return out


@router.post("/calendars/{calendar_id}/shares")
def add_share(
    calendar_id: int,
    data: ShareCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    permissions.is_calendar_owner(db, current_user, calendar_id)
    if data.permission not in ("read", "read_write"):
        raise HTTPException(422, "permission must be 'read' or 'read_write'")
    target = db.query(models.User).filter(models.User.id == data.user_id).first()
    if not target:
        raise HTTPException(404, "User not found")
    if target.id == current_user.id:
        raise HTTPException(422, "Cannot share a calendar with yourself")

    share = (
        db.query(models.CalendarShare)
        .filter(
            models.CalendarShare.calendar_id == calendar_id,
            models.CalendarShare.user_id == data.user_id,
        )
        .first()
    )
    if share:
        share.permission = data.permission  # update existing
    else:
        share = models.CalendarShare(
            calendar_id=calendar_id,
            user_id=data.user_id,
            permission=data.permission,
            created_at=_now_iso(),
        )
        db.add(share)
    db.commit()
    return {"ok": True}


@router.delete("/calendars/{calendar_id}/shares/{user_id}")
def remove_share(
    calendar_id: int,
    user_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    permissions.is_calendar_owner(db, current_user, calendar_id)
    share = (
        db.query(models.CalendarShare)
        .filter(
            models.CalendarShare.calendar_id == calendar_id,
            models.CalendarShare.user_id == user_id,
        )
        .first()
    )
    if not share:
        raise HTTPException(404, "Share not found")
    db.delete(share)
    db.commit()
    return {"ok": True}


# ── iCal Import / Export (local calendars only) ───────────

def _import_ics_into(cal: models.LocalCalendar, raw: bytes, db: Session) -> dict:
    parsed = ical_io.parse_ics(raw)
    imported = 0
    skipped = 0
    for item in parsed["events"]:
        uid = item.get("uid") or str(uuid.uuid4())
        existing = db.query(models.LocalEvent).filter(models.LocalEvent.uid == uid).first()
        if existing:
            skipped += 1
            continue
        ev = models.LocalEvent(
            calendar_id=cal.id,
            uid=uid,
            title=item.get("title") or "(ohne Titel)",
            start=item["start"],
            end=item["end"],
            all_day=item.get("all_day", False),
            location=item.get("location"),
            description=item.get("description"),
            rrule=item.get("rrule"),
            exdate=item.get("exdate"),
            creator_name_external=item.get("organizer"),
        )
        db.add(ev)
        imported += 1
    db.commit()
    return {"imported": imported, "skipped": skipped, "errors": parsed["errors"]}


@router.post("/calendars/{calendar_id}/import")
async def import_calendar(
    calendar_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    cal = permissions.accessible_local_calendar(db, current_user, calendar_id, require_write=True)
    raw = await file.read()
    try:
        return _import_ics_into(cal, raw, db)
    except ValueError as e:
        raise HTTPException(422, str(e))


@router.post("/import")
async def import_generic(
    file: UploadFile = File(...),
    calendar_id: Optional[int] = Form(None),
    create_calendar: bool = Form(False),
    calendar_name: Optional[str] = Form(None),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if create_calendar:
        cal = models.LocalCalendar(
            user_id=current_user.id,
            name=calendar_name or "Importiert",
        )
        db.add(cal)
        db.commit()
        db.refresh(cal)
    elif calendar_id is not None:
        cal = permissions.accessible_local_calendar(db, current_user, calendar_id, require_write=True)
    else:
        raise HTTPException(422, "Provide calendar_id or create_calendar=true")

    raw = await file.read()
    try:
        result = _import_ics_into(cal, raw, db)
    except ValueError as e:
        raise HTTPException(422, str(e))
    result["calendar_id"] = cal.id
    return result


@router.get("/calendars/{calendar_id}/export")
def export_calendar(
    calendar_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    cal = permissions.accessible_local_calendar(db, current_user, calendar_id)
    events = (
        db.query(models.LocalEvent)
        .filter(models.LocalEvent.calendar_id == cal.id)
        .all()
    )
    # Resolve creator display names for ORGANIZER.
    name_cache = {u.id: u.username for u in db.query(models.User).all()}
    ics = ical_io.build_ics(cal, events, name_cache=name_cache)
    safe_name = "".join(c for c in cal.name if c.isalnum() or c in (" ", "-", "_")).strip() or "calendar"
    return Response(
        content=ics,
        media_type="text/calendar",
        headers={"Content-Disposition": f'attachment; filename="{safe_name}.ics"'},
    )
