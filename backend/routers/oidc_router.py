"""OpenID Connect single sign-on — browser flow and native-client exchange.

Two consumers:

* **Web** — ``/start`` redirects to the provider, ``/callback`` receives the
  code, ``/complete`` hands the Calendarr JWT to the SPA.
* **Mobile** — the app runs the whole flow itself as a *public* client
  (AppAuth, PKCE, ``offline_access``) and trades the resulting ID token for a
  Calendarr JWT at ``/exchange``. It never sends a client secret.

Flow state (PKCE verifier, nonce) lives in a short-lived signed JWT in an
HttpOnly cookie rather than in a process-local dict like
``homeassistant_router._pending_oauth`` — so it survives a restart and works
with more than one worker.
"""

from __future__ import annotations

import base64
import hashlib
import logging
import secrets
from datetime import datetime, timedelta
from typing import Optional
from urllib.parse import urlencode

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request, Response
from fastapi.responses import RedirectResponse
from jose import JWTError, jwt
from pydantic import BaseModel
from sqlalchemy.orm import Session

import models
import oidc_client
import oidc_config
from auth import ALGORITHM, SECRET_KEY, create_user_token, get_current_user
from database import get_db
from dav_util import public_base
from oidc_client import OIDCError
from oidc_identity import OIDCPolicyError, link_identity, resolve_user

logger = logging.getLogger(__name__)

router = APIRouter()

FLOW_COOKIE = "clr_oidc_flow"
FLOW_TTL = 600          # 10 minutes to complete a login
HANDOFF_COOKIE = "clr_oidc_token"
HANDOFF_TTL = 60        # the SPA picks the token up immediately
LINK_COOKIE = "clr_oidc_link"
LINK_TTL = 900          # 15 minutes to sign in with a password and link

# Refusals that mean "this identity is fine, it just has no owner yet". In all
# three the honest answer is to ask the user to prove which account is theirs,
# rather than to dead-end them: no account exists, one exists under the same
# address, or automatic creation is switched off.
LINKABLE_REFUSALS = {
    "oidc_account_not_linked",
    "oidc_signup_disabled",
    "oidc_email_conflict",
}
LINK_RETURN = "/?sso_linked=1"


# ── flow-state cookie ────────────────────────────────────────────────────────

def _cookie_kwargs(request: Request, path: str, max_age: int) -> dict:
    return {
        "httponly": True,
        # Lax, NOT Strict: the cookie has to survive the identity provider's
        # top-level cross-site redirect back to /callback. With Strict the
        # browser drops it and every single login fails with state_mismatch.
        "samesite": "lax",
        "secure": public_base(request).startswith("https"),
        "path": path,
        "max_age": max_age,
    }


def _encode_flow(payload: dict) -> str:
    data = dict(payload)
    data["typ"] = "oidc_flow"
    data["exp"] = datetime.utcnow() + timedelta(seconds=FLOW_TTL)
    return jwt.encode(data, SECRET_KEY, algorithm=ALGORITHM)


def _encode_link(claims: dict, provider_key: str) -> str:
    """A verified-but-unlinked identity, parked until the user proves the
    Calendarr account is theirs by signing in with their password."""
    data = {
        "typ": "oidc_link",
        "p": provider_key,
        "sub": claims.get("sub"),
        "iss": claims.get("iss"),
        "email": claims.get("email"),
        "exp": datetime.utcnow() + timedelta(seconds=LINK_TTL),
    }
    return jwt.encode(data, SECRET_KEY, algorithm=ALGORITHM)


def _decode_link(token: str) -> Optional[dict]:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        return None
    if payload.get("typ") != "oidc_link" or not payload.get("sub"):
        return None
    return payload


def _decode_flow(token: str) -> Optional[dict]:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        return None
    # Guard against another token type being replayed here.
    if payload.get("typ") != "oidc_flow":
        return None
    return payload


def _pkce_pair() -> tuple:
    verifier = secrets.token_urlsafe(64)
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    challenge = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
    return verifier, challenge


def _redirect_uri(request: Request, provider) -> str:
    """Always derived server-side — never taken from client input."""
    if provider.redirect_uri:
        return provider.redirect_uri
    return f"{public_base(request)}/api/auth/oidc/{provider.key}/callback"


