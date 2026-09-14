"""Event attachments: content validation, storage and cleanup."""

import io
import os
import shutil
import time

import pytest
from fastapi import HTTPException
from PIL import Image

import attachments_store
import models
from conftest import auth, create_user, register_admin
from database import SessionLocal

RANGE = {"start": "2026-06-01T00:00:00Z", "end": "2026-06-30T00:00:00Z"}


@pytest.fixture(autouse=True)
def clean_attachment_dir():
    """conftest wipes the tables but not the files — without this the orphan
    sweep test would trip over leftovers from earlier tests."""
    for child in attachments_store.ATTACH_DIR.iterdir():
        shutil.rmtree(child, ignore_errors=True) if child.is_dir() else child.unlink()
    yield


# ── Fixtures for file bytes ───────────────────────────────

def png_bytes(size=(8, 8)) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, "red").save(buf, "PNG")
    return buf.getvalue()


PDF_BYTES = b"%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n"
TXT_BYTES = "Zugangsdaten: siehe Umschlag\n".encode("utf-8")


# ── Helpers ───────────────────────────────────────────────

def _make_calendar(client, token, name="Privat"):
    r = client.post("/api/local/calendars", headers=auth(token),
                    json={"name": name, "color": "#4285f4"})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def _make_event(client, token, cal_id, title="Termin"):
    r = client.post("/api/local/events", headers=auth(token), json={
        "calendar_id": cal_id, "title": title,
        "start": "2026-06-10T10:00:00+00:00", "end": "2026-06-10T11:00:00+00:00",
    })
    assert r.status_code == 200, r.text
    return r.json()


def _attach_row(event_uid, event_id, raw=PDF_BYTES, content_type="application/pdf",
                ext=".pdf", filename="Rechnung.pdf"):
    """Insert an attachment row and write its bytes, bypassing the API.

    Used by the cleanup tests, which must work before the upload endpoint
    exists and must be able to build states the API would refuse to create.
    """
    stored = attachments_store.new_stored_name(ext)
    attachments_store.write_file(stored, raw)
    has_thumb = attachments_store.make_thumb(raw, content_type, stored)
    db = SessionLocal()
    try:
        row = models.EventAttachment(
            source="local", event_uid=event_uid, event_id=event_id,
            filename=filename, stored_name=stored, content_type=content_type,
            size_bytes=len(raw), has_thumb=has_thumb,
            token=attachments_store.new_token(),
        )
        db.add(row)
        db.commit()
        return stored
    finally:
        db.close()


def _row_count() -> int:
    db = SessionLocal()
    try:
        return db.query(models.EventAttachment).count()
    finally:
        db.close()


def _exists(stored_name) -> bool:
    return attachments_store.path_for(stored_name).exists()


# ── Content sniffing ──────────────────────────────────────

@pytest.mark.parametrize("raw,name,expected", [
    (PDF_BYTES, "x.pdf", "application/pdf"),
    (png_bytes(), "x.png", "image/png"),
    (TXT_BYTES, "notiz.txt", "text/plain"),
    (b"a,b\n1,2", "liste.csv", "text/csv"),
    (b"# Titel", "doku.md", "text/markdown"),
])
def test_sniff_accepts_allowed_types(raw, name, expected):
    content_type, _ = attachments_store.sniff(raw, name)
    assert content_type == expected


@pytest.mark.parametrize("raw,name", [
    (b'<svg xmlns="http://www.w3.org/2000/svg"><script/></svg>', "x.svg"),
    (b"<!doctype html><html><script>alert(1)</script></html>", "x.html"),
    (b"print('hi')", "x.py"),
    (bytes(range(256)), "x.bin"),
    (b"plain text but no known extension", "readme"),
])
def test_sniff_rejects_everything_else(raw, name):
    """SVG and HTML matter most here: both execute script in the app's origin,
    where the session token lives in localStorage."""
    with pytest.raises(HTTPException) as e:
        attachments_store.sniff(raw, name)
    assert e.value.status_code == 400


def test_sniff_ignores_the_uploaded_name_for_binary_types():
    """A PNG named .pdf is a PNG. The extension never overrides the bytes."""
    content_type, ext = attachments_store.sniff(png_bytes(), "getarnt.pdf")
    assert (content_type, ext) == ("image/png", ".png")


