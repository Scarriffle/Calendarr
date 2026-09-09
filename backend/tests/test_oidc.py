"""OpenID Connect SSO — protocol validation, account mapping and provisioning.

ID tokens here are signed with a real RSA key and go through the real
validation path; only the network (discovery, JWKS, token endpoint) is stubbed,
at the single seam ``oidc_client._http_get``.
"""

import time

import pytest
from authlib.jose import JsonWebKey, jwt as authlib_jwt

import models
import oidc_client
import oidc_config
from conftest import auth, create_user, register_admin
from database import SessionLocal

ISSUER = "https://authentik.example.com/application/o/calendarr/"
WEB_CLIENT = "calendarr-web"
MOBILE_CLIENT = "calendarr-mobile"

# One key pair for the whole module — generating RSA keys is slow.
_KEY = JsonWebKey.generate_key("RSA", 2048, is_private=True)
_KID = "test-key-1"


def _jwks() -> dict:
    pub = _KEY.as_dict(is_private=False)
    pub["kid"] = _KID
    return {"keys": [pub]}


def _discovery() -> dict:
    return {
        "issuer": ISSUER,
        "authorization_endpoint": ISSUER + "authorize/",
        "token_endpoint": ISSUER + "token/",
        "userinfo_endpoint": ISSUER + "userinfo/",
        "jwks_uri": ISSUER + "jwks/",
        "end_session_endpoint": ISSUER + "end-session/",
    }


def make_id_token(*, sub="ak-sub-1", aud=WEB_CLIENT, iss=ISSUER, nonce=None,
                  email="user@example.com", email_verified=True,
                  preferred_username="user", name="Test User",
                  exp_delta=300, alg="RS256", key=None, extra=None):
    now = int(time.time())
    payload = {
        "iss": iss, "sub": sub, "aud": aud,
        "iat": now, "exp": now + exp_delta,
    }
    if nonce is not None:
        payload["nonce"] = nonce
    if email is not None:
        payload["email"] = email
        payload["email_verified"] = email_verified
    if preferred_username is not None:
        payload["preferred_username"] = preferred_username
    if name is not None:
        payload["name"] = name
    if extra:
        payload.update(extra)
    header = {"alg": alg, "kid": _KID}
    return authlib_jwt.encode(header, payload, key or _KEY).decode("ascii")


@pytest.fixture
def stub_network(monkeypatch):
    """Serve discovery and JWKS locally; fail loudly on any other URL."""
    def fake_get(url, timeout=10):
        if url.endswith("/.well-known/openid-configuration"):
            return _discovery()
        if url == _discovery()["jwks_uri"]:
            return _jwks()
        raise AssertionError(f"unexpected network call: {url}")
    monkeypatch.setattr(oidc_client, "_http_get", fake_get)


@pytest.fixture
def authentik_env(monkeypatch):
    """Provider configuration only — the network is left alone."""
    monkeypatch.setenv("OIDC_PROVIDERS", "authentik")
    monkeypatch.setenv("OIDC_AUTHENTIK_NAME", "Authentik")
    monkeypatch.setenv("OIDC_AUTHENTIK_ISSUER", ISSUER)
    monkeypatch.setenv("OIDC_AUTHENTIK_CLIENT_ID", WEB_CLIENT)
    monkeypatch.setenv("OIDC_AUTHENTIK_MOBILE_CLIENT_ID", MOBILE_CLIENT)
    oidc_config.reset_cache()
    oidc_client.reset_cache()
    yield
    oidc_config.reset_cache()
    oidc_client.reset_cache()


@pytest.fixture
def authentik(authentik_env, stub_network):
    """Configured provider with a working, stubbed IdP."""
    yield


def exchange(client, **over):
    body = {"provider": "authentik", "client_id": MOBILE_CLIENT,
            "id_token": make_id_token(aud=MOBILE_CLIENT)}
    body.update(over)
    return client.post("/api/auth/oidc/exchange", json=body)


def db_session():
    return SessionLocal()


# ── unconfigured: SSO must be completely invisible ───────────────────────────

def test_disabled_when_unconfigured(client):
    oidc_config.reset_cache()
    r = client.get("/api/auth/oidc/providers")
    assert r.status_code == 200
    assert r.json() == {"enabled": False, "providers": []}
    assert client.get("/api/auth/oidc/authentik/start",
                      follow_redirects=False).status_code == 404


