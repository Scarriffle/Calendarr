"""Tests for sharing, group permissions, the iCal parser, and private filtering."""

from conftest import register_admin, create_user, auth

RANGE = {"start": "2026-06-01T00:00:00Z", "end": "2026-06-30T00:00:00Z"}


def _make_calendar(client, token, name="Cal"):
    r = client.post("/api/local/calendars", headers=auth(token), json={"name": name})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def _make_event(client, token, cal_id, title="Event", private=False,
                start="2026-06-10T10:00:00+00:00", end="2026-06-10T11:00:00+00:00"):
    r = client.post("/api/local/events", headers=auth(token), json={
        "calendar_id": cal_id, "title": title, "start": start, "end": end,
        "private": private,
    })
    assert r.status_code == 200, r.text
    return r.json()


# ── Sharing ───────────────────────────────────────────────

def test_share_read_then_read_write(client):
    admin = register_admin(client)
    b_id, b_tok = create_user(client, admin, "bob")

    cal_id = _make_calendar(client, admin, "Admins Kalender")
    ev = _make_event(client, admin, cal_id, "Meeting")

    # Creator field populated server-side.
    assert ev["creator"]["display_name"] == "admin"
    assert ev["type"] == "local"

    # Share read-only with bob.
    r = client.post(f"/api/local/calendars/{cal_id}/shares", headers=auth(admin),
                    json={"user_id": b_id, "permission": "read"})
    assert r.status_code == 200, r.text

    # Bob sees the shared calendar with shared_by.
    cals = client.get("/api/local/calendars", headers=auth(b_tok)).json()
    shared = [c for c in cals if not c["owned"]]
    assert len(shared) == 1
    assert shared[0]["shared_by"] == "admin"
    assert shared[0]["permission"] == "read"

    # Bob sees the event in the merged read.
    events = client.get("/api/caldav/events", headers=auth(b_tok), params=RANGE).json()["events"]
    assert any(e["title"] == "Meeting" for e in events)

    # Bob cannot write (read-only) -> 403.
    r = client.post("/api/local/events", headers=auth(b_tok), json={
        "calendar_id": cal_id, "title": "Nope",
        "start": "2026-06-11T10:00:00+00:00", "end": "2026-06-11T11:00:00+00:00",
    })
    assert r.status_code == 403, r.text

    # Upgrade to read_write -> bob can write.
    client.post(f"/api/local/calendars/{cal_id}/shares", headers=auth(admin),
                json={"user_id": b_id, "permission": "read_write"})
    r = client.post("/api/local/events", headers=auth(b_tok), json={
        "calendar_id": cal_id, "title": "Bobs Eintrag",
        "start": "2026-06-11T10:00:00+00:00", "end": "2026-06-11T11:00:00+00:00",
    })
    assert r.status_code == 200, r.text
    # Created by bob.
    assert r.json()["creator"]["display_name"] == "bob"


def test_non_owner_cannot_manage_shares(client):
    admin = register_admin(client)
    b_id, b_tok = create_user(client, admin, "bob")
    cal_id = _make_calendar(client, admin)
    # Bob (no access at all) cannot list shares -> 404 (existence hidden).
    r = client.get(f"/api/local/calendars/{cal_id}/shares", headers=auth(b_tok))
    assert r.status_code == 404


def test_unshared_calendar_invisible(client):
    admin = register_admin(client)
    _b_id, b_tok = create_user(client, admin, "bob")
    cal_id = _make_calendar(client, admin)
    _make_event(client, admin, cal_id, "Privat")
    events = client.get("/api/caldav/events", headers=auth(b_tok), params=RANGE).json()["events"]
    assert not any(e["title"] == "Privat" for e in events)


# ── Groups ────────────────────────────────────────────────

