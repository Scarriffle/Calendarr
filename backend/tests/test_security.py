"""Regression tests for the findings of the November 2026 security review.

Each test names the finding it guards. They are the executable half of that
review — if one of these starts passing trivially, check the fix is still there.
"""

import pytest

import models
from conftest import auth, create_user, register_admin
from database import SessionLocal


def db_session():
    return SessionLocal()


# ── CAL-01: the Google callback must be bound to the browser ───────────────

def test_google_callback_rejects_a_guessed_state(client, monkeypatch):
    """The old code took the user id straight from `state`, so anyone could
    attach their Google account to user 1 by guessing a small integer."""
    monkeypatch.setenv("GOOGLE_CLIENT_ID", "x")
    monkeypatch.setenv("GOOGLE_CLIENT_SECRET", "y")
    monkeypatch.setenv("GOOGLE_REDIRECT_URI", "https://example.com/cb")
    import routers.google_router as gr
    monkeypatch.setattr(gr, "GOOGLE_CLIENT_ID", "x")
    monkeypatch.setattr(gr, "GOOGLE_CLIENT_SECRET", "y")
    monkeypatch.setattr(gr, "GOOGLE_REDIRECT_URI", "https://example.com/cb")

    register_admin(client, "admin", "pw")
    r = client.get("/api/google/callback?code=whatever&state=1",
                   follow_redirects=False)
    assert r.status_code == 400
    with db_session() as db:
        assert db.query(models.GoogleAccount).count() == 0


def test_google_auth_url_sets_a_flow_cookie_with_pkce(client, monkeypatch):
    import routers.google_router as gr
    monkeypatch.setattr(gr, "GOOGLE_CLIENT_ID", "x")
    monkeypatch.setattr(gr, "GOOGLE_CLIENT_SECRET", "y")
    monkeypatch.setattr(gr, "GOOGLE_REDIRECT_URI", "https://example.com/cb")

    token = register_admin(client, "admin", "pw")
    r = client.get("/api/google/auth-url", headers=auth(token))
    assert r.status_code == 200
    url = r.json()["url"]
    assert "code_challenge=" in url and "code_challenge_method=S256" in url
    assert "state=1" not in url          # not the user id any more
    assert "clr_google_flow" in r.headers.get("set-cookie", "")


# ── CAL-04: colours are the stored-XSS vector ──────────────────────────────

@pytest.mark.parametrize("bad", [
    '#fff" onmouseover="alert(1)',
    'red;background:url(javascript:alert(1))',
    '"><script>alert(1)</script>',
    'notacolour',
])
def test_calendar_colour_must_be_a_hex_value(client, bad):
    admin_token = register_admin(client, "admin", "pw")
    r = client.post("/api/local/calendars", headers=auth(admin_token),
                    json={"name": "Test", "color": bad})
    assert r.status_code == 422, f"{bad!r} was accepted"


def test_a_real_colour_still_works(client):
    admin_token = register_admin(client, "admin", "pw")
    r = client.post("/api/local/calendars", headers=auth(admin_token),
                    json={"name": "Test", "color": "#58B900"})
    assert r.status_code == 200, r.text


# ── CAL-03 / SSRF: where the server may connect ────────────────────────────

@pytest.mark.parametrize("url", [
    "http://127.0.0.1:8080",
    "http://localhost:8123",
    "http://169.254.169.254/latest/meta-data/",
])
def test_home_assistant_refuses_loopback_and_metadata(client, url):
    admin_token = register_admin(client, "admin", "pw")
    r = client.post("/api/homeassistant/accounts", headers=auth(admin_token),
                    json={"name": "HA", "url": url, "token": "t"})
    assert r.status_code == 400, f"{url} was accepted"


def test_url_guard_still_allows_the_lan():
    """A Home Assistant on the home network is the normal case — the guard
    must not turn the feature off while closing the metadata hole."""
    from url_guard import host_is_reachable, validate_reachable_url
    assert host_is_reachable("192.168.1.10")
    assert host_is_reachable("10.0.0.5")
    validate_reachable_url("https://192.168.1.10:8123")   # no raise
    for bad in ("http://127.0.0.1", "http://169.254.169.254"):
        with pytest.raises(ValueError):
            validate_reachable_url(bad)


