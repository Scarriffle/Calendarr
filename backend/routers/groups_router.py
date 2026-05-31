"""Groups: shared group calendar + combined member-calendar overlay view.

A group has members and exactly one group calendar (a local calendar owned by
the creator, linked via group_calendars). Members get read/write on the group
calendar (enforced by permissions.accessible_local_calendar). The combined view
overlays every member's local calendars plus the group calendar, applying each
member's private-event visibility setting.
"""

import logging
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import or_
from sqlalchemy.orm import Session

import models
from auth import get_current_user
from database import get_db
from local_events_util import build_local_event_dict, expand_recurring_local

logger = logging.getLogger(__name__)
router = APIRouter()

PALETTE = ["#4285f4", "#ea4335", "#fbbc04", "#34a853", "#ff6d00", "#46bdc6", "#8e24aa"]


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class GroupCreate(BaseModel):
    name: str
    member_ids: List[int] = []


class MemberAdd(BaseModel):
    user_id: int


def _membership(db: Session, group_id: int, user_id: int) -> Optional[models.GroupMember]:
    return (
        db.query(models.GroupMember)
        .filter(
            models.GroupMember.group_id == group_id,
            models.GroupMember.user_id == user_id,
        )
        .first()
    )


def _require_member(db: Session, group: models.Group, user: models.User) -> models.GroupMember:
    m = _membership(db, group.id, user.id)
    if not m:
        raise HTTPException(403, "You are not a member of this group")
    return m


def _require_owner(db: Session, group: models.Group, user: models.User) -> None:
    m = _membership(db, group.id, user.id)
    if not m or m.role != "owner":
        raise HTTPException(403, "Only the group owner may do this")


def _get_group_or_404(db: Session, group_id: int) -> models.Group:
    g = db.query(models.Group).filter(models.Group.id == group_id).first()
    if not g:
        raise HTTPException(404, "Group not found")
    return g


def _group_calendar_id(db: Session, group_id: int) -> Optional[int]:
    gc = (
        db.query(models.GroupCalendar)
        .filter(models.GroupCalendar.group_id == group_id)
        .first()
    )
    return gc.calendar_id if gc else None