def test_password_login_still_works_with_sso_enabled(client, authentik):
    register_admin(client, "admin", "pw")
    r = client.post("/api/auth/login", json={"username": "admin", "password": "pw"})
    assert r.status_code == 200
    assert r.json()["user"]["username"] == "admin"


# ── /providers ───────────────────────────────────────────────────────────────

def test_providers_lists_endpoints(client, authentik):
    body = client.get("/api/auth/oidc/providers").json()
    assert body["enabled"] is True
    p = body["providers"][0]
    assert p["key"] == "authentik"
    assert p["name"] == "Authentik"
    assert p["mobile_client_id"] == MOBILE_CLIENT
    assert p["authorization_endpoint"] == _discovery()["authorization_endpoint"]


def test_mobile_scopes_include_offline_access_by_default(client, authentik):
    """The apps need a refresh token, so the server asks for offline_access."""
    p = client.get("/api/auth/oidc/providers").json()["providers"][0]
    assert "offline_access" in p["mobile_scopes"].split()
    # The browser flow does not need it and must not be changed by this.
    assert "offline_access" not in p["scopes"].split()


def test_mobile_scopes_are_overridable(client, authentik, monkeypatch):
    """A provider that cannot grant offline_access must be configurable."""
    monkeypatch.setenv("OIDC_AUTHENTIK_MOBILE_SCOPES", "openid email")
    oidc_config.reset_cache()
    p = client.get("/api/auth/oidc/providers").json()["providers"][0]
    assert p["mobile_scopes"] == "openid email"


def test_providers_never_leaks_client_secret(client, authentik, monkeypatch):
    secret = "super-secret-value-42"
    monkeypatch.setenv("OIDC_AUTHENTIK_CLIENT_SECRET", secret)
    oidc_config.reset_cache()
    r = client.get("/api/auth/oidc/providers")
    assert secret not in r.text


def test_provider_without_client_id_is_dropped(client, monkeypatch):
    monkeypatch.setenv("OIDC_PROVIDERS", "broken")
    monkeypatch.setenv("OIDC_BROKEN_ISSUER", ISSUER)
    oidc_config.reset_cache()
    assert client.get("/api/auth/oidc/providers").json()["enabled"] is False
    oidc_config.reset_cache()


# ── browser flow: /start and /callback ───────────────────────────────────────

def test_start_redirects_with_pkce_and_sets_flow_cookie(client, authentik):
    register_admin(client, "admin", "pw")
    r = client.get("/api/auth/oidc/authentik/start", follow_redirects=False)
    assert r.status_code == 302
    loc = r.headers["location"]
    assert loc.startswith(_discovery()["authorization_endpoint"])
    for expected in ("code_challenge=", "code_challenge_method=S256",
                     "state=", "nonce=", "response_type=code"):
        assert expected in loc
    # The PKCE verifier must never travel to the provider.
    assert "code_verifier" not in loc
    cookie_header = r.headers["set-cookie"]
    assert "clr_oidc_flow=" in cookie_header
    assert "HttpOnly" in cookie_header
    # Lax, not Strict: the cookie has to survive the IdP's cross-site redirect.
    assert "SameSite=lax" in cookie_header.replace("samesite", "SameSite")


def test_start_refused_before_initial_setup(client, authentik):
    r = client.get("/api/auth/oidc/authentik/start", follow_redirects=False)
    assert r.status_code == 302
    assert "sso_error=setup_required" in r.headers["location"]


def _break_network(monkeypatch):
    """Fail at the `requests` layer, below _http_get, so the real error
    translation in _http_get is what gets exercised."""
    import requests as real_requests

    def boom(*a, **k):
        raise real_requests.ConnectionError("dns go boom")
    monkeypatch.setattr(oidc_client.http_requests, "get", boom)
    monkeypatch.setattr(oidc_client.http_requests, "post", boom)
    oidc_client.reset_cache()