def test_stored_name_never_contains_path_separators():
    """The uploaded name is attacker-controlled, and on the CalDAV path so is
    the event UID — neither may reach the filesystem."""
    _, ext = attachments_store.sniff(PDF_BYTES, "../../../etc/passwd.pdf")
    stored = attachments_store.new_stored_name(ext)
    assert "/" not in stored and "\\" not in stored and ".." not in stored
    path = attachments_store.path_for(stored)
    assert attachments_store.ATTACH_DIR in path.parents


def test_safe_filename_strips_directories_and_quotes():
    assert attachments_store.safe_filename("../../etc/passwd", ".txt") == "passwd"
    assert '"' not in attachments_store.safe_filename('a"b.pdf', ".pdf")
    assert attachments_store.safe_filename("", ".pdf") == "anhang.pdf"


def test_thumbnail_only_for_images():
    stored = attachments_store.new_stored_name(".png")
    attachments_store.write_file(stored, png_bytes((600, 400)))
    assert attachments_store.make_thumb(png_bytes((600, 400)), "image/png", stored) is True
    assert attachments_store.thumb_path_for(stored).exists()

    stored_pdf = attachments_store.new_stored_name(".pdf")
    assert attachments_store.make_thumb(PDF_BYTES, "application/pdf", stored_pdf) is False


# ── Cleanup on every delete path ──────────────────────────

def test_deleting_an_event_removes_rows_and_files(client):
    token = register_admin(client)
    cal_id = _make_calendar(client, token)
    ev = _make_event(client, token, cal_id)
    db = SessionLocal()
    ev_id = db.query(models.LocalEvent).filter(models.LocalEvent.uid == ev["id"]).first().id
    db.close()

    stored = _attach_row(ev["id"], ev_id)
    assert _row_count() == 1 and _exists(stored)

    r = client.delete(f"/api/local/events/{ev['id']}", headers=auth(token))
    assert r.status_code == 200, r.text
    assert _row_count() == 0
    assert not _exists(stored)


def test_deleting_a_calendar_removes_rows_and_files(client):
    token = register_admin(client)
    cal_id = _make_calendar(client, token)
    ev = _make_event(client, token, cal_id)
    db = SessionLocal()
    ev_id = db.query(models.LocalEvent).filter(models.LocalEvent.uid == ev["id"]).first().id
    db.close()
    stored = _attach_row(ev["id"], ev_id)

    r = client.delete(f"/api/local/calendars/{cal_id}", headers=auth(token))
    assert r.status_code == 200, r.text
    assert _row_count() == 0
    assert not _exists(stored)


def test_deleting_a_user_removes_rows_and_files(client):
    """The longest cascade: user -> calendars -> events -> attachments."""
    admin = register_admin(client)
    bob_id, bob = create_user(client, admin, "bob")
    cal_id = _make_calendar(client, bob, "Bobs Kalender")
    ev = _make_event(client, bob, cal_id)
    db = SessionLocal()
    ev_id = db.query(models.LocalEvent).filter(models.LocalEvent.uid == ev["id"]).first().id
    db.close()
    stored = _attach_row(ev["id"], ev_id)

    r = client.delete(f"/api/users/{bob_id}", headers=auth(admin))
    assert r.status_code == 200, r.text
    assert _row_count() == 0
    assert not _exists(stored)


# ── The background sweep ──────────────────────────────────

def test_sweep_removes_rows_whose_event_is_gone(client):
    token = register_admin(client)
    cal_id = _make_calendar(client, token)
    ev = _make_event(client, token, cal_id)
    db = SessionLocal()
    ev_id = db.query(models.LocalEvent).filter(models.LocalEvent.uid == ev["id"]).first().id
    db.close()
    stored = _attach_row(ev["id"], ev_id)

    # Delete the event behind the API's back, as a cascade that skipped the
    # purge helper would.
    db = SessionLocal()
    db.query(models.LocalEvent).filter(models.LocalEvent.id == ev_id).delete()
    db.commit()
    db.close()

    db = SessionLocal()
    rows, files = attachments_store.sweep(db)
    db.close()
    assert rows == 1
    assert not _exists(stored)


