"""Invitations arriving by mail.

The mailbox is never touched here — ingest_ics is fed directly, because what
matters is what an iCalendar payload from a stranger is allowed to do, not
whether imaplib works.
"""

import mail_invites
import models
from conftest import auth, register_admin
from database import SessionLocal


def _ics(uid="meet-1", sequence=0, method="REQUEST", attendee="admin@example.com",
         summary="Projektbesprechung", start="20260601T090000Z", end="20260601T100000Z"):
    return (
        "BEGIN:VCALENDAR\r\n"
        "VERSION:2.0\r\n"
        "PRODID:-//Test//EN\r\n"
        f"METHOD:{method}\r\n"
        "BEGIN:VEVENT\r\n"
        f"UID:{uid}\r\n"
        f"SEQUENCE:{sequence}\r\n"
        f"SUMMARY:{summary}\r\n"
        f"DTSTART:{start}\r\n"
        f"DTEND:{end}\r\n"
        "ORGANIZER;CN=Chefin:mailto:chefin@example.org\r\n"
        f"ATTENDEE;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:{attendee}\r\n"
        "END:VEVENT\r\n"
        "END:VCALENDAR\r\n"
    ).encode()


def _admin_with_email(client, address="admin@example.com"):
    token = register_admin(client)
    db = SessionLocal()
    try:
        user = db.query(models.User).filter(models.User.username == "admin").first()
        user.email = address
        db.commit()
        return token, user.id
    finally:
        db.close()


def _ingest(payload):
    db = SessionLocal()
    try:
        return mail_invites.ingest_ics(db, payload)
    finally:
        db.close()


def test_parser_exposes_the_itip_fields():
    import ical_io

    parsed = ical_io.parse_ics(_ics(sequence=3))
    assert parsed["method"] == "REQUEST"
    item = parsed["events"][0]
    assert item["sequence"] == 3
    assert item["organizer_email"] == "chefin@example.org"
    assert item["attendees"][0]["email"] == "admin@example.com"
    assert item["attendees"][0]["partstat"] == "NEEDS-ACTION"
    assert item["attendees"][0]["rsvp"] is True


def test_invitation_lands_as_pending(client):
    token, _ = _admin_with_email(client)
    assert _ingest(_ics()) is True

    rows = client.get("/api/invites", headers=auth(token)).json()
    assert len(rows) == 1
    assert rows[0]["status"] == "pending"
    assert rows[0]["title"] == "Projektbesprechung"
    assert rows[0]["organizer_email"] == "chefin@example.org"


def test_a_mail_alone_creates_no_event(client):
    """The whole security model in one assertion."""
    token, _ = _admin_with_email(client)
    _ingest(_ics())

    db = SessionLocal()
    try:
        assert db.query(models.LocalEvent).count() == 0
    finally:
        db.close()


def test_unknown_attendee_is_ignored(client):
    register_admin(client)   # no email set, so nothing matches
    assert _ingest(_ics(attendee="someone-else@example.net")) is False


def test_from_header_cannot_route(client):
    """Routing is by ATTENDEE only; a sender can claim anything."""
    token, _ = _admin_with_email(client)
    assert _ingest(_ics(attendee="stranger@example.net")) is False
    assert client.get("/api/invites", headers=auth(token)).json() == []


def test_same_sequence_is_ignored(client):
    token, _ = _admin_with_email(client)
    _ingest(_ics(summary="Erste Fassung"))
    _ingest(_ics(summary="Zweite Fassung"))   # forwarded twice

    rows = client.get("/api/invites", headers=auth(token)).json()
    assert len(rows) == 1
    assert rows[0]["title"] == "Erste Fassung"


def test_higher_sequence_reopens_an_answered_invitation(client):
    token, _ = _admin_with_email(client)
    _ingest(_ics())
    invite_id = client.get("/api/invites", headers=auth(token)).json()[0]["id"]
    client.post(f"/api/invites/{invite_id}/respond", json={"action": "accept"},
                headers=auth(token))

    _ingest(_ics(sequence=1, summary="Verschoben"))

    rows = client.get("/api/invites", headers=auth(token)).json()
    assert len(rows) == 1
    assert rows[0]["status"] == "pending"
    assert rows[0]["title"] == "Verschoben"


def test_accepting_creates_the_event(client):
    token, _ = _admin_with_email(client)
    _ingest(_ics())
    invite_id = client.get("/api/invites", headers=auth(token)).json()[0]["id"]

    res = client.post(f"/api/invites/{invite_id}/respond", json={"action": "accept"},
                      headers=auth(token))
    assert res.status_code == 200
    assert res.json()["status"] == "accepted"

    db = SessionLocal()
    try:
        ev = db.query(models.LocalEvent).one()
        assert ev.title == "Projektbesprechung"
        assert ev.external_uid == "invite:meet-1"
        assert ev.uid != "meet-1"      # never the organiser's UID
    finally:
        db.close()
    assert client.get("/api/invites", headers=auth(token)).json() == []


