"""Pull iTIP invitations out of a watched mailbox.

A mailbox is a trust boundary this app did not have before: anyone who knows the
address can hand the server an iCalendar file. So the rule throughout is that a
mail can only ever create a row in ``event_invites``. No calendar read path
touches that table — an invitation becomes an event when a human accepts it, and
not before.

Credentials live in the environment, never in the database. The service already
loads an EnvironmentFile, and this keeps the one secret that grants access to a
whole mailbox out of a table that an endpoint could return.

Single process assumed, same as the rest of the scheduler (see scheduler.py).
"""

from __future__ import annotations

import contextlib
import imaplib
import logging
import os
import re
import uuid
from datetime import datetime, timezone
from email import message_from_bytes
from email.message import EmailMessage

from sqlalchemy import func
from sqlalchemy.orm import Session

import dav_util
import ical_io
import models

logger = logging.getLogger(__name__)

# An invitation is a few kilobytes. These caps exist so one oversized mail
# cannot exhaust memory, and so a flooded mailbox cannot monopolise a run.
MAX_MESSAGE_BYTES = 1 * 1024 * 1024
MAX_ICS_BYTES = 256 * 1024
MAX_MESSAGES_PER_RUN = 25
MAX_CAL_PARTS = 3

# Checked before an address is ever put into a mail header. Rejecting the
# characters that could break a header out is cheaper than trusting the
# formatter, and EmailMessage refuses embedded newlines on top of it.
_ADDR_RE = re.compile(r"^[^@\s<>\",;:]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$")

_HANDLED_METHODS = ("REQUEST", "CANCEL")


def is_configured() -> bool:
    return bool(os.environ.get("IMAP_HOST"))


def _valid_address(addr: str | None) -> str | None:
    if not addr:
        return None
    addr = addr.strip().lower()
    return addr if _ADDR_RE.match(addr) else None


def user_for_address(db: Session, addr: str | None):
    """The user who owns this address, or None.

    Reads the dedicated table and `users.email` both, so someone whose
    invitation address is already in their profile needs no extra setup.
    """
    addr = _valid_address(addr)
    if not addr:
        return None
    row = (db.query(models.UserEmailAddress)
             .filter(models.UserEmailAddress.address == addr).first())
    if row:
        return row.user
    return (db.query(models.User)
              .filter(func.lower(models.User.email) == addr).first())


# ── Ingest ────────────────────────────────────────────────


def _match_attendee(db: Session, item: dict):
    """Which user this invitation is for, read from the ATTENDEE list.

    Never from the From header: a mail can claim any sender it likes, and that
    header is what an attacker controls. The ATTENDEE list is what the organiser
    put in the payload, matched against addresses a user has proven are theirs.
    """
    # Our own invitation coming back to us is not an invitation to accept.
    if user_for_address(db, item.get("organizer_email")):
        return None, None
    for att in item.get("attendees") or ():
        user = user_for_address(db, att.get("email"))
        if user:
            return user, _valid_address(att.get("email"))
    return None, None


def _apply_request(db: Session, user, attendee: str, item: dict, raw_ics: str) -> None:
    inv = (db.query(models.EventInvite)
             .filter(models.EventInvite.user_id == user.id,
                     models.EventInvite.uid == item["uid"]).first())
    sequence = int(item.get("sequence") or 0)
    if inv and sequence <= inv.sequence and inv.status != "cancelled":
        return  # Forwarded mail arrives twice; the same SEQUENCE is the same news.

    if inv is None:
        inv = models.EventInvite(user_id=user.id, uid=item["uid"])
        db.add(inv)

    inv.sequence = sequence
    inv.title = (item.get("title") or "(ohne Titel)")[:255]
    inv.start = item["start"]
    inv.end = item["end"]
    inv.all_day = bool(item.get("all_day"))
    inv.location = (item.get("location") or None) and item["location"][:500]
    inv.description = (item.get("description") or None) and item["description"][:8000]
    inv.rrule = item.get("rrule")
    inv.organizer_email = _valid_address(item.get("organizer_email"))
    inv.organizer_name = (item.get("organizer") or None) and item["organizer"][:255]
    inv.attendee_email = attendee
    inv.raw_ics = raw_ics
    inv.received_at = datetime.now(timezone.utc)
    # A changed invitation is a new decision, so an already answered one goes
    # back to pending. The event created earlier stays until the user answers
    # again — this never rewrites a calendar entry behind their back.
    inv.status = "pending"
    inv.reply_state = None
    db.commit()
    logger.info("Einladung %s für Nutzer %s gespeichert (SEQUENCE %s)",
                item["uid"], user.id, sequence)


def _apply_cancel(db: Session, user, item: dict) -> None:
    inv = (db.query(models.EventInvite)
             .filter(models.EventInvite.user_id == user.id,
                     models.EventInvite.uid == item["uid"]).first())
    if inv is None:
        return
    drop_event(db, inv)
    inv.status = "cancelled"
    db.commit()
    logger.info("Einladung %s zurückgezogen", item["uid"])


def drop_event(db: Session, inv) -> None:
    """Remove the event an acceptance created, if it still exists."""
    if not inv.event_id:
        return
    ev = db.query(models.LocalEvent).filter(models.LocalEvent.id == inv.event_id).first()
    if ev:
        cal = (db.query(models.LocalCalendar)
                 .filter(models.LocalCalendar.id == ev.calendar_id).first())
        db.delete(ev)
        if cal:
            dav_util.bump_dav(cal)
    inv.event_id = None