def test_sweep_removes_files_with_no_row_but_respects_the_grace_period():
    stored = attachments_store.new_stored_name(".pdf")
    path = attachments_store.write_file(stored, PDF_BYTES)

    # Fresh file, no row: must survive — an upload in flight writes the bytes
    # before it commits the row.
    db = SessionLocal()
    rows, files = attachments_store.sweep(db)
    db.close()
    assert files == 0 and path.exists()

    # Same file, aged past the grace window: now it is an orphan.
    old = time.time() - attachments_store.SWEEP_GRACE_SECONDS - 60
    os.utime(path, (old, old))
    db = SessionLocal()
    rows, files = attachments_store.sweep(db)
    db.close()
    assert files == 1 and not path.exists()


def test_sweep_leaves_live_attachments_alone(client):
    token = register_admin(client)
    cal_id = _make_calendar(client, token)
    ev = _make_event(client, token, cal_id)
    db = SessionLocal()
    ev_id = db.query(models.LocalEvent).filter(models.LocalEvent.uid == ev["id"]).first().id
    db.close()
    stored = _attach_row(ev["id"], ev_id)

    old = time.time() - attachments_store.SWEEP_GRACE_SECONDS - 60
    for p in (attachments_store.path_for(stored),):
        os.utime(p, (old, old))

    db = SessionLocal()
    rows, files = attachments_store.sweep(db)
    db.close()
    assert (rows, files) == (0, 0)
    assert _row_count() == 1 and _exists(stored)


# ── Upload / download through the API ─────────────────────

def _upload(client, token, uid, raw=PDF_BYTES, name="Rechnung.pdf", mime="application/pdf"):
    return client.post(
        f"/api/local/events/{uid}/attachments",
        headers=auth(token),
        files={"file": (name, raw, mime)},
    )


def test_upload_list_and_download_roundtrip(client):
    token = register_admin(client)
    cal_id = _make_calendar(client, token)
    ev = _make_event(client, token, cal_id)

    r = _upload(client, token, ev["id"])
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["filename"] == "Rechnung.pdf"
    assert body["content_type"] == "application/pdf"
    assert body["has_thumb"] is False
    assert body["uploaded_by"]["display_name"] == "admin"

    listing = client.get(f"/api/local/events/{ev['id']}/attachments", headers=auth(token))
    assert listing.status_code == 200
    assert [a["id"] for a in listing.json()] == [body["id"]]

    dl = client.get(f"/api/local/attachments/{body['id']}", headers=auth(token))
    assert dl.status_code == 200
    assert dl.content == PDF_BYTES
    assert dl.headers["content-disposition"].startswith("attachment;")
    assert dl.headers["x-content-type-options"] == "nosniff"


def test_image_upload_gets_a_thumbnail(client):
    token = register_admin(client)
    ev = _make_event(client, token, _make_calendar(client, token))
    r = _upload(client, token, ev["id"], png_bytes((640, 480)), "foto.png", "image/png")
    assert r.status_code == 201, r.text
    assert r.json()["has_thumb"] is True

    thumb = client.get(f"/api/local/attachments/{r.json()['id']}/thumb", headers=auth(token))
    assert thumb.status_code == 200
    assert thumb.headers["content-type"] == "image/jpeg"


def test_declared_mime_is_ignored_in_favour_of_the_bytes(client):
    """A PNG announced as application/pdf is stored as a PNG."""
    token = register_admin(client)
    ev = _make_event(client, token, _make_calendar(client, token))
    r = _upload(client, token, ev["id"], png_bytes(), "getarnt.pdf", "application/pdf")
    assert r.status_code == 201, r.text
    assert r.json()["content_type"] == "image/png"


def test_rejects_disallowed_type_and_writes_nothing(client):
    token = register_admin(client)
    ev = _make_event(client, token, _make_calendar(client, token))
    r = _upload(client, token, ev["id"], b"<svg/>", "x.svg", "image/svg+xml")
    assert r.status_code == 400
    assert _row_count() == 0
    assert not any(p.is_file() for p in attachments_store.ATTACH_DIR.rglob("*"))


def test_rejects_oversized_file(client):
    token = register_admin(client)
    ev = _make_event(client, token, _make_calendar(client, token))
    big = b"%PDF-1.4\n" + b"x" * attachments_store.MAX_ATTACHMENT_BYTES
    r = _upload(client, token, ev["id"], big, "gross.pdf")
    assert r.status_code == 413
    assert _row_count() == 0