def test_invitation_cannot_overwrite_an_existing_event(client):
    """The test that matters: a colliding UID must not touch what is there."""
    token, user_id = _admin_with_email(client)
    db = SessionLocal()
    try:
        cal = models.LocalCalendar(user_id=user_id, name="Privat", color="#4285f4")
        db.add(cal)
        db.flush()
        db.add(models.LocalEvent(calendar_id=cal.id, uid="meet-1", title="Mein Termin",
                                 start="2026-06-01T09:00:00+00:00",
                                 end="2026-06-01T10:00:00+00:00"))
        db.commit()
    finally:
        db.close()

    _ingest(_ics(uid="meet-1", summary="Fremder Termin"))
    invite_id = client.get("/api/invites", headers=auth(token)).json()[0]["id"]
    client.post(f"/api/invites/{invite_id}/respond", json={"action": "accept"},
                headers=auth(token))

    db = SessionLocal()
    try:
        mine = db.query(models.LocalEvent).filter(models.LocalEvent.uid == "meet-1").one()
        assert mine.title == "Mein Termin"          # untouched
        assert db.query(models.LocalEvent).count() == 2
    finally:
        db.close()


def test_declining_creates_nothing(client):
    token, _ = _admin_with_email(client)
    _ingest(_ics())
    invite_id = client.get("/api/invites", headers=auth(token)).json()[0]["id"]

    client.post(f"/api/invites/{invite_id}/respond", json={"action": "decline"},
                headers=auth(token))

    db = SessionLocal()
    try:
        assert db.query(models.LocalEvent).count() == 0
    finally:
        db.close()


def test_cancel_removes_an_accepted_event(client):
    token, _ = _admin_with_email(client)
    _ingest(_ics())
    invite_id = client.get("/api/invites", headers=auth(token)).json()[0]["id"]
    client.post(f"/api/invites/{invite_id}/respond", json={"action": "accept"},
                headers=auth(token))

    _ingest(_ics(method="CANCEL", sequence=1))

    db = SessionLocal()
    try:
        assert db.query(models.LocalEvent).count() == 0
    finally:
        db.close()
    rows = client.get("/api/invites", headers=auth(token)).json()
    assert rows[0]["status"] == "cancelled"   # stays visible, not silently gone


def test_reply_and_publish_are_not_invitations(client):
    _admin_with_email(client)
    assert _ingest(_ics(method="REPLY")) is False
    assert _ingest(_ics(method="PUBLISH")) is False


def test_oversized_payload_is_refused(client):
    _admin_with_email(client)
    padded = _ics(summary="X" * (mail_invites.MAX_ICS_BYTES + 10))
    assert _ingest(padded) is False


# ── Mailbox configuration ─────────────────────────────────


def _mailbox_payload(**over):
    body = {"imap_host": "imap.example.com", "imap_user": "einladungen@example.com",
            "imap_password": "geheim", "imap_port": 993, "poll_minutes": 5}
    body.update(over)
    return body


def test_mailbox_password_is_never_returned(client):
    token = register_admin(client)
    client.put("/api/invites/mailbox", json=_mailbox_payload(), headers=auth(token))

    body = client.get("/api/invites/mailbox", headers=auth(token)).json()
    assert body["imap_host"] == "imap.example.com"
    assert body["has_imap_password"] is True
    assert "imap_password" not in body


def test_editing_without_a_password_keeps_the_stored_one(client):
    token = register_admin(client)
    client.put("/api/invites/mailbox", json=_mailbox_payload(), headers=auth(token))
    client.put("/api/invites/mailbox",
               json=_mailbox_payload(imap_password=None, imap_port=143),
               headers=auth(token))

    db = SessionLocal()
    try:
        acc = db.query(models.MailboxAccount).one()
        assert acc.imap_port == 143
        assert acc.imap_password == "geheim"
    finally:
        db.close()


def test_first_save_requires_a_password(client):
    token = register_admin(client)
    res = client.put("/api/invites/mailbox", json=_mailbox_payload(imap_password=None),
                     headers=auth(token))
    assert res.status_code == 422


def test_only_admins_touch_the_mailbox(client):
    from conftest import create_user

    admin = register_admin(client)
    user = create_user(client, admin, "lisa")
    assert client.get("/api/invites/mailbox", headers=auth(user)).status_code == 403
    assert client.put("/api/invites/mailbox", json=_mailbox_payload(),
                      headers=auth(user)).status_code == 403


def test_disabled_mailbox_counts_as_unconfigured(client):
    token = register_admin(client)
    client.put("/api/invites/mailbox", json=_mailbox_payload(enabled=False),
               headers=auth(token))

    assert client.get("/api/invites/status", headers=auth(token)).json()["imap_configured"] is False

    db = SessionLocal()
    try:
        assert mail_invites.get_account(db) is None
    finally:
        db.close()
