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
def status(db: Session = Depends(get_db),
           current_user: models.User = Depends(get_current_user)):
    acc = mail_invites.get_account(db)
    return {
        "imap_configured": acc is not None,
        "smtp_configured": bool(acc and acc.smtp_host),
        "last_run": acc.last_run.isoformat() if acc and acc.last_run else None,
        "last_error": acc.last_error if acc else None,
    }


# ── Mailbox configuration ─────────────────────────────────
#
# One mailbox per instance: it is a shared forwarding target, not a per-user
# account, so only administrators may see or change it.


def _require_admin(user: models.User) -> None:
    if not user.is_admin:
        raise HTTPException(403, "Nur für Administratoren")


def _mailbox_dict(acc) -> dict | None:
    if acc is None:
        return None
    # Passwords are never returned, the same as the CalDAV account endpoints.
    return {
        "id": acc.id,
        "enabled": bool(acc.enabled),
        "imap_host": acc.imap_host,
        "imap_port": acc.imap_port,
        "imap_ssl": bool(acc.imap_ssl),
        "imap_user": acc.imap_user,
        "imap_folder": acc.imap_folder,
        "poll_minutes": acc.poll_minutes,
        "has_imap_password": bool(acc.imap_password),
        "smtp_host": acc.smtp_host,
        "smtp_port": acc.smtp_port,
        "smtp_ssl": bool(acc.smtp_ssl),
        "smtp_user": acc.smtp_user,
        "smtp_from": acc.smtp_from,
        "has_smtp_password": bool(acc.smtp_password),
        "last_run": acc.last_run.isoformat() if acc.last_run else None,
        "last_error": acc.last_error,
    }


class MailboxUpdate(BaseModel):
    enabled: bool = True
    imap_host: str
    imap_port: int = 993
    imap_ssl: bool = True
    imap_user: str
    # Optional on edit: left out keeps the stored one, so changing a port does
    # not mean retyping the password.
    imap_password: Optional[str] = None
    imap_folder: str = "INBOX"
    poll_minutes: int = 5
    smtp_host: Optional[str] = None
    smtp_port: Optional[int] = 587
    smtp_ssl: Optional[bool] = False
    smtp_user: Optional[str] = None
    smtp_password: Optional[str] = None
    smtp_from: Optional[str] = None


@router.get("/mailbox")
def get_mailbox(db: Session = Depends(get_db),
                current_user: models.User = Depends(get_current_user)):
    _require_admin(current_user)
    return _mailbox_dict(
        db.query(models.MailboxAccount).order_by(models.MailboxAccount.id).first())


@router.put("/mailbox")
def set_mailbox(data: MailboxUpdate, db: Session = Depends(get_db),
                current_user: models.User = Depends(get_current_user)):
    _require_admin(current_user)
    acc = db.query(models.MailboxAccount).order_by(models.MailboxAccount.id).first()
    if acc is None:
        acc = models.MailboxAccount(imap_host="", imap_user="", imap_password="")
        db.add(acc)

    if not data.imap_password and not acc.imap_password:
        raise HTTPException(422, "Passwort fehlt")
    if not 1 <= data.poll_minutes <= 1440:
        raise HTTPException(422, "Abrufintervall muss zwischen 1 und 1440 Minuten liegen")

    acc.enabled = data.enabled
    acc.imap_host = data.imap_host.strip()
    acc.imap_port = data.imap_port
    acc.imap_ssl = data.imap_ssl
    acc.imap_user = data.imap_user.strip()
    if data.imap_password:
        acc.imap_password = data.imap_password
    acc.imap_folder = (data.imap_folder or "INBOX").strip()
    acc.poll_minutes = data.poll_minutes
    acc.smtp_host = (data.smtp_host or "").strip() or None
    acc.smtp_port = data.smtp_port
    acc.smtp_ssl = bool(data.smtp_ssl)
    acc.smtp_user = (data.smtp_user or "").strip() or None
    if data.smtp_password:
        acc.smtp_password = data.smtp_password
    acc.smtp_from = (data.smtp_from or "").strip() or None
    # Settings changed, so whatever went wrong before is no longer current.
    acc.last_error = None
    db.commit()
    return _mailbox_dict(acc)


@router.delete("/mailbox")
def delete_mailbox(db: Session = Depends(get_db),
                   current_user: models.User = Depends(get_current_user)):
    _require_admin(current_user)
    acc = db.query(models.MailboxAccount).order_by(models.MailboxAccount.id).first()
    if acc:
        db.delete(acc)
        db.commit()
    return {"ok": True}


@router.post("/poll")
def poll_now(db: Session = Depends(get_db),
             current_user: models.User = Depends(get_current_user)):
    """Fetch right now instead of waiting for the scheduler."""
    _require_admin(current_user)
    if not mail_invites.is_configured(db):
        raise HTTPException(400, "Kein Postfach konfiguriert")
    mail_invites.fetch_invites(db)
    acc = mail_invites.get_account(db)
    return {"ok": True, "last_error": acc.last_error if acc else None}