def ingest_ics(db: Session, raw: bytes) -> bool:
    """Store one invitation from an iCalendar payload. True when something was."""
    if len(raw) > MAX_ICS_BYTES:
        logger.info("Kalenderteil zu groß (%s Bytes), übersprungen", len(raw))
        return False
    try:
        parsed = ical_io.parse_ics(raw)
    except ValueError:
        return False

    method = (parsed.get("method") or "").upper()
    if method not in _HANDLED_METHODS:
        return False  # REPLY/COUNTER/PUBLISH: we are never the organiser.

    text = raw.decode("utf-8", "replace")
    for item in parsed.get("events") or ():
        if item.get("recurrence_id"):
            # One occurrence of a series. Applying it as the whole series would
            # silently move every other date.
            logger.info("Einzeltermin einer Serie übersprungen (UID %s)", item.get("uid"))
            continue
        user, attendee = _match_attendee(db, item)
        if not user:
            continue
        if method == "CANCEL":
            _apply_cancel(db, user, item)
        else:
            _apply_request(db, user, attendee, item, text)
        return True  # One invitation per mail; never a bulk import.
    return False


# ── Mailbox ───────────────────────────────────────────────


def _connect() -> imaplib.IMAP4:
    host = os.environ["IMAP_HOST"]
    port = int(os.environ.get("IMAP_PORT", "993"))
    use_ssl = os.environ.get("IMAP_SSL", "1") != "0"
    box = (imaplib.IMAP4_SSL(host, port, timeout=30) if use_ssl
           else imaplib.IMAP4(host, port, timeout=30))
    box.login(os.environ["IMAP_USER"], os.environ["IMAP_PASSWORD"])
    return box


def _calendar_parts(msg) -> list[bytes]:
    """Every iCalendar payload in a mail, capped.

    Senders disagree on the content type: a proper invitation is text/calendar,
    but plenty of clients attach it as application/ics or just a .ics file.
    """
    out: list[bytes] = []
    for part in msg.walk():
        if len(out) >= MAX_CAL_PARTS:
            break
        ctype = (part.get_content_type() or "").lower()
        name = (part.get_filename() or "").lower()
        if ctype in ("text/calendar", "application/ics") or name.endswith(".ics"):
            try:
                payload = part.get_payload(decode=True)
            except Exception:
                continue
            if payload:
                out.append(payload)
    return out


def _handle_message(db: Session, box: imaplib.IMAP4, uid: bytes) -> None:
    typ, size_data = box.uid("FETCH", uid, "(RFC822.SIZE)")
    if typ == "OK" and size_data and size_data[0]:
        m = re.search(rb"RFC822\.SIZE (\d+)", size_data[0])
        if m and int(m.group(1)) > MAX_MESSAGE_BYTES:
            logger.info("Mail %s zu groß (%s Bytes), übersprungen", uid, m.group(1))
            return

    # PEEK: a plain FETCH sets \Seen on the server even if we crash afterwards,
    # which would lose the invitation entirely.
    typ, data = box.uid("FETCH", uid, "(BODY.PEEK[])")
    if typ != "OK" or not data or not data[0]:
        return
    msg = message_from_bytes(data[0][1])

    for payload in _calendar_parts(msg):
        if ingest_ics(db, payload):
            return


def fetch_invites(db: Session) -> None:
    """Scheduler job: read new mail and store any invitations it holds."""
    if not is_configured():
        return
    box = _connect()
    try:
        box.select(os.environ.get("IMAP_FOLDER", "INBOX"))
        # UID commands, not sequence numbers: those shift when a message is
        # expunged mid-run and we would read the wrong mail.
        typ, data = box.uid("SEARCH", None, "UNSEEN")
        if typ != "OK":
            logger.warning("IMAP SEARCH fehlgeschlagen: %s", typ)
            return
        uids = (data[0] or b"").split()[:MAX_MESSAGES_PER_RUN]
        for uid in uids:
            try:
                _handle_message(db, box, uid)
            except Exception:
                logger.exception("Einladungsmail %s nicht verarbeitbar", uid)
                with contextlib.suppress(Exception):
                    db.rollback()
            finally:
                # Advertising and broken mail get marked too, or every run
                # retries them forever. Nothing is ever deleted.
                with contextlib.suppress(Exception):
                    box.uid("STORE", uid, "+FLAGS", "\\Seen")
    finally:
        with contextlib.suppress(Exception):
            box.logout()


# ── Accepting ─────────────────────────────────────────────


def upsert_event(db: Session, inv, cal) -> models.LocalEvent:
    """Create or update the event an acceptance produces.

    The event gets a fresh UID. LocalEvent.uid is globally unique, so reusing
    the organiser's would let a mail collide with — and refuse to coexist
    alongside — an event that is already there. The organiser's UID goes to
    external_uid, which is what the rest of the app already uses for
    "this came from somewhere else".
    """
    ev = None
    if inv.event_id:
        ev = db.query(models.LocalEvent).filter(models.LocalEvent.id == inv.event_id).first()
    if ev is None:
        ev = models.LocalEvent(uid=str(uuid.uuid4()),
                               external_uid=f"invite:{inv.uid}",
                               creator_id=inv.user_id)
        db.add(ev)
    ev.calendar_id = cal.id
    ev.title = inv.title
    ev.start = inv.start
    ev.end = inv.end
    ev.all_day = bool(inv.all_day)
    ev.location = inv.location
    ev.description = inv.description
    ev.rrule = inv.rrule
    ev.creator_name_external = inv.organizer_name
    ev.etag = dav_util.new_tag()
    dav_util.bump_dav(cal)
    db.flush()
    inv.event_id = ev.id
    return ev
