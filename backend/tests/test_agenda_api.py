"""Tests for the read-only agenda API and its keys.

What matters here is the gate, not the aggregation: that nothing answers
without a valid key, that a key scoped to one calendar cannot read another,
and that the response carries only the promised fields. The aggregation itself
is caldav_router's and is covered where it lives.
"""

from conftest import register_admin, create_user, auth


def _cal(client, token, name="Cal"):
    r = client.post("/api/local/calendars", headers=auth(token), json={"name": name})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def _event(client, token, cal_id, title, start, end, location="", description=""):
    r = client.post("/api/local/events", headers=auth(token), json={
        "calendar_id": cal_id, "title": title, "start": start, "end": end,
        "location": location, "description": description,
    })
    assert r.status_code == 200, r.text
    return r.json()


def _key(client, token, label="Briefing", calendars=None):
    r = client.post("/api/profile/api-keys", headers=auth(token),
                    json={"label": label, "calendars": calendars})
    assert r.status_code == 200, r.text
    return r.json()


def _agenda(client, key, **params):
    return client.get("/api/agenda", headers={"Authorization": f"Bearer {key}"},
                      params=params)


# ── The gate ──────────────────────────────────────────────

def test_no_credentials_is_rejected(client):
    assert client.get("/api/agenda").status_code == 401


def test_unknown_key_is_rejected(client):
    assert _agenda(client, "calrr_nope").status_code == 401


def test_session_token_is_not_accepted(client):
    """A session JWT must not authenticate here — otherwise a browser session
    would reach the endpoint and skip the key's calendar scope entirely."""
    admin = register_admin(client)
    assert _agenda(client, admin).status_code == 401


def test_x_api_key_header_also_works(client):
    admin = register_admin(client)
    key = _key(client, admin)["key"]
    r = client.get("/api/agenda", headers={"X-API-Key": key},
                   params={"date": "2026-06-10", "tz": "UTC"})
    assert r.status_code == 200, r.text


def test_key_is_returned_once_and_not_stored_in_clear(client):
    admin = register_admin(client)
    created = _key(client, admin)
    assert created["key"].startswith("calrr_")
    rows = client.get("/api/profile/api-keys", headers=auth(admin)).json()
    assert len(rows) == 1
    assert "key" not in rows[0]
    # The prefix is a hint, never enough to reconstruct the secret.
    assert created["key"].startswith(rows[0]["prefix"])
    assert len(rows[0]["prefix"]) < len(created["key"])


def test_revoked_key_stops_working(client):
    admin = register_admin(client)
    created = _key(client, admin)
    r = client.delete(f"/api/profile/api-keys/{created['id']}", headers=auth(admin))
    assert r.status_code == 200, r.text
    assert _agenda(client, created["key"], date="2026-06-10", tz="UTC").status_code == 401


def test_key_of_one_user_cannot_be_revoked_by_another(client):
    admin = register_admin(client)
    _, bob = create_user(client, admin, "bob")
    created = _key(client, admin)
    r = client.delete(f"/api/profile/api-keys/{created['id']}", headers=auth(bob))
    assert r.status_code == 404


# ── Scope ─────────────────────────────────────────────────

def test_unscoped_key_sees_every_calendar(client):
    admin = register_admin(client)
    a, b = _cal(client, admin, "A"), _cal(client, admin, "B")
    _event(client, admin, a, "In A", "2026-06-10T09:00:00+00:00", "2026-06-10T10:00:00+00:00")
    _event(client, admin, b, "In B", "2026-06-10T11:00:00+00:00", "2026-06-10T12:00:00+00:00")

    body = _agenda(client, _key(client, admin)["key"], date="2026-06-10", tz="UTC").json()
    assert {e["title"] for e in body["events"]} == {"In A", "In B"}