def _fail(request: Request, slug: str) -> RedirectResponse:
    resp = RedirectResponse(url=f"/?sso_error={slug}", status_code=302)
    resp.delete_cookie(FLOW_COOKIE, path="/api/auth/oidc")
    return resp


# ── discovery for clients ────────────────────────────────────────────────────

@router.get("/providers")
def list_providers():
    """Public: what the login screen and the mobile apps need to start a flow.

    Never exposes the client secret.
    """
    out = []
    for provider in oidc_config.get_providers().values():
        entry = {
            "key": provider.key,
            "name": provider.name,
            "icon": provider.icon,
            "issuer": provider.issuer,
            "scopes": provider.scopes,
            "start_url": f"/api/auth/oidc/{provider.key}/start",
        }
        if provider.mobile_client_ids:
            entry["mobile_client_id"] = provider.mobile_client_ids[0]
            # The apps request exactly these — they must not invent scopes of
            # their own, or a provider that lacks one rejects the whole flow.
            entry["mobile_scopes"] = provider.mobile_scopes
        try:
            doc = oidc_client.discover(provider)
            entry["authorization_endpoint"] = doc.get("authorization_endpoint")
            entry["token_endpoint"] = doc.get("token_endpoint")
            entry["end_session_endpoint"] = doc.get("end_session_endpoint")
        except Exception as e:
            # A provider whose discovery is down must not break the login page.
            logger.warning("OIDC discovery failed for %s: %s", provider.key, e)
            entry["degraded"] = True
        out.append(entry)
    return {"enabled": bool(out), "providers": out}


# ── browser flow ─────────────────────────────────────────────────────────────

@router.get("/{provider_key}/start")
def oidc_start(provider_key: str, request: Request, db: Session = Depends(get_db)):
    provider = oidc_config.get_provider(provider_key)
    if provider is None:
        raise HTTPException(404, "Unbekannter SSO-Anbieter")

    # Before the first-run admin exists, an SSO login would create a non-admin
    # account and leave the instance unadministrable.
    if db.query(models.User).count() == 0:
        return _fail(request, "setup_required")

    try:
        authorize_url = oidc_client.authorization_endpoint(provider)
    except OIDCError as e:
        logger.warning("OIDC start failed for %s: %s", provider.key, e.detail)
        return _fail(request, e.slug)

    verifier, challenge = _pkce_pair()
    nonce = secrets.token_urlsafe(24)
    state = secrets.token_urlsafe(16)
    redirect_uri = _redirect_uri(request, provider)

    params = {
        "response_type": "code",
        "client_id": provider.client_id,
        "redirect_uri": redirect_uri,
        "scope": provider.scopes,
        "state": state,
        "nonce": nonce,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    }
    resp = RedirectResponse(url=f"{authorize_url}?{urlencode(params)}", status_code=302)
    # Only `state` travels over the wire; verifier and nonce stay in the cookie
    # and therefore out of the provider's access logs.
    resp.set_cookie(
        FLOW_COOKIE,
        _encode_flow({"p": provider.key, "n": nonce, "cv": verifier, "jti": state}),
        **_cookie_kwargs(request, "/api/auth/oidc", FLOW_TTL),
    )
    return resp


