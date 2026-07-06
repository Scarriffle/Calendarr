"""Central access control for local calendars.

Local calendars are visible/writable to a user if any of the following holds:
  - the user owns the calendar (LocalCalendar.user_id),
  - the calendar is shared with the user (calendar_shares; write needs 'read_write'),
  - the calendar is a group calendar and the user is a member of that group
    (members get read & write).

These helpers replace the scattered owner-only filters so sharing and groups
work consistently across every local-calendar endpoint and the event merge read.
"""

from typing import Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session

import models


def _share_for(db: Session, calendar_id: int, user_id: int) -> Optional[models.CalendarShare]:
    return (
        db.query(models.CalendarShare)
        .filter(
            models.CalendarShare.calendar_id == calendar_id,
            models.CalendarShare.user_id == user_id,
        )
        .first()
    )


def _is_group_calendar_member(db: Session, calendar_id: int, user_id: int) -> bool:
    gc = (
        db.query(models.GroupCalendar)
        .filter(models.GroupCalendar.calendar_id == calendar_id)
        .first()
    )
    if not gc:
        return False
    member = (
        db.query(models.GroupMember)
        .filter(
            models.GroupMember.group_id == gc.group_id,
            models.GroupMember.user_id == user_id,
        )
        .first()
    )
    return member is not None


def accessible_local_calendar(
    db: Session,
    user: models.User,
    calendar_id: int,
    *,
    require_write: bool = False,
) -> models.LocalCalendar:
    """Return the calendar if the user may access it, else raise 404/403.

    404 when the calendar does not exist or is not visible to the user (so we
    don't leak existence). 403 when it is visible (read) but write is required.
    """
    cal = (
        db.query(models.LocalCalendar)
        .filter(models.LocalCalendar.id == calendar_id)
        .first()
    )
    if not cal:
        raise HTTPException(404, "Calendar not found")

    if cal.user_id == user.id:
        return cal  # owner: full access

    if _is_group_calendar_member(db, calendar_id, user.id):
        return cal  # group members get read & write

    share = _share_for(db, calendar_id, user.id)
    if share is None:
        raise HTTPException(404, "Calendar not found")
    if require_write and share.permission != "read_write":
        raise HTTPException(403, "You only have read access to this calendar")
    return cal


def is_calendar_owner(db: Session, user: models.User, calendar_id: int) -> models.LocalCalendar:
    """Return the calendar only if the user owns it, else raise 404."""
    cal = (
        db.query(models.LocalCalendar)
        .filter(
            models.LocalCalendar.id == calendar_id,
            models.LocalCalendar.user_id == user.id,
        )
        .first()
    )
    if not cal:
        raise HTTPException(404, "Calendar not found")
    return cal


def co_member_group_visible_calendars(db: Session, user: models.User) -> list[models.LocalCalendar]:
    """Calendars that co-members of the user's groups share into the group.

    Each user designates ONE of their own calendars via
    UserSettings.group_visible_calendar_id. This returns those calendars for
    every co-member of any group the user belongs to (excluding the user's own).
    The calendar must be owned by the designating member. Deduped (each calendar
    appears once even across multiple shared groups).
    """
    my_group_ids = (
        db.query(models.GroupMember.group_id)
        .filter(models.GroupMember.user_id == user.id)
    )
    co_member_ids = (
        db.query(models.GroupMember.user_id)
        .filter(
            models.GroupMember.group_id.in_(my_group_ids),
            models.GroupMember.user_id != user.id,
        )
        .distinct()
    )
    return (
        db.query(models.LocalCalendar)
        .join(
            models.UserSettings,
            models.UserSettings.group_visible_calendar_id == models.LocalCalendar.id,
        )
        .filter(
            models.UserSettings.user_id.in_(co_member_ids),
            # the designating member must own the calendar they share
            models.LocalCalendar.user_id == models.UserSettings.user_id,
        )
        .all()
    )


def readable_local_calendar_ids(db: Session, user: models.User) -> list[int]:
    """All local calendar ids the user may read: own + shared + group + co-member group-visible."""
    ids: set[int] = set()

    own = (
        db.query(models.LocalCalendar.id)
        .filter(models.LocalCalendar.user_id == user.id)
        .all()
    )
    ids.update(r[0] for r in own)

    shared = (
        db.query(models.CalendarShare.calendar_id)
        .filter(models.CalendarShare.user_id == user.id)
        .all()
    )
    ids.update(r[0] for r in shared)

    group_cals = (
        db.query(models.GroupCalendar.calendar_id)
        .join(models.GroupMember, models.GroupMember.group_id == models.GroupCalendar.group_id)
        .filter(models.GroupMember.user_id == user.id)
        .all()
    )
    ids.update(r[0] for r in group_cals)

    # Calendars co-members share into shared groups (group-visible).
    ids.update(c.id for c in co_member_group_visible_calendars(db, user))

    return list(ids)