def test_enforces_the_per_event_limit(client):
    token = register_admin(client)
    ev = _make_event(client, token, _make_calendar(client, token))
    for i in range(attachments_store.MAX_ATTACHMENTS_PER_EVENT):
        assert _upload(client, token, ev["id"], name=f"a{i}.pdf").status_code == 201
    r = _upload(client, token, ev["id"], name="zuviel.pdf")
    assert r.status_code == 409
    assert _row_count() == attachments_store.MAX_ATTACHMENTS_PER_EVENT


def test_deleting_an_attachment_removes_its_file(client):
    token = register_admin(client)
    ev = _make_event(client, token, _make_calendar(client, token))
    att_id = _upload(client, token, ev["id"]).json()["id"]
    db = SessionLocal()
    stored = db.query(models.EventAttachment).filter(
        models.EventAttachment.id == att_id).first().stored_name
    db.close()

    r = client.delete(f"/api/local/attachments/{att_id}", headers=auth(token))
    assert r.status_code == 200, r.text
    assert _row_count() == 0
    assert not _exists(stored)


# ── Permission matrix ─────────────────────────────────────

def _share(client, owner_token, cal_id, user_id, permission):
    r = client.post(f"/api/local/calendars/{cal_id}/shares", headers=auth(owner_token),
                    json={"user_id": user_id, "permission": permission})
    assert r.status_code == 200, r.text


def test_read_share_may_view_but_not_upload_or_delete(client):
    admin = register_admin(client)
    bob_id, bob = create_user(client, admin, "bob")
    cal_id = _make_calendar(client, admin)
    ev = _make_event(client, admin, cal_id)
    att_id = _upload(client, admin, ev["id"]).json()["id"]
    _share(client, admin, cal_id, bob_id, "read")

    assert client.get(f"/api/local/events/{ev['id']}/attachments",
                      headers=auth(bob)).status_code == 200
    assert client.get(f"/api/local/attachments/{att_id}", headers=auth(bob)).status_code == 200
    assert _upload(client, bob, ev["id"], name="nope.pdf").status_code == 403
    assert client.delete(f"/api/local/attachments/{att_id}",
                         headers=auth(bob)).status_code == 403


def test_read_write_share_may_upload_and_delete(client):
    admin = register_admin(client)
    bob_id, bob = create_user(client, admin, "bob")
    cal_id = _make_calendar(client, admin)
    ev = _make_event(client, admin, cal_id)
    att_id = _upload(client, admin, ev["id"]).json()["id"]
    _share(client, admin, cal_id, bob_id, "read_write")

    assert _upload(client, bob, ev["id"], name="bob.pdf").status_code == 201
    # The stated rule: whoever may edit the event may remove anyone's attachment.
    assert client.delete(f"/api/local/attachments/{att_id}",
                         headers=auth(bob)).status_code == 200


def test_unrelated_user_gets_404_not_403(client):
    """404 everywhere, so a stranger cannot even learn the event exists."""
    admin = register_admin(client)
    _, dave = create_user(client, admin, "dave")
    ev = _make_event(client, admin, _make_calendar(client, admin))
    att_id = _upload(client, admin, ev["id"]).json()["id"]

    assert client.get(f"/api/local/events/{ev['id']}/attachments",
                      headers=auth(dave)).status_code == 404
    assert client.get(f"/api/local/attachments/{att_id}", headers=auth(dave)).status_code == 404
    assert client.delete(f"/api/local/attachments/{att_id}",
                         headers=auth(dave)).status_code == 404


def test_private_event_hides_its_attachments_from_a_share_recipient(client):
    """The leak this feature could most easily introduce: the merge read masks
    a foreign private event, so its attachments must be unreachable too."""
    admin = register_admin(client)
    bob_id, bob = create_user(client, admin, "bob")
    cal_id = _make_calendar(client, admin)
    r = client.post("/api/local/events", headers=auth(admin), json={
        "calendar_id": cal_id, "title": "Vertraulich", "private": True,
        "start": "2026-06-10T10:00:00+00:00", "end": "2026-06-10T11:00:00+00:00",
    })
    ev = r.json()
    att_id = _upload(client, admin, ev["id"]).json()["id"]
    _share(client, admin, cal_id, bob_id, "read_write")

    assert client.get(f"/api/local/events/{ev['id']}/attachments",
                      headers=auth(bob)).status_code == 404
    assert client.get(f"/api/local/attachments/{att_id}", headers=auth(bob)).status_code == 404
    # The owner still reaches their own private event's attachments.
    assert client.get(f"/api/local/attachments/{att_id}", headers=auth(admin)).status_code == 200