def test_scoped_key_sees_only_its_calendar(client):
    admin = register_admin(client)
    a, b = _cal(client, admin, "A"), _cal(client, admin, "B")
    _event(client, admin, a, "In A", "2026-06-10T09:00:00+00:00", "2026-06-10T10:00:00+00:00")
    _event(client, admin, b, "In B", "2026-06-10T11:00:00+00:00", "2026-06-10T12:00:00+00:00")

    key = _key(client, admin, calendars=[f"local-{a}"])["key"]
    body = _agenda(client, key, date="2026-06-10", tz="UTC").json()
    assert [e["title"] for e in body["events"]] == ["In A"]


def test_key_cannot_reach_another_users_calendar(client):
    """The scope is a filter over what the owner may read, never a way in:
    naming someone else's calendar key must not widen access."""
    admin = register_admin(client)
    _, bob = create_user(client, admin, "bob")
    bobs_cal = _cal(client, bob, "Bobs")
    _event(client, bob, bobs_cal, "Bobs Termin",
           "2026-06-10T09:00:00+00:00", "2026-06-10T10:00:00+00:00")

    key = _key(client, admin, calendars=[f"local-{bobs_cal}"])["key"]
    body = _agenda(client, key, date="2026-06-10", tz="UTC").json()
    assert body["events"] == []


# ── The promised shape ────────────────────────────────────

def test_response_carries_only_the_documented_fields(client):
    admin = register_admin(client)
    cal = _cal(client, admin)
    _event(client, admin, cal, "Zahnarzt",
           "2026-06-10T09:00:00+00:00", "2026-06-10T10:00:00+00:00",
           location="Praxis", description="Geheime Notiz")

    body = _agenda(client, _key(client, admin)["key"], date="2026-06-10", tz="UTC").json()
    ev = body["events"][0]
    assert set(ev) == {"title", "start", "end", "all_day", "location", "calendar", "color", "source"}
    assert ev["title"] == "Zahnarzt"
    assert ev["location"] == "Praxis"
    # A long-lived key must not hand out event bodies.
    assert "Geheime Notiz" not in str(body)


def test_own_private_events_are_included_in_full(client):
    """The briefing is for the calendar's own owner, so their private events
    belong in it with their real title. Only OTHER people's private events are
    redacted, and that rule lives in apply_event_privacy, not here.

    Pinned by a test because a key is the one caller that is not a browser
    session: a future tightening of the API surface could plausibly start
    masking private events and silently empty the morning briefing.
    """
    admin = register_admin(client)
    cal = _cal(client, admin)
    r = client.post("/api/local/events", headers=auth(admin), json={
        "calendar_id": cal, "title": "Therapie",
        "start": "2026-06-10T09:00:00+00:00", "end": "2026-06-10T10:00:00+00:00",
        "location": "Praxis", "private": True,
    })
    assert r.status_code == 200, r.text

    body = _agenda(client, _key(client, admin)["key"], date="2026-06-10", tz="UTC").json()
    assert [e["title"] for e in body["events"]] == ["Therapie"]
    assert body["events"][0]["location"] == "Praxis"


def test_another_users_private_event_stays_redacted(client):
    """A key must not become a way around someone else's privacy setting. The
    default visibility masks a foreign private event as busy; what must never
    appear is its title."""
    admin = register_admin(client)
    b_id, bob = create_user(client, admin, "bob")
    bobs_cal = _cal(client, bob, "Bobs")
    r = client.post("/api/local/events", headers=auth(bob), json={
        "calendar_id": bobs_cal, "title": "Bobs Geheimnis",
        "start": "2026-06-10T09:00:00+00:00", "end": "2026-06-10T10:00:00+00:00",
        "private": True,
    })
    assert r.status_code == 200, r.text

    # Bob shares the calendar, so the event reaches admin's read at all. The
    # share must really succeed: without it admin sees nothing anyway and the
    # assertion below would pass for the wrong reason.
    admin_id = client.get("/api/profile/", headers=auth(admin)).json()["id"]
    r2 = client.post(f"/api/local/calendars/{bobs_cal}/shares", headers=auth(bob),
                     json={"user_id": admin_id, "permission": "read"})
    assert r2.status_code == 200, r2.text

    key = _key(client, admin)["key"]
    body = _agenda(client, key, date="2026-06-10", tz="UTC").json()
    assert "Bobs Geheimnis" not in str(body)
    # Proof the share works and the event is reaching the read at all: the same
    # calendar's non-private event does come through.
    r3 = client.post("/api/local/events", headers=auth(bob), json={
        "calendar_id": bobs_cal, "title": "Bobs offener Termin",
        "start": "2026-06-10T14:00:00+00:00", "end": "2026-06-10T15:00:00+00:00",
    })
    assert r3.status_code == 200, r3.text
    body2 = _agenda(client, key, date="2026-06-10", tz="UTC").json()
    assert "Bobs offener Termin" in str(body2)