@router.post("/")
def create_group(
    data: GroupCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    group = models.Group(name=data.name, created_by=current_user.id, created_at=_now_iso())
    db.add(group)
    db.flush()

    # Creator is owner; add the requested members (deduped, excluding creator).
    db.add(models.GroupMember(group_id=group.id, user_id=current_user.id, role="owner", joined_at=_now_iso()))
    seen = {current_user.id}
    for uid in data.member_ids:
        if uid in seen:
            continue
        if not db.query(models.User).filter(models.User.id == uid).first():
            continue
        db.add(models.GroupMember(group_id=group.id, user_id=uid, role="member", joined_at=_now_iso()))
        seen.add(uid)

    # Auto-create the group calendar (a local calendar owned by the creator).
    cal = models.LocalCalendar(
        user_id=current_user.id,
        name=f"{data.name} (Gruppe)",
        color=PALETTE[group.id % len(PALETTE)],
    )
    db.add(cal)
    db.flush()
    db.add(models.GroupCalendar(group_id=group.id, calendar_id=cal.id))

    db.commit()
    db.refresh(group)
    return _group_detail(db, group, current_user)


@router.get("/")
def list_groups(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    memberships = (
        db.query(models.GroupMember)
        .filter(models.GroupMember.user_id == current_user.id)
        .all()
    )
    out = []
    for m in memberships:
        group = db.query(models.Group).filter(models.Group.id == m.group_id).first()
        if not group:
            continue
        member_count = db.query(models.GroupMember).filter(models.GroupMember.group_id == group.id).count()
        out.append({
            "id": group.id,
            "name": group.name,
            "role": m.role,
            "member_count": member_count,
            "group_calendar_id": _group_calendar_id(db, group.id),
        })
    return out


def _group_detail(db: Session, group: models.Group, current_user: models.User) -> dict:
    members = db.query(models.GroupMember).filter(models.GroupMember.group_id == group.id).all()
    member_dicts = []
    for m in members:
        u = db.query(models.User).filter(models.User.id == m.user_id).first()
        member_dicts.append({
            "id": m.user_id,
            "display_name": u.username if u else None,
            "role": m.role,
        })
    return {
        "id": group.id,
        "name": group.name,
        "created_by": group.created_by,
        "members": member_dicts,
        "group_calendar_id": _group_calendar_id(db, group.id),
    }


@router.get("/{group_id}")
def get_group(
    group_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    group = _get_group_or_404(db, group_id)
    _require_member(db, group, current_user)
    return _group_detail(db, group, current_user)


@router.post("/{group_id}/members")
def add_member(
    group_id: int,
    data: MemberAdd,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    group = _get_group_or_404(db, group_id)
    _require_owner(db, group, current_user)
    if not db.query(models.User).filter(models.User.id == data.user_id).first():
        raise HTTPException(404, "User not found")
    if _membership(db, group_id, data.user_id):
        return {"ok": True}  # already a member
    db.add(models.GroupMember(group_id=group_id, user_id=data.user_id, role="member", joined_at=_now_iso()))
    db.commit()
    return {"ok": True}


@router.delete("/{group_id}/members/{user_id}")
def remove_member(
    group_id: int,
    user_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    group = _get_group_or_404(db, group_id)
    # Owner can remove anyone; a member may remove themselves (leave).
    if user_id != current_user.id:
        _require_owner(db, group, current_user)
    else:
        _require_member(db, group, current_user)
    target = _membership(db, group_id, user_id)
    if not target:
        raise HTTPException(404, "Member not found")
    if target.role == "owner":
        raise HTTPException(422, "The owner cannot be removed; delete the group instead")
    db.delete(target)
    db.commit()
    return {"ok": True}


@router.delete("/{group_id}")
def delete_group(
    group_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    group = _get_group_or_404(db, group_id)
    _require_owner(db, group, current_user)
    # Remove the group calendar (and its events) too.
    gc = db.query(models.GroupCalendar).filter(models.GroupCalendar.group_id == group_id).first()
    if gc:
        cal = db.query(models.LocalCalendar).filter(models.LocalCalendar.id == gc.calendar_id).first()
        if cal:
            db.delete(cal)  # cascades to events
    db.delete(group)  # cascades to members + group_calendar link
    db.commit()
    return {"ok": True}


def _strip_busy(event: dict) -> dict:
    """Anonymise a private event for the 'busy' visibility mode."""
    event = dict(event)
    event["title"] = "Beschäftigt"
    event["location"] = ""
    event["description"] = ""
    event["private"] = True
    return event


@router.get("/{group_id}/combined")
def combined_events(
    group_id: int,
    start: str = Query(...),
    end: str = Query(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    group = _get_group_or_404(db, group_id)
    _require_member(db, group, current_user)

    try:
        start_dt = datetime.fromisoformat(start.replace("Z", "+00:00"))
        end_dt = datetime.fromisoformat(end.replace("Z", "+00:00"))
    except ValueError:
        raise HTTPException(400, "Invalid date format — use ISO 8601")
    if start_dt.tzinfo is None:
        start_dt = start_dt.replace(tzinfo=timezone.utc)
    if end_dt.tzinfo is None:
        end_dt = end_dt.replace(tzinfo=timezone.utc)

    members = db.query(models.GroupMember).filter(models.GroupMember.group_id == group_id).all()
    name_cache = {u.id: u.username for u in db.query(models.User).all()}
    visibility_cache: dict[int, str] = {}

    def visibility_for(user_id: int) -> str:
        if user_id not in visibility_cache:
            s = db.query(models.UserSettings).filter(models.UserSettings.user_id == user_id).first()
            visibility_cache[user_id] = (s.private_event_visibility if s else None) or "busy"
        return visibility_cache[user_id]

    group_cal_id = _group_calendar_id(db, group_id)
    all_events: list[dict] = []

    def emit_calendar(cal: models.LocalCalendar, owner_id: int, is_group: bool):
        owner_user = name_cache.get(owner_id)
        owner = {"id": owner_id, "display_name": owner_user}
        events = (
            db.query(models.LocalEvent)
            .filter(
                models.LocalEvent.calendar_id == cal.id,
                or_(
                    (models.LocalEvent.rrule == None) & (models.LocalEvent.start < end) & (models.LocalEvent.end > start),
                    models.LocalEvent.rrule != None,
                ),
            )
            .all()
        )
        for ev in events:
            creator_owner_id = ev.creator_id or owner_id
            # Private filtering for events that belong to someone else.
            if ev.is_private and creator_owner_id != current_user.id:
                vis = visibility_for(creator_owner_id)
                if vis == "hidden":
                    continue
            creator = None
            if ev.creator_id and name_cache.get(ev.creator_id):
                creator = {"id": ev.creator_id, "display_name": name_cache[ev.creator_id]}
            elif ev.creator_name_external:
                creator = {"id": None, "display_name": f"{ev.creator_name_external} (importiert)"}

            if ev.rrule:
                built = expand_recurring_local(ev, cal, start_dt, end_dt, creator=creator, owner=owner, is_group_event=is_group)
            else:
                built = [build_local_event_dict(ev, cal, rrule=None, creator=creator, owner=owner, is_group_event=is_group)]

            for b in built:
                if ev.is_private and creator_owner_id != current_user.id and visibility_for(creator_owner_id) == "busy":
                    b = _strip_busy(b)
                all_events.append(b)

    # Each member shares exactly one calendar into their groups, chosen in their
    # settings (group_visible_calendar_id). Only that calendar is overlaid.
    for m in members:
        settings = (
            db.query(models.UserSettings)
            .filter(models.UserSettings.user_id == m.user_id)
            .first()
        )
        visible_id = settings.group_visible_calendar_id if settings else None
        if visible_id is None or visible_id == group_cal_id:
            continue
        cal = (
            db.query(models.LocalCalendar)
            .filter(
                models.LocalCalendar.id == visible_id,
                models.LocalCalendar.user_id == m.user_id,  # must be the member's own
            )
            .first()
        )
        if cal:
            emit_calendar(cal, m.user_id, is_group=False)

    # The group calendar itself.
    if group_cal_id is not None:
        group_cal = db.query(models.LocalCalendar).filter(models.LocalCalendar.id == group_cal_id).first()
        if group_cal:
            emit_calendar(group_cal, group_cal.user_id, is_group=True)

    return {"events": all_events}