# ── Capability URL ────────────────────────────────────────

def test_capability_url_serves_without_authentication(client):
    token = register_admin(client)
    ev = _make_event(client, token, _make_calendar(client, token))
    att_id = _upload(client, token, ev["id"]).json()["id"]
    db = SessionLocal()
    cap = db.query(models.EventAttachment).filter(
        models.EventAttachment.id == att_id).first().token
    db.close()

    r = client.get(f"/api/attach/{cap}/Rechnung.pdf")  # no Authorization header
    assert r.status_code == 200
    assert r.content == PDF_BYTES
    assert r.headers["content-disposition"].startswith("attachment;")
    assert r.headers["x-content-type-options"] == "nosniff"

    assert client.get("/api/attach/voellig-erfunden").status_code == 404
    client.delete(f"/api/local/attachments/{att_id}", headers=auth(token))
    assert client.get(f"/api/attach/{cap}").status_code == 404


# ── attachment_count in the merged event read ─────────────

def test_attachment_count_appears_on_the_merged_read(client):
    token = register_admin(client)
    cal_id = _make_calendar(client, token)
    ev = _make_event(client, token, cal_id)

    def count_for(uid):
        events = client.get("/api/caldav/events", headers=auth(token),
                            params=RANGE).json()["events"]
        return next(e["attachment_count"] for e in events if e["id"] == uid)

    assert count_for(ev["id"]) == 0
    _upload(client, token, ev["id"], name="a.pdf")
    _upload(client, token, ev["id"], name="b.pdf")
    assert count_for(ev["id"]) == 2


def test_recurring_event_carries_the_count_on_every_occurrence(client):
    token = register_admin(client)
    cal_id = _make_calendar(client, token)
    r = client.post("/api/local/events", headers=auth(token), json={
        "calendar_id": cal_id, "title": "Taeglich", "rrule": "FREQ=DAILY;COUNT=5",
        "start": "2026-06-10T10:00:00+00:00", "end": "2026-06-10T11:00:00+00:00",
    })
    ev = r.json()
    _upload(client, token, ev["id"], name="a.pdf")

    events = client.get("/api/caldav/events", headers=auth(token),
                        params=RANGE).json()["events"]
    occurrences = [e for e in events if e["id"] == ev["id"]]
    assert len(occurrences) == 5
    assert all(e["attachment_count"] == 1 for e in occurrences)


def test_busy_masked_event_reports_no_attachments(client):
    """A count is metadata too: "this busy block has 3 files" would leak."""
    admin = register_admin(client)
    bob_id, bob = create_user(client, admin, "bob")
    cal_id = _make_calendar(client, admin)
    r = client.post("/api/local/events", headers=auth(admin), json={
        "calendar_id": cal_id, "title": "Vertraulich", "private": True,
        "start": "2026-06-10T10:00:00+00:00", "end": "2026-06-10T11:00:00+00:00",
    })
    ev = r.json()
    _upload(client, admin, ev["id"], name="geheim.pdf")
    _share(client, admin, cal_id, bob_id, "read")

    events = client.get("/api/caldav/events", headers=auth(bob),
                        params=RANGE).json()["events"]
    masked = next(e for e in events if e["id"] == ev["id"])
    assert masked["title"] == "Beschäftigt"
    assert masked["attachment_count"] == 0


# ── ATTACH in the generated ICS ───────────────────────────

def _publish(client, token, cal_id):
    """Publish the calendar over CalDAV and return its secret token URL path."""
    r = client.put(f"/api/local/calendars/{cal_id}", headers=auth(token),
                   json={"caldav_published": True})
    assert r.status_code == 200, r.text
    cals = client.get("/api/local/calendars", headers=auth(token)).json()
    url = next(c["caldav_url"] for c in cals if c["id"] == cal_id)
    return "/dav/" + url.rstrip("/").rsplit("/", 1)[-1] + "/"