def test_group_create_and_members(client):
    admin = register_admin(client)
    b_id, b_tok = create_user(client, admin, "bob")
    c_id, c_tok = create_user(client, admin, "carol")

    r = client.post("/api/groups/", headers=auth(admin),
                    json={"name": "Familie", "member_ids": [b_id]})
    assert r.status_code == 200, r.text
    group = r.json()
    gid = group["id"]
    assert group["group_calendar_id"] is not None
    assert {m["display_name"] for m in group["members"]} == {"admin", "bob"}

    # Both members see the group.
    assert any(g["id"] == gid for g in client.get("/api/groups/", headers=auth(b_tok)).json())
    # Carol is not a member.
    assert not any(g["id"] == gid for g in client.get("/api/groups/", headers=auth(c_tok)).json())
    assert client.get(f"/api/groups/{gid}", headers=auth(c_tok)).status_code == 403

    # Only owner adds members.
    assert client.post(f"/api/groups/{gid}/members", headers=auth(b_tok),
                       json={"user_id": c_id}).status_code == 403
    assert client.post(f"/api/groups/{gid}/members", headers=auth(admin),
                       json={"user_id": c_id}).status_code == 200

    # Member can leave; owner cannot be removed.
    assert client.delete(f"/api/groups/{gid}/members/{c_id}", headers=auth(c_tok)).status_code == 200
    admin_id = client.get("/api/auth/me", headers=auth(admin)).json()["id"]
    assert client.delete(f"/api/groups/{gid}/members/{admin_id}", headers=auth(admin)).status_code == 422


def test_group_members_can_write_group_calendar(client):
    admin = register_admin(client)
    b_id, b_tok = create_user(client, admin, "bob")
    group = client.post("/api/groups/", headers=auth(admin),
                        json={"name": "Team", "member_ids": [b_id]}).json()
    gcal = group["group_calendar_id"]
    # Bob (member, not owner of the calendar) can create in the group calendar.
    r = client.post("/api/local/events", headers=auth(b_tok), json={
        "calendar_id": gcal, "title": "Teamtermin",
        "start": "2026-06-12T09:00:00+00:00", "end": "2026-06-12T10:00:00+00:00",
    })
    assert r.status_code == 200, r.text


def test_combined_view_marks_owner_and_group_event(client):
    admin = register_admin(client)
    b_id, b_tok = create_user(client, admin, "bob")
    group = client.post("/api/groups/", headers=auth(admin),
                        json={"name": "Team", "member_ids": [b_id]}).json()
    gid = group["id"]
    gcal = group["group_calendar_id"]

    # Bob's own calendar + event.
    b_cal = _make_calendar(client, b_tok, "Bobs Kalender")
    _make_event(client, b_tok, b_cal, "Bobs Termin")
    # A group-calendar event.
    _make_event(client, admin, gcal, "Gruppentermin")

    events = client.get(f"/api/groups/{gid}/combined", headers=auth(admin), params=RANGE).json()["events"]
    titles = {e["title"]: e for e in events}
    assert "Bobs Termin" in titles
    assert titles["Bobs Termin"]["owner"]["display_name"] == "bob"
    assert titles["Bobs Termin"].get("is_group_event") is not True
    assert "Gruppentermin" in titles
    assert titles["Gruppentermin"]["is_group_event"] is True


# ── Private filtering ─────────────────────────────────────

def _combined_titles(client, token, gid):
    evs = client.get(f"/api/groups/{gid}/combined", headers=auth(token), params=RANGE).json()["events"]
    return evs


def test_private_visibility_hidden_and_busy(client):
    admin = register_admin(client)
    b_id, b_tok = create_user(client, admin, "bob")
    group = client.post("/api/groups/", headers=auth(admin),
                        json={"name": "Team", "member_ids": [b_id]}).json()
    gid = group["id"]

    b_cal = _make_calendar(client, b_tok, "Bobs Kalender")
    _make_event(client, b_tok, b_cal, "Geheimes", private=True,
                start="2026-06-15T10:00:00+00:00", end="2026-06-15T11:00:00+00:00")

    # Bob sees his own private event in full.
    own = _combined_titles(client, b_tok, gid)
    assert any(e["title"] == "Geheimes" for e in own)

    # Default visibility = busy -> admin sees it as anonymous "Beschäftigt".
    seen = _combined_titles(client, admin, gid)
    busy = [e for e in seen if e["start"].startswith("2026-06-15")]
    assert busy and all(e["title"] == "Beschäftigt" for e in busy)
    assert all(e["location"] == "" and e["description"] == "" for e in busy)

    # Switch bob to hidden -> admin no longer sees it at all.
    client.put("/api/settings/", headers=auth(b_tok), json={"private_event_visibility": "hidden"})
    seen2 = _combined_titles(client, admin, gid)
    assert not any(e["start"].startswith("2026-06-15") for e in seen2)