# ── Range ─────────────────────────────────────────────────

def test_date_and_timezone_pick_the_local_day(client):
    """23:30 Berlin on the 10th is 21:30 UTC — asking for the 10th in Berlin
    must return it, and asking for the 11th must not."""
    admin = register_admin(client)
    cal = _cal(client, admin)
    _event(client, admin, cal, "Spaet",
           "2026-06-10T21:30:00+00:00", "2026-06-10T22:30:00+00:00")

    key = _key(client, admin)["key"]
    tenth = _agenda(client, key, date="2026-06-10", tz="Europe/Berlin").json()
    assert [e["title"] for e in tenth["events"]] == ["Spaet"]
    eleventh = _agenda(client, key, date="2026-06-11", tz="Europe/Berlin").json()
    assert eleventh["events"] == []


def test_days_extends_the_range(client):
    admin = register_admin(client)
    cal = _cal(client, admin)
    _event(client, admin, cal, "Heute", "2026-06-10T09:00:00+00:00", "2026-06-10T10:00:00+00:00")
    _event(client, admin, cal, "Morgen", "2026-06-11T09:00:00+00:00", "2026-06-11T10:00:00+00:00")

    key = _key(client, admin)["key"]
    one = _agenda(client, key, date="2026-06-10", tz="UTC").json()
    assert [e["title"] for e in one["events"]] == ["Heute"]
    two = _agenda(client, key, date="2026-06-10", tz="UTC", days=2).json()
    assert {e["title"] for e in two["events"]} == {"Heute", "Morgen"}


def test_timestamps_are_normalised_per_source():
    """The sources disagree on format — CalDAV and Google send a bare date for
    an all-day event, a local event keeps the client's full timestamp. The API
    promises one shape per field, so this is pinned as a unit."""
    from routers.agenda_router import _iso

    assert _iso("2026-11-26", all_day=True) == "2026-11-26"
    assert _iso("2026-11-26T00:00:00+00:00", all_day=True) == "2026-11-26"
    assert _iso("2026-11-26T09:30:00+01:00", all_day=False) == "2026-11-26T09:30:00+01:00"
    assert _iso("2026-11-26T09:30:00Z", all_day=False) == "2026-11-26T09:30:00+00:00"
    # No offset from the source is read as UTC, not as local server time.
    assert _iso("2026-11-26T09:30:00", all_day=False) == "2026-11-26T09:30:00+00:00"
    # Unparseable is passed through: a wrong timestamp debugs better than none.
    assert _iso("kaputt", all_day=False) == "kaputt"
    assert _iso("", all_day=False) is None
    assert _iso(None, all_day=True) is None


def test_bad_input_is_rejected(client):
    admin = register_admin(client)
    key = _key(client, admin)["key"]
    assert _agenda(client, key, tz="Mars/Olympus").status_code == 400
    assert _agenda(client, key, date="10.06.2026").status_code == 400
    # start without end is a mistake, not a half-specified range.
    assert _agenda(client, key, start="2026-06-10T00:00:00Z").status_code == 400
    assert _agenda(client, key, start="2026-06-11T00:00:00Z",
                   end="2026-06-10T00:00:00Z").status_code == 400
    assert _agenda(client, key, date="2026-06-10", tz="UTC", days=99).status_code == 422