@router.get("/{provider_key}/callback")
def oidc_callback(provider_key: str, request: Request,
                  code: str = Query(""), state: str = Query(""),
                  error: str = Query(""), db: Session = Depends(get_db)):
    provider = oidc_config.get_provider(provider_key)
    if provider is None:
        return _fail(request, "unknown_provider")
    if error or not code:
        return _fail(request, error or "no_code")

    raw = request.cookies.get(FLOW_COOKIE)
    payload = _decode_flow(raw) if raw else None
    # Double-submit: the state in the URL must match the one in the cookie, so
    # an attacker cannot feed a victim a callback URL from their own flow.
    if not payload or payload.get("p") != provider.key or payload.get("jti") != state:
        return _fail(request, "state_mismatch")

    try:
        tokens = oidc_client.exchange_code(
            provider, code, _redirect_uri(request, provider), payload["cv"])
        claims = oidc_client.validate_id_token(
            provider, tokens["id_token"],
            expected_audience=provider.client_id,
            nonce=payload.get("n"),
            # We generated this nonce; the provider must echo it back.
            require_nonce=True,
            access_token=tokens.get("access_token"),
        )
        if not claims.get("email"):
            claims.update({k: v for k, v in
                           oidc_client.fetch_userinfo(
                               provider, tokens.get("access_token") or "").items()
                           if k not in claims})
    except OIDCError as e:
        logger.warning("OIDC callback failed for %s: %s", provider.key, e.detail)
        return _fail(request, e.slug)

    try:
        user, action = resolve_user(db, provider, claims)
    except OIDCPolicyError as e:
        if e.slug in LINKABLE_REFUSALS:
            # The identity is verified but belongs to nobody yet. Park it and
            # invite the user to prove the Calendarr account is theirs. That is
            # strictly safer than matching on the email address alone, which
            # trusts the provider not to hand out someone else's.
            resp = RedirectResponse(url="/?sso_link=1", status_code=302)
            resp.delete_cookie(FLOW_COOKIE, path="/api/auth/oidc")
            resp.set_cookie(
                LINK_COOKIE, _encode_link(claims, provider.key),
                **_cookie_kwargs(request, "/api/auth/oidc", LINK_TTL),
            )
            return resp
        return _fail(request, e.slug)

    logger.info("OIDC login (%s) user id=%s via %s", action, user.id, provider.key)
    token = create_user_token(user)

    resp = RedirectResponse(url="/?sso=1", status_code=302)
    resp.delete_cookie(FLOW_COOKIE, path="/api/auth/oidc")
    # The token goes in an HttpOnly cookie, not in the URL: a query parameter
    # would land in the reverse-proxy and uvicorn access logs and in Referer,
    # and a fragment would persist in browser history.
    resp.set_cookie(
        HANDOFF_COOKIE, token,
        **_cookie_kwargs(request, "/api/auth/oidc", HANDOFF_TTL),
    )
    return resp


@router.post("/complete")
def oidc_complete(request: Request, response: Response, db: Session = Depends(get_db)):
    """Trade the one-time handoff cookie for the token, same-origin."""
    token = request.cookies.get(HANDOFF_COOKIE)
    # Clear it either way: one attempt per login, success or not.
    response.delete_cookie(HANDOFF_COOKIE, path="/api/auth/oidc")
    if not token:
        raise HTTPException(401, "Keine SSO-Sitzung")

    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        uid = payload.get("uid")
    except JWTError:
        raise HTTPException(401, "SSO-Sitzung ungültig")
    if uid is None:
        raise HTTPException(401, "SSO-Sitzung ungültig")

    user = db.query(models.User).filter(models.User.id == uid).first()
    if not user:
        raise HTTPException(401, "SSO-Sitzung ungültig")

    return {"access_token": token, "token_type": "bearer", "user": _user_dict(user)}


@router.post("/link-pending")
def oidc_link_pending(request: Request, response: Response,
                      current_user: models.User = Depends(get_current_user),
                      db: Session = Depends(get_db)):
    """Attach the parked SSO identity to the account that just signed in.

    Both halves are proven: we validated the ID token ourselves before parking
    it, and the bearer token proves this password login succeeded.
    """
    raw = request.cookies.get(LINK_COOKIE)
    response.delete_cookie(LINK_COOKIE, path="/api/auth/oidc")
    if not raw:
        raise HTTPException(404, "Keine offene SSO-Verknüpfung")

    payload = _decode_link(raw)
    if not payload:
        raise HTTPException(400, "oidc_link_expired")

    provider = oidc_config.get_provider(payload.get("p", ""))
    if provider is None:
        raise HTTPException(400, "oidc_unknown_provider")

    claims = {"sub": payload["sub"], "iss": payload.get("iss"),
              "email": payload.get("email")}
    try:
        link_identity(db, current_user, provider, claims)
    except OIDCPolicyError as e:
        raise HTTPException(409, e.slug)

    logger.info("OIDC: linked %s identity to user id=%s after password login",
                provider.key, current_user.id)
    return {"linked": True, "provider": provider.key, "name": provider.name}


# ── native (mobile) clients ──────────────────────────────────────────────────

class ExchangeRequest(BaseModel):
    """Deliberately has no client_secret field — public clients must not send one."""

    provider: str
    client_id: str
    id_token: str
    access_token: Optional[str] = None
    nonce: Optional[str] = None