def test_start_survives_unreachable_provider(client, authentik_env, monkeypatch):
    """An unreachable IdP must be a clean error, not an HTTP 500."""
    register_admin(client, "admin", "pw")
    _break_network(monkeypatch)

    r = client.get("/api/auth/oidc/authentik/start", follow_redirects=False)
    assert r.status_code == 302
    assert "sso_error=oidc_provider_unreachable" in r.headers["location"]


def test_providers_stays_up_when_discovery_is_down(client, authentik_env, monkeypatch):
    """The login screen must render even if the IdP is unreachable."""
    _break_network(monkeypatch)
    body = client.get("/api/auth/oidc/providers").json()
    assert body["enabled"] is True
    assert body["providers"][0]["degraded"] is True


def test_exchange_survives_unreachable_jwks(client, authentik_env, monkeypatch):
    """A JWKS fetch failure must be a 401, not an HTTP 500."""
    _seed_identity(client)
    _break_network(monkeypatch)
    assert exchange(client).status_code == 401


def test_callback_rejects_missing_cookie(client, authentik):
    register_admin(client, "admin", "pw")
    r = client.get("/api/auth/oidc/authentik/callback?code=x&state=y",
                   follow_redirects=False)
    assert "sso_error=state_mismatch" in r.headers["location"]


def test_callback_rejects_state_mismatch(client, authentik, monkeypatch):
    register_admin(client, "admin", "pw")
    client.get("/api/auth/oidc/authentik/start", follow_redirects=False)
    r = client.get("/api/auth/oidc/authentik/callback?code=x&state=tampered",
                   follow_redirects=False)
    assert "sso_error=state_mismatch" in r.headers["location"]
    with db_session() as db:
        assert db.query(models.User).count() == 1  # only the admin


def test_callback_happy_path_logs_in_linked_user(client, authentik, monkeypatch):
    admin_token = register_admin(client, "admin", "pw")
    uid, _ = create_user(client, admin_token, "alice")

    start = client.get("/api/auth/oidc/authentik/start", follow_redirects=False)
    state = _state_from(start.headers["location"])

    with db_session() as db:
        db.add(models.OIDCIdentity(user_id=uid, provider_key="authentik",
                                   issuer=ISSUER, subject="ak-alice"))
        db.commit()

    nonce = _nonce_from(start.headers["location"])
    monkeypatch.setattr(oidc_client, "exchange_code", lambda *a, **k: {
        "id_token": make_id_token(sub="ak-alice", nonce=nonce, email="alice@example.com"),
    })

    cb = client.get(f"/api/auth/oidc/authentik/callback?code=good&state={state}",
                    follow_redirects=False)
    assert cb.status_code == 302
    assert cb.headers["location"] == "/?sso=1"
    assert "clr_oidc_token=" in cb.headers["set-cookie"]

    done = client.post("/api/auth/oidc/complete")
    assert done.status_code == 200
    assert done.json()["user"]["username"] == "alice"

    # The handoff cookie is single-use.
    assert client.post("/api/auth/oidc/complete").status_code == 401


def _state_from(location: str) -> str:
    from urllib.parse import parse_qs, urlparse
    return parse_qs(urlparse(location).query)["state"][0]


def _nonce_from(location: str) -> str:
    from urllib.parse import parse_qs, urlparse
    return parse_qs(urlparse(location).query)["nonce"][0]


def _run_callback(client, monkeypatch, *, sub, email):
    """Drive /start + /callback for an identity, returning the callback response."""
    start = client.get("/api/auth/oidc/authentik/start", follow_redirects=False)
    state = _state_from(start.headers["location"])
    nonce = _nonce_from(start.headers["location"])
    monkeypatch.setattr(oidc_client, "exchange_code", lambda *a, **k: {
        "id_token": make_id_token(sub=sub, nonce=nonce, email=email),
    })
    return client.get(f"/api/auth/oidc/authentik/callback?code=good&state={state}",
                      follow_redirects=False)


def test_unlinked_identity_offers_linking_instead_of_failing(client, authentik, monkeypatch):
    """An unknown SSO identity parks itself rather than dead-ending."""
    admin_token = register_admin(client, "admin", "pw")
    create_user(client, admin_token, "erin")

    cb = _run_callback(client, monkeypatch, sub="ak-erin", email="erin@example.com")
    assert cb.status_code == 302
    assert cb.headers["location"] == "/?sso_link=1"
    assert "clr_oidc_link=" in cb.headers["set-cookie"]
    # Nothing is linked until an account proves itself.
    with db_session() as db:
        assert db.query(models.OIDCIdentity).count() == 0


