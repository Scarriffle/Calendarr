import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

import models
from auth import get_current_user
from database import get_db

router = APIRouter()


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


class EventUpdate(BaseModel):
    title: Optional[str] = None
    start: Optional[str] = None
    end: Optional[str] = None
    allDay: Optional[bool] = None
    location: Optional[str] = None
    description: Optional[str] = None
    color: Optional[str] = None


def _cal_dict(cal: models.LocalCalendar) -> dict:
    return {
        "id": cal.id,
        "name": cal.name,
        "color": cal.color,
        "enabled": cal.enabled,
    }


def _event_dict(ev: models.LocalEvent, cal: models.LocalCalendar) -> dict:
    return {
        "id": ev.uid,
        "url": f"local://{ev.uid}",
        "title": ev.title,
        "start": ev.start,
        "end": ev.end,
        "allDay": ev.all_day,
        "location": ev.location or "",
        "description": ev.description or "",
        "color": ev.color,
        "calendar_id": f"local-{cal.id}",
        "calendar_name": cal.name,
        "calendarColor": cal.color,
        "source": "local",
    }


# ── Calendar CRUD ─────────────────────────────────────────

@router.get("/calendars")
def list_calendars(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    cals = (
        db.query(models.LocalCalendar)
        .filter(models.LocalCalendar.user_id == current_user.id)
        .all()
    )
    return [_cal_dict(c) for c in cals]


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
    cal = (
        db.query(models.LocalCalendar)
        .filter(
            models.LocalCalendar.id == data.calendar_id,
            models.LocalCalendar.user_id == current_user.id,
        )
        .first()
    )
    if not cal:
        raise HTTPException(404, "Calendar not found")

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
    )
    db.add(ev)
    db.commit()
    db.refresh(ev)
    return _event_dict(ev, cal)


@router.put("/events/{uid}")
def update_event(
    uid: str,
    data: EventUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    ev = (
        db.query(models.LocalEvent)
        .join(models.LocalCalendar)
        .filter(
            models.LocalEvent.uid == uid,
            models.LocalCalendar.user_id == current_user.id,
        )
        .first()
    )
    if not ev:
        raise HTTPException(404, "Event not found")
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
    db.commit()
    return {"ok": True}


@router.delete("/events/{uid}")
def delete_event(
    uid: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    ev = (
        db.query(models.LocalEvent)
        .join(models.LocalCalendar)
        .filter(
            models.LocalEvent.uid == uid,
            models.LocalCalendar.user_id == current_user.id,
        )
        .first()
    )
    if not ev:
        raise HTTPException(404, "Event not found")
    db.delete(ev)
    db.commit()
    return {"ok": True}