@router.post("/exchange")
def oidc_exchange(req: ExchangeRequest, db: Session = Depends(get_db)):
    """Trade a provider ID token for a Calendarr JWT (AppAuth iOS/Android).

    The app has already completed the authorization-code flow with PKCE
    against the provider. Its security rests on PKCE plus the provider's
    registered redirect-URI check (RFC 8252), not on a secret.
    """
    provider = oidc_config.get_provider(req.provider)
    if provider is None:
        raise HTTPException(401, "oidc_unknown_provider")

    # Restrict to client ids we know: otherwise an ID token minted for an
    # unrelated application at the same provider could be replayed here.
    if req.client_id not in oidc_config.accepted_audiences(provider):
        raise HTTPException(401, "oidc_unknown_client")

    try:
        claims = oidc_client.validate_id_token(
            provider, req.id_token,
            expected_audience=req.client_id,
            nonce=req.nonce,
            access_token=req.access_token,
        )
    except OIDCError as e:
        logger.info("OIDC exchange rejected: %s", e.detail)
        raise HTTPException(401, e.slug)

    # The nonce is the app's replay protection; if the token carries one, the
    # caller has to prove it knows it.
    if claims.get("nonce") and not req.nonce:
        raise HTTPException(400, "oidc_nonce_required")

    if not claims.get("email") and req.access_token:
        claims.update({k: v for k, v in
                       oidc_client.fetch_userinfo(provider, req.access_token).items()
                       if k not in claims})

    try:
        user, action = resolve_user(db, provider, claims)
    except OIDCPolicyError as e:
        raise HTTPException(403, e.slug)

    logger.info("OIDC exchange (%s) user id=%s via %s", action, user.id, provider.key)
    return {
        "access_token": create_user_token(user),
        "token_type": "bearer",
        "user": _user_dict(user),
    }


# ── linking from an authenticated session ────────────────────────────────────

@router.get("/identities")
def list_identities(current_user: models.User = Depends(get_current_user)):
    return {
        "auth_source": current_user.auth_source or "local",
        "identities": [
            {
                "id": i.id,
                "provider": i.provider_key,
                "name": (oidc_config.get_provider(i.provider_key).name
                         if oidc_config.get_provider(i.provider_key) else i.provider_key),
                "email": i.email,
                "last_login_at": i.last_login_at.isoformat() if i.last_login_at else None,
            }
            for i in current_user.oidc_identities
        ],
    }


@router.post("/{provider_key}/link")
def link_current_user(provider_key: str,
                      id_token: str = Body(..., embed=True),
                      client_id: str = Body("", embed=True),
                      nonce: Optional[str] = Body(None, embed=True),
                      current_user: models.User = Depends(get_current_user),
                      db: Session = Depends(get_db)):
    """Attach an SSO identity to the signed-in account.

    This is the safe alternative to matching on email: the user proves they
    control both the Calendarr account (bearer token) and the SSO identity.
    """
    provider = oidc_config.get_provider(provider_key)
    if provider is None:
        raise HTTPException(404, "Unbekannter SSO-Anbieter")

    audience = client_id or provider.client_id
    if audience not in oidc_config.accepted_audiences(provider):
        raise HTTPException(400, "oidc_unknown_client")

    try:
        claims = oidc_client.validate_id_token(
            provider, id_token, expected_audience=audience, nonce=nonce)
    except OIDCError as e:
        raise HTTPException(400, e.slug)

    try:
        identity = link_identity(db, current_user, provider, claims)
    except OIDCPolicyError as e:
        raise HTTPException(409, e.slug)

    return {"linked": True, "id": identity.id, "provider": provider.key}


@router.delete("/identities/{identity_id}")
def unlink_identity(identity_id: int,
                    current_user: models.User = Depends(get_current_user),
                    db: Session = Depends(get_db)):
    identity = db.query(models.OIDCIdentity).filter(
        models.OIDCIdentity.id == identity_id,
        models.OIDCIdentity.user_id == current_user.id,
    ).first()
    if identity is None:
        raise HTTPException(404, "Verknüpfung nicht gefunden")

    # An SSO-provisioned user has no usable password, so removing their last
    # identity would lock them out permanently.
    if (current_user.auth_source or "local") == "sso" and len(current_user.oidc_identities) <= 1:
        raise HTTPException(400, "oidc_last_identity")

    db.delete(identity)
    db.commit()
    return {"unlinked": True}


def _user_dict(user: models.User) -> dict:
    """Same shape as auth_router's login response, so clients share a path."""
    return {
        "id": user.id,
        "username": user.username,
        "display_name": user.display_name or user.username,
        "is_admin": user.is_admin,
    }