def test_password_login_redeems_the_parked_identity(client, authentik, monkeypatch):
    admin_token = register_admin(client, "admin", "pw")
    uid, _ = create_user(client, admin_token, "erin")
    _run_callback(client, monkeypatch, sub="ak-erin", email="erin@example.com")

    # The user signs in with their password; the client then redeems the cookie.
    login = client.post("/api/auth/login", json={"username": "erin", "password": "pw"})
    token = login.json()["access_token"]
    linked = client.post("/api/auth/oidc/link-pending", headers=auth(token))
    assert linked.status_code == 200, linked.text
    assert linked.json()["linked"] is True

    with db_session() as db:
        identity = db.query(models.OIDCIdentity).one()
        assert identity.user_id == uid
        assert identity.subject == "ak-erin"

    # From now on SSO alone gets them in.
    again = _run_callback(client, monkeypatch, sub="ak-erin", email="erin@example.com")
    assert again.headers["location"] == "/?sso=1"


def test_parked_identity_links_to_whoever_signs_in(client, authentik, monkeypatch):
    """The link follows the password login, not the email in the token — that
    is the whole point of asking instead of matching."""
    admin_token = register_admin(client, "admin", "pw")
    other_id, _ = create_user(client, admin_token, "frank")
    _run_callback(client, monkeypatch, sub="ak-erin", email="erin@example.com")

    login = client.post("/api/auth/login", json={"username": "frank", "password": "pw"})
    client.post("/api/auth/oidc/link-pending", headers=auth(login.json()["access_token"]))

    with db_session() as db:
        assert db.query(models.OIDCIdentity).one().user_id == other_id


def test_link_pending_without_a_cookie_is_a_404(client, authentik):
    admin_token = register_admin(client, "admin", "pw")
    _, token = create_user(client, admin_token, "erin")
    assert client.post("/api/auth/oidc/link-pending", headers=auth(token)).status_code == 404


def test_link_cookie_is_single_use(client, authentik, monkeypatch):
    admin_token = register_admin(client, "admin", "pw")
    _, token = create_user(client, admin_token, "erin")
    _run_callback(client, monkeypatch, sub="ak-erin", email="erin@example.com")

    assert client.post("/api/auth/oidc/link-pending", headers=auth(token)).status_code == 200
    assert client.post("/api/auth/oidc/link-pending", headers=auth(token)).status_code == 404


def test_link_pending_requires_authentication(client, authentik, monkeypatch):
    register_admin(client, "admin", "pw")
    _run_callback(client, monkeypatch, sub="ak-erin", email="erin@example.com")
    assert client.post("/api/auth/oidc/link-pending").status_code == 401


# ── /exchange: token validation (the mobile entry point) ─────────────────────

def _seed_identity(client, sub="ak-sub-1", username="alice"):
    admin_token = register_admin(client, "admin", "pw")
    uid, _ = create_user(client, admin_token, username)
    with db_session() as db:
        db.add(models.OIDCIdentity(user_id=uid, provider_key="authentik",
                                   issuer=ISSUER, subject=sub))
        db.commit()
    return uid


def test_exchange_happy_path(client, authentik):
    _seed_identity(client)
    r = exchange(client)
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    me = client.get("/api/auth/me", headers=auth(token))
    assert me.status_code == 200
    assert me.json()["username"] == "alice"


def test_exchange_rejects_alg_none(client, authentik):
    """Regression guard for the pinned signature-algorithm allow-list."""
    import base64
    import json

    def b64(raw):
        return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()

    header = b64(json.dumps({"alg": "none", "kid": _KID}).encode())
    payload = b64(json.dumps({
        "iss": ISSUER, "sub": "ak-sub-1", "aud": MOBILE_CLIENT,
        "iat": int(time.time()), "exp": int(time.time()) + 300,
    }).encode())
    _seed_identity(client)
    r = exchange(client, id_token=f"{header}.{payload}.")
    assert r.status_code == 401