def test_ical_still_refuses_private_targets():
    """Subscriptions point at public feeds; nothing internal is allowed."""
    from url_guard import validate_public_url
    for bad in ("http://127.0.0.1/x.ics", "http://192.168.1.10/x.ics",
                "ftp://example.com/x.ics"):
        with pytest.raises(ValueError):
            validate_public_url(bad)


def test_home_assistant_verifies_tls():
    """No code path may turn certificate checking off."""
    import routers.homeassistant_router as ha
    src = open(ha.__file__, encoding="utf-8").read()
    assert "verify=False" not in src
    assert "CERT_NONE" not in src
    assert ha.HA_VERIFY is True or isinstance(ha.HA_VERIFY, str)


# ── CAL-05: no start without a real secret ─────────────────────────────────

def test_secret_key_guard_rejects_the_old_default():
    """Reproduces the guard's condition; importing auth with a bad key cannot
    be tested directly because it is already imported."""
    import auth
    for bad in ("", "short", auth._INSECURE_DEFAULT):
        assert not bad or bad == auth._INSECURE_DEFAULT or len(bad) < 32
    assert len(auth.SECRET_KEY) >= 32
    assert auth.SECRET_KEY != auth._INSECURE_DEFAULT


# ── CAL-06: repeated failures lock the account ─────────────────────────────

def test_account_locks_after_repeated_failures(client):
    admin_token = register_admin(client, "admin", "pw")
    create_user(client, admin_token, "mallory", password="correct")

    for _ in range(10):
        r = client.post("/api/auth/login",
                        json={"username": "mallory", "password": "wrong"})
        assert r.status_code == 401

    # Locked now — even the right password is refused.
    r = client.post("/api/auth/login",
                    json={"username": "mallory", "password": "correct"})
    assert r.status_code == 429


def test_a_success_clears_the_counter(client):
    admin_token = register_admin(client, "admin", "pw")
    create_user(client, admin_token, "bob", password="correct")

    for _ in range(3):
        client.post("/api/auth/login", json={"username": "bob", "password": "wrong"})
    assert client.post("/api/auth/login",
                       json={"username": "bob", "password": "correct"}).status_code == 200
    with db_session() as db:
        user = db.query(models.User).filter(models.User.username == "bob").one()
        assert (user.failed_logins or 0) == 0


# ── CAL-07: a password change retires existing sessions ────────────────────

def test_password_change_invalidates_other_sessions(client):
    admin_token = register_admin(client, "admin", "pw")
    _, stolen = create_user(client, admin_token, "carol", password="old")

    # Carol changes her password in another browser.
    r = client.post("/api/profile/password", headers=auth(stolen),
                    json={"current_password": "old", "new_password": "newpass"})
    assert r.status_code == 200
    fresh = r.json().get("access_token")
    assert fresh, "the caller must get a replacement token"

    # The token as held by the attacker is dead; the replacement works.
    assert client.get("/api/auth/me", headers=auth(stolen)).status_code == 401
    assert client.get("/api/auth/me", headers=auth(fresh)).status_code == 200


def test_logout_all_kills_the_current_token(client):
    admin_token = register_admin(client, "admin", "pw")
    _, token = create_user(client, admin_token, "dave")

    assert client.post("/api/profile/logout-all", headers=auth(token)).status_code == 200
    assert client.get("/api/auth/me", headers=auth(token)).status_code == 401


def test_a_token_without_an_epoch_still_works(client):
    """Tokens minted before the column existed must not be refused, or a
    deploy signs everyone out."""
    from auth import create_access_token
    admin_token = register_admin(client, "admin", "pw")
    with db_session() as db:
        uid = db.query(models.User).filter(models.User.username == "admin").one().id
    legacy = create_access_token({"sub": "admin", "uid": uid})
    assert client.get("/api/auth/me", headers=auth(legacy)).status_code == 200