def test_private_visibility_validation(client):
    admin = register_admin(client)
    r = client.put("/api/settings/", headers=auth(admin), json={"private_event_visibility": "bogus"})
    assert r.status_code == 422


# ── iCal import/export ────────────────────────────────────

SAMPLE_ICS = b"""BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test//EN
BEGIN:VEVENT
UID:evt-1@test
SUMMARY:Importiert 1
DTSTART:20260620T100000Z
DTEND:20260620T110000Z
LOCATION:Buero
ORGANIZER;CN=Max Mustermann:mailto:max@example.com
RRULE:FREQ=WEEKLY;BYDAY=MO
END:VEVENT
BEGIN:VEVENT
UID:evt-2@test
SUMMARY:Importiert 2
DTSTART;VALUE=DATE:20260621
DTEND;VALUE=DATE:20260622
END:VEVENT
END:VCALENDAR
"""


def test_ical_parser_roundtrip():
    import ical_io
    parsed = ical_io.parse_ics(SAMPLE_ICS)
    assert len(parsed["events"]) == 2
    ev1 = next(e for e in parsed["events"] if e["uid"] == "evt-1@test")
    assert ev1["title"] == "Importiert 1"
    assert ev1["location"] == "Buero"
    assert ev1["organizer"] == "Max Mustermann"
    assert ev1["rrule"] == "FREQ=WEEKLY;BYDAY=MO"
    ev2 = next(e for e in parsed["events"] if e["uid"] == "evt-2@test")
    assert ev2["all_day"] is True


def test_import_dedupes_by_uid(client):
    admin = register_admin(client)
    cal_id = _make_calendar(client, admin, "Import-Ziel")

    files = {"file": ("test.ics", SAMPLE_ICS, "text/calendar")}
    r = client.post(f"/api/local/calendars/{cal_id}/import", headers=auth(admin), files=files)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["imported"] == 2 and body["skipped"] == 0

    # Re-import -> all skipped (UID dedupe).
    files = {"file": ("test.ics", SAMPLE_ICS, "text/calendar")}
    r2 = client.post(f"/api/local/calendars/{cal_id}/import", headers=auth(admin), files=files)
    assert r2.json()["imported"] == 0 and r2.json()["skipped"] == 2

    # Imported events carry the external creator name.
    events = client.get("/api/caldav/events", headers=auth(admin), params=RANGE).json()["events"]
    imported = [e for e in events if e["title"] == "Importiert 1"]
    assert imported and imported[0]["creator"]["display_name"] == "Max Mustermann (importiert)"


def test_export_contains_organizer_and_rrule(client):
    admin = register_admin(client)
    cal_id = _make_calendar(client, admin, "Export-Test")
    _make_event(client, admin, cal_id, "Wöchentlich")
    # Add a recurring rule via update.
    events = client.get("/api/caldav/events", headers=auth(admin), params=RANGE).json()["events"]
    uid = next(e["id"] for e in events if e["title"] == "Wöchentlich")
    client.put(f"/api/local/events/{uid}", headers=auth(admin), json={"rrule": "FREQ=WEEKLY;BYDAY=MO"})

    r = client.get(f"/api/local/calendars/{cal_id}/export", headers=auth(admin))
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/calendar")
    body = r.text
    assert "BEGIN:VCALENDAR" in body
    assert "ORGANIZER" in body and "admin" in body
    assert "RRULE" in body


def test_import_export_only_local(client):
    """Import/export endpoints reject non-existent / inaccessible calendars."""
    admin = register_admin(client)
    _b, b_tok = create_user(client, admin, "bob")
    cal_id = _make_calendar(client, admin, "Privat")
    # Bob has no access -> 404 on export.
    assert client.get(f"/api/local/calendars/{cal_id}/export", headers=auth(b_tok)).status_code == 404