def test_exchange_rejects_bad_signature(client, authentik):
    other_key = JsonWebKey.generate_key("RSA", 2048, is_private=True)
    _seed_identity(client)
    r = exchange(client, id_token=make_id_token(aud=MOBILE_CLIENT, key=other_key))
    assert r.status_code == 401


def test_exchange_rejects_wrong_issuer(client, authentik):
    _seed_identity(client)
    r = exchange(client, id_token=make_id_token(aud=MOBILE_CLIENT,
                                                iss="https://evil.example.com/"))
    assert r.status_code == 401


def test_exchange_rejects_wrong_audience(client, authentik):
    _seed_identity(client)
    # A token minted for the web client replayed against the mobile client id.
    r = exchange(client, id_token=make_id_token(aud=WEB_CLIENT))
    assert r.status_code == 401


def test_exchange_rejects_expired_token(client, authentik):
    _seed_identity(client)
    r = exchange(client, id_token=make_id_token(aud=MOBILE_CLIENT, exp_delta=-3600))
    assert r.status_code == 401


def test_exchange_rejects_unknown_client_id(client, authentik):
    _seed_identity(client)
    r = exchange(client, client_id="some-other-app",
                 id_token=make_id_token(aud="some-other-app"))
    assert r.status_code == 401


def test_exchange_rejects_nonce_mismatch(client, authentik):
    _seed_identity(client)
    r = exchange(client, nonce="expected-nonce",
                 id_token=make_id_token(aud=MOBILE_CLIENT, nonce="different"))
    assert r.status_code == 401


def test_refreshed_token_without_nonce_is_accepted(client, authentik):
    """A token renewed via the refresh token drops the nonce claim; the app
    still sends the nonce it remembers, and that must not be a mismatch."""
    _seed_identity(client)
    r = exchange(client, nonce="original-nonce",
                 id_token=make_id_token(aud=MOBILE_CLIENT, nonce=None))
    assert r.status_code == 200, r.text


def test_browser_flow_requires_a_nonce_in_the_token(client, authentik):
    """We generate the nonce for the browser flow, so the provider must echo
    it — a token without one is refused there even though /exchange allows it."""
    import oidc_config
    from oidc_client import OIDCError

    provider = oidc_config.get_provider("authentik")
    with pytest.raises(OIDCError) as e:
        oidc_client.validate_id_token(
            provider, make_id_token(nonce=None),
            expected_audience=WEB_CLIENT, nonce="expected", require_nonce=True)
    assert e.value.slug == "oidc_nonce_missing"


def test_exchange_requires_nonce_when_token_carries_one(client, authentik):
    _seed_identity(client)
    r = exchange(client, id_token=make_id_token(aud=MOBILE_CLIENT, nonce="from-appauth"))
    assert r.status_code == 400


def test_exchange_accepts_no_secret_field(client, authentik):
    """A public client must not be able to authenticate with a secret."""
    _seed_identity(client)
    r = exchange(client, client_secret="anything")   # extra field is ignored
    assert r.status_code == 200


# ── account mapping and provisioning ─────────────────────────────────────────

def test_autoprovision_disabled_by_default(client, authentik):
    register_admin(client, "admin", "pw")
    r = exchange(client, id_token=make_id_token(aud=MOBILE_CLIENT, sub="new-sub",
                                                email="new@example.com"))
    assert r.status_code == 403
    assert r.json()["detail"] == "oidc_signup_disabled"
    with db_session() as db:
        assert db.query(models.User).count() == 1


def test_autoprovision_creates_user_with_settings(client, authentik, monkeypatch):
    monkeypatch.setenv("OIDC_AUTHENTIK_ALLOW_SIGNUP", "true")
    oidc_config.reset_cache()
    register_admin(client, "admin", "pw")

    r = exchange(client, id_token=make_id_token(
        aud=MOBILE_CLIENT, sub="new-sub", email="new@example.com",
        preferred_username="Neuer Nutzer"))
    assert r.status_code == 200, r.text

    with db_session() as db:
        user = db.query(models.User).filter(models.User.email == "new@example.com").one()
        assert user.auth_source == "sso"
        assert user.is_admin is False
        assert user.username == "neuernutzer"     # normalised
        # Without this row /api/settings would 500 for the new user.
        assert db.query(models.UserSettings).filter(
            models.UserSettings.user_id == user.id).count() == 1

    settings = client.get("/api/settings/", headers=auth(r.json()["access_token"]))
    assert settings.status_code == 200