def _attach_props(ics_text):
    """Re-parse instead of grepping: icalendar folds lines at 75 octets, so a
    naive substring check would miss a long URL."""
    from icalendar import Calendar

    cal = Calendar.from_ical(ics_text)
    out = []
    for comp in cal.walk("VEVENT"):
        prop = comp.get("attach")
        if prop is None:
            continue
        for p in (prop if isinstance(prop, list) else [prop]):
            out.append((str(p), dict(p.params)))
    return out


def test_ics_carries_an_attach_line_per_attachment(client):
    token = register_admin(client)
    cal_id = _make_calendar(client, token)
    ev = _make_event(client, token, cal_id)
    _upload(client, token, ev["id"], name="Mietvertrag.pdf")
    _upload(client, token, ev["id"], png_bytes(), "foto.png", "image/png")
    dav_path = _publish(client, token, cal_id)

    props = _attach_props(client.get(dav_path).text)
    assert len(props) == 2
    by_name = {params["FILENAME"]: (uri, params) for uri, params in props}
    assert set(by_name) == {"Mietvertrag.pdf", "foto.png"}

    uri, params = by_name["Mietvertrag.pdf"]
    assert params["FMTTYPE"] == "application/pdf"
    assert int(params["SIZE"]) == len(PDF_BYTES)
    assert "/api/attach/" in uri and uri.startswith("http")


def test_attach_url_from_the_ics_actually_serves_the_file(client):
    """The whole point: an external client follows the URL with no credentials."""
    token = register_admin(client)
    cal_id = _make_calendar(client, token)
    ev = _make_event(client, token, cal_id)
    _upload(client, token, ev["id"])
    dav_path = _publish(client, token, cal_id)

    uri, _ = _attach_props(client.get(dav_path).text)[0]
    path = uri.split("testserver", 1)[1]
    r = client.get(path)  # no Authorization header
    assert r.status_code == 200
    assert r.content == PDF_BYTES


def test_attach_url_honours_public_base_url(client, monkeypatch):
    """Behind a reverse proxy the app only sees its internal origin."""
    monkeypatch.setenv("PUBLIC_BASE_URL", "https://cal.example.com")
    token = register_admin(client)
    cal_id = _make_calendar(client, token)
    ev = _make_event(client, token, cal_id)
    _upload(client, token, ev["id"])
    dav_path = _publish(client, token, cal_id)

    uri, _ = _attach_props(client.get(dav_path).text)[0]
    assert uri.startswith("https://cal.example.com/api/attach/")


def test_no_attach_when_public_links_are_switched_off(client, monkeypatch):
    monkeypatch.setattr(attachments_store, "PUBLIC_LINKS_ENABLED", False)
    token = register_admin(client)
    cal_id = _make_calendar(client, token)
    ev = _make_event(client, token, cal_id)
    _upload(client, token, ev["id"])
    dav_path = _publish(client, token, cal_id)

    assert _attach_props(client.get(dav_path).text) == []


def test_events_without_attachments_get_no_attach(client):
    token = register_admin(client)
    cal_id = _make_calendar(client, token)
    _make_event(client, token, cal_id)
    dav_path = _publish(client, token, cal_id)
    assert _attach_props(client.get(dav_path).text) == []


def test_upload_changes_the_event_etag(client):
    """The ICS body changes, so CalDAV clients must be told to re-fetch."""
    token = register_admin(client)
    cal_id = _make_calendar(client, token)
    ev = _make_event(client, token, cal_id)
    db = SessionLocal()
    before = db.query(models.LocalEvent).filter(
        models.LocalEvent.uid == ev["id"]).first().etag
    db.close()

    _upload(client, token, ev["id"])

    db = SessionLocal()
    after = db.query(models.LocalEvent).filter(
        models.LocalEvent.uid == ev["id"]).first().etag
    db.close()
    assert after != before


def test_caldav_put_leaves_attachments_alone(client):
    """An external client rewriting the event must not drop its attachments."""
    token = register_admin(client)
    cal_id = _make_calendar(client, token)
    ev = _make_event(client, token, cal_id)
    _upload(client, token, ev["id"])
    dav_path = _publish(client, token, cal_id)

    ics = client.get(dav_path).text
    r = client.put(f"{dav_path}{ev['id']}.ics", content=ics.encode("utf-8"),
                   headers={"Content-Type": "text/calendar"})
    assert r.status_code in (201, 204), r.text
    assert _row_count() == 1
    assert len(_attach_props(client.get(dav_path).text)) == 1
