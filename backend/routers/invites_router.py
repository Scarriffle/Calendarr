"""Invitations that arrived by mail: list them, accept or decline, dismiss.

The decision is the only thing that turns an invitation into a calendar entry.
Everything a mail can do on its own stops at the event_invites table.
"""

import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

import mail_invites
import models
import permissions
from auth import get_current_user
from database import get_db

logger = logging.getLogger(__name__)

router = APIRouter()


def _invite_dict(inv: models.EventInvite) -> dict:
    return {
        "id": inv.id,
        "uid": inv.uid,
        "status": inv.status,
        "title": inv.title,
        "start": inv.start,
        "end": inv.end,
        "all_day": bool(inv.all_day),
        "location": inv.location,
        "description": inv.description,
        "rrule": inv.rrule,
        "organizer_email": inv.organizer_email,
        "organizer_name": inv.organizer_name,
        "attendee_email": inv.attendee_email,
        "reply_state": inv.reply_state,
        "received_at": inv.received_at.isoformat() if inv.received_at else None,
    }


def _own_invite(db: Session, user: models.User, invite_id: int) -> models.EventInvite:
    inv = (db.query(models.EventInvite)
             .filter(models.EventInvite.id == invite_id,
                     models.EventInvite.user_id == user.id).first())
    if inv is None:
        raise HTTPException(404, "Einladung nicht gefunden")
    return inv


def _default_invite_calendar(db: Session, user: models.User) -> models.LocalCalendar:
    """Where an accepted invitation lands when the client names no calendar.

    The user's own, non-birthday calendar with the lowest id — the same one they
    would have picked by hand in almost every case. A birthday calendar is
    excluded because the server injects reminders into those.
    """
    cal = (db.query(models.LocalCalendar)
             .filter(models.LocalCalendar.user_id == user.id,
                     models.LocalCalendar.is_birthday.isnot(True))
             .order_by(models.LocalCalendar.id).first())
    if cal:
        return cal
    cal = models.LocalCalendar(user_id=user.id, name="Einladungen", color="#4285f4")
    db.add(cal)
    db.flush()
    return cal


@router.get("")
def list_invites(db: Session = Depends(get_db),
                 current_user: models.User = Depends(get_current_user)):
    """Everything still awaiting a decision, plus withdrawn ones.

    Cancelled invitations stay visible on purpose: a withdrawal the user never
    sees is worse than one more row to dismiss.
    """
    rows = (db.query(models.EventInvite)
              .filter(models.EventInvite.user_id == current_user.id,
                      models.EventInvite.status.in_(("pending", "cancelled")))
              .order_by(models.EventInvite.start).all())
    return [_invite_dict(i) for i in rows]


class InviteRespond(BaseModel):
    action: str                      # accept | decline
    calendar_id: Optional[int] = None


@router.post("/{invite_id}/respond")
def respond(invite_id: int, data: InviteRespond,
            db: Session = Depends(get_db),
            current_user: models.User = Depends(get_current_user)):
    inv = _own_invite(db, current_user, invite_id)
    if data.action not in ("accept", "decline"):
        raise HTTPException(422, "action muss accept oder decline sein")
    if inv.status == "cancelled":
        raise HTTPException(409, "Die Einladung wurde zurückgezogen.")

    cal = None
    if data.action == "accept":
        # The target is checked server-side; a client cannot name a calendar it
        # may not write to.
        cal = (permissions.accessible_local_calendar(db, current_user, data.calendar_id,
                                                     require_write=True)
               if data.calendar_id else _default_invite_calendar(db, current_user))
        mail_invites.upsert_event(db, inv, cal)
        inv.status = "accepted"
    else:
        mail_invites.drop_event(db, inv)
        inv.status = "declined"

    # Committed before any mail is attempted: a broken SMTP must never roll back
    # a decision the user already made.
    db.commit()
    return {"ok": True, "status": inv.status, "reply_state": inv.reply_state,
            "calendar_id": cal.id if cal else None}


@router.delete("/{invite_id}")
def dismiss(invite_id: int, db: Session = Depends(get_db),
            current_user: models.User = Depends(get_current_user)):
    """Clear an invitation from the list. An accepted event stays."""
    inv = _own_invite(db, current_user, invite_id)
    db.delete(inv)
    db.commit()
    return {"ok": True}


@router.get("/status")
def status(current_user: models.User = Depends(get_current_user)):
    return {"imap_configured": mail_invites.is_configured()}


@router.post("/poll")
def poll_now(db: Session = Depends(get_db),
             current_user: models.User = Depends(get_current_user)):
    """Fetch right now instead of waiting for the scheduler.

    Admin-only: it opens a connection to the shared mailbox, so it is not a
    per-user action.
    """
    if not current_user.is_admin:
        raise HTTPException(403, "Nur für Administratoren")
    if not mail_invites.is_configured():
        raise HTTPException(400, "Kein Postfach konfiguriert")
    mail_invites.fetch_invites(db)
    return {"ok": True}