def test_domain_allowlist_blocks_foreign_domain(client, authentik, monkeypatch):
    monkeypatch.setenv("OIDC_AUTHENTIK_ALLOW_SIGNUP", "true")
    monkeypatch.setenv("OIDC_AUTHENTIK_ALLOWED_DOMAINS", "allowed.example")
    oidc_config.reset_cache()
    register_admin(client, "admin", "pw")

    r = exchange(client, id_token=make_id_token(aud=MOBILE_CLIENT, sub="s2",
                                                email="x@forbidden.example"))
    assert r.status_code == 403
    assert r.json()["detail"] == "oidc_domain_not_allowed"

    ok = exchange(client, id_token=make_id_token(aud=MOBILE_CLIENT, sub="s3",
                                                 email="y@allowed.example"))
    assert ok.status_code == 200


def test_email_match_on_existing_account_is_refused(client, authentik):
    """The account-takeover guard: no silent linking by email address."""
    admin_token = register_admin(client, "admin", "pw")
    client.post("/api/users/", headers=auth(admin_token),
                json={"username": "bob", "password": "pw", "email": "bob@example.com"})

    r = exchange(client, id_token=make_id_token(aud=MOBILE_CLIENT, sub="ak-bob",
                                                email="bob@example.com"))
    assert r.status_code == 403
    assert r.json()["detail"] == "oidc_account_not_linked"
    with db_session() as db:
        assert db.query(models.OIDCIdentity).count() == 0


def test_link_by_email_requires_verified_email(client, authentik, monkeypatch):
    monkeypatch.setenv("OIDC_AUTHENTIK_LINK_BY_EMAIL", "true")
    oidc_config.reset_cache()
    admin_token = register_admin(client, "admin", "pw")
    client.post("/api/users/", headers=auth(admin_token),
                json={"username": "bob", "password": "pw", "email": "bob@example.com"})

    bad = exchange(client, id_token=make_id_token(
        aud=MOBILE_CLIENT, sub="ak-bob", email="bob@example.com", email_verified=False))
    assert bad.status_code == 403
    assert bad.json()["detail"] == "oidc_email_not_verified"

    good = exchange(client, id_token=make_id_token(
        aud=MOBILE_CLIENT, sub="ak-bob", email="bob@example.com", email_verified=True))
    assert good.status_code == 200
    assert good.json()["user"]["username"] == "bob"


def test_username_collision_gets_suffix(client, authentik, monkeypatch):
    monkeypatch.setenv("OIDC_AUTHENTIK_ALLOW_SIGNUP", "true")
    oidc_config.reset_cache()
    register_admin(client, "admin", "pw")

    # A different human whose preferred_username happens to be "admin".
    r = exchange(client, id_token=make_id_token(
        aud=MOBILE_CLIENT, sub="other-human", email="other@example.com",
        preferred_username="admin"))
    assert r.status_code == 200
    assert r.json()["user"]["username"] == "admin-2"
    with db_session() as db:
        assert db.query(models.User).filter(models.User.username == "admin").one().is_admin


def test_email_collision_during_signup_is_refused(client, authentik, monkeypatch):
    monkeypatch.setenv("OIDC_AUTHENTIK_ALLOW_SIGNUP", "true")
    oidc_config.reset_cache()
    admin_token = register_admin(client, "admin", "pw")
    client.post("/api/users/", headers=auth(admin_token),
                json={"username": "carol", "password": "pw", "email": "carol@example.com"})

    r = exchange(client, id_token=make_id_token(aud=MOBILE_CLIENT, sub="ak-carol",
                                                email="carol@example.com"))
    # Refused rather than forking one human into a second account.
    assert r.status_code == 403
    with db_session() as db:
        assert db.query(models.User).filter(
            models.User.email == "carol@example.com").count() == 1


def test_second_login_reuses_the_same_account(client, authentik, monkeypatch):
    monkeypatch.setenv("OIDC_AUTHENTIK_ALLOW_SIGNUP", "true")
    oidc_config.reset_cache()
    register_admin(client, "admin", "pw")

    first = exchange(client, id_token=make_id_token(aud=MOBILE_CLIENT, sub="stable",
                                                    email="a@example.com"))
    # Same sub, different email and username at the provider.
    second = exchange(client, id_token=make_id_token(
        aud=MOBILE_CLIENT, sub="stable", email="renamed@example.com",
        preferred_username="renamed"))
    assert first.json()["user"]["id"] == second.json()["user"]["id"]
    with db_session() as db:
        assert db.query(models.OIDCIdentity).count() == 1


# ── the password_hash trap ───────────────────────────────────────────────────

def test_sso_user_password_login_fails_without_500(client, authentik, monkeypatch):
    monkeypatch.setenv("OIDC_AUTHENTIK_ALLOW_SIGNUP", "true")
    oidc_config.reset_cache()
    register_admin(client, "admin", "pw")
    exchange(client, id_token=make_id_token(aud=MOBILE_CLIENT, sub="s", email="s@example.com",
                                            preferred_username="ssouser"))

    r = client.post("/api/auth/login", json={"username": "ssouser", "password": ""})
    assert r.status_code == 401, f"expected 401, got {r.status_code}"


def test_verify_password_survives_malformed_hash():
    from auth import verify_password
    for broken in ("", "!", "not-a-bcrypt-hash"):
        assert verify_password("anything", broken) is False


# ── linking and unlinking from a session ─────────────────────────────────────

def test_link_and_unlink_identity(client, authentik):
    admin_token = register_admin(client, "admin", "pw")
    _, token = create_user(client, admin_token, "dave")

    r = client.post("/api/auth/oidc/authentik/link", headers=auth(token),
                    json={"id_token": make_id_token(sub="ak-dave"),
                          "client_id": WEB_CLIENT})
    assert r.status_code == 200, r.text
    identity_id = r.json()["id"]

    listed = client.get("/api/auth/oidc/identities", headers=auth(token)).json()
    assert len(listed["identities"]) == 1
    assert listed["auth_source"] == "local"

    # Now SSO login for that identity works.
    ex = exchange(client, client_id=MOBILE_CLIENT,
                  id_token=make_id_token(sub="ak-dave", aud=MOBILE_CLIENT))
    assert ex.status_code == 200
    assert ex.json()["user"]["username"] == "dave"

    assert client.delete(f"/api/auth/oidc/identities/{identity_id}",
                         headers=auth(token)).status_code == 200


def test_cannot_link_identity_owned_by_someone_else(client, authentik):
    admin_token = register_admin(client, "admin", "pw")
    _, dave = create_user(client, admin_token, "dave")
    _, eve = create_user(client, admin_token, "eve")

    client.post("/api/auth/oidc/authentik/link", headers=auth(dave),
                json={"id_token": make_id_token(sub="ak-dave"), "client_id": WEB_CLIENT})
    r = client.post("/api/auth/oidc/authentik/link", headers=auth(eve),
                    json={"id_token": make_id_token(sub="ak-dave"), "client_id": WEB_CLIENT})
    assert r.status_code == 409


def test_sso_only_user_cannot_unlink_last_identity(client, authentik, monkeypatch):
    monkeypatch.setenv("OIDC_AUTHENTIK_ALLOW_SIGNUP", "true")
    oidc_config.reset_cache()
    register_admin(client, "admin", "pw")
    r = exchange(client, id_token=make_id_token(aud=MOBILE_CLIENT, sub="lonely",
                                                email="lonely@example.com"))
    token = r.json()["access_token"]

    identities = client.get("/api/auth/oidc/identities", headers=auth(token)).json()
    only = identities["identities"][0]["id"]
    assert identities["auth_source"] == "sso"

    resp = client.delete(f"/api/auth/oidc/identities/{only}", headers=auth(token))
    assert resp.status_code == 400
    assert resp.json()["detail"] == "oidc_last_identity"


# ── token type confusion ─────────────────────────────────────────────────────

def test_flow_token_cannot_be_used_as_access_token(client, authentik):
    from routers.oidc_router import _encode_flow
    register_admin(client, "admin", "pw")
    flow = _encode_flow({"p": "authentik", "n": "n", "cv": "v", "jti": "s"})
    assert client.get("/api/auth/me", headers=auth(flow)).status_code == 401
