"""Mapping a verified OIDC identity onto a Calendarr user account.

The security-relevant decisions live here:

* ``(provider_key, sub)`` is the only automatic match. ``sub`` is the one claim
  an identity provider guarantees to be stable and unique; email and username
  are not.
* Matching a verified email onto an *existing* local account is refused by
  default. Anyone who can set an arbitrary email on an IdP account would
  otherwise inherit the matching Calendarr account — including an admin's.
  Linking is an explicit, authenticated action instead.
* Just-in-time provisioning is off unless the provider enables it.
"""

from __future__ import annotations

import hashlib
import logging
import re
import secrets
import unicodedata
from datetime import datetime
from typing import Optional, Tuple

from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

import models
from auth import get_password_hash
from oidc_config import OIDCProvider

logger = logging.getLogger(__name__)

USERNAME_MAX = 50
_USERNAME_STRIP = re.compile(r"[^a-z0-9._-]")


class OIDCPolicyError(Exception):
    """A refusal that is the user's/admin's to resolve, not a protocol fault.

    ``slug`` maps to a translated message on the login screen.
    """

    def __init__(self, slug: str, detail: str = ""):
        super().__init__(detail or slug)
        self.slug = slug
        self.detail = detail or slug


def claim_email(claims: dict) -> str:
    return (claims.get("email") or "").strip().lower()


def _normalise_username(raw: str) -> str:
    """Fold a claim value into the shape `users.username` requires."""
    if not raw:
        return ""
    folded = unicodedata.normalize("NFKD", raw)
    folded = folded.encode("ascii", "ignore").decode("ascii").lower()
    folded = _USERNAME_STRIP.sub("", folded)
    return folded.strip("._-")[:USERNAME_MAX]


def _username_taken(db: Session, name: str) -> bool:
    return db.query(models.User).filter(
        func.lower(models.User.username) == name.lower()
    ).first() is not None


def derive_username(db: Session, claims: dict, provider: OIDCProvider) -> str:
    """Pick a free, valid username for a newly provisioned SSO user.

    A collision here is a *different human* who happens to share a
    preferred_username, so we never reuse an existing name — that would be
    instant account takeover.
    """
    candidates = [
        claims.get(provider.username_claim),
        claim_email(claims).split("@")[0] if claim_email(claims) else "",
        "u" + hashlib.sha256((claims.get("sub") or "").encode()).hexdigest()[:12],
    ]
    base = ""
    for candidate in candidates:
        base = _normalise_username(candidate or "")
        if base:
            break
    if not base:
        base = "u" + secrets.token_hex(6)

    if not _username_taken(db, base):
        return base

    for suffix in range(2, 51):
        tail = f"-{suffix}"
        name = base[: USERNAME_MAX - len(tail)] + tail
        if not _username_taken(db, name):
            return name

    # Pathological case: fall back to something effectively unique.
    tail = "-" + secrets.token_hex(5)
    return base[: USERNAME_MAX - len(tail)] + tail


def _create_user(db: Session, provider: OIDCProvider, claims: dict,
                 email: str) -> models.User:
    """Provision a new account. Mirrors users_router.create_user."""
    # `users.password_hash` is NOT NULL and `auth.verify_password` feeds it
    # straight to bcrypt.checkpw, which raises ValueError on anything that is
    # not a real hash — that surfaces as HTTP 500 on /api/auth/login and on
    # every CalDAV Basic-Auth attempt. So store a real bcrypt hash of a random
    # secret that is never written down anywhere: unusable, but well-formed.
    user = models.User(
        username=derive_username(db, claims, provider),
        display_name=(claims.get("name") or "").strip()[:100] or None,
        email=email or None,
        password_hash=get_password_hash(secrets.token_urlsafe(48)),
        is_admin=False,
        auth_source="sso",
    )
    db.add(user)
    db.flush()
    # Without this row /api/settings returns 500 for the new user.
    db.add(models.UserSettings(user_id=user.id))
    return user


def _attach_identity(db: Session, user: models.User, provider: OIDCProvider,
                     claims: dict, email: str) -> models.OIDCIdentity:
    identity = models.OIDCIdentity(
        user_id=user.id,
        provider_key=provider.key,
        issuer=claims.get("iss") or provider.issuer,
        subject=claims["sub"],
        email=email or None,
        last_login_at=datetime.utcnow(),
    )
    db.add(identity)
    return identity


def find_identity(db: Session, provider: OIDCProvider,
                  subject: str) -> Optional[models.OIDCIdentity]:
    return db.query(models.OIDCIdentity).filter(
        models.OIDCIdentity.provider_key == provider.key,
        models.OIDCIdentity.subject == subject,
    ).first()


def link_identity(db: Session, user: models.User, provider: OIDCProvider,
                  claims: dict) -> models.OIDCIdentity:
    """Attach an SSO identity to an already-authenticated account."""
    subject = claims.get("sub") or ""
    if not subject:
        raise OIDCPolicyError("oidc_no_subject")

    existing = find_identity(db, provider, subject)
    if existing is not None:
        if existing.user_id != user.id:
            raise OIDCPolicyError("oidc_identity_taken")
        existing.last_login_at = datetime.utcnow()
        db.commit()
        return existing

    identity = _attach_identity(db, user, provider, claims, claim_email(claims))
    db.commit()
    return identity


def resolve_user(db: Session, provider: OIDCProvider,
                 claims: dict) -> Tuple[models.User, str]:
    """Map verified claims onto a user.

    Returns ``(user, action)`` where action is ``login``, ``linked`` or
    ``created``. Raises :class:`OIDCPolicyError` for every refusal.
    """
    subject = claims.get("sub") or ""
    if not subject:
        raise OIDCPolicyError("oidc_no_subject")
    email = claim_email(claims)

    # 1. Known identity — the only automatic path.
    identity = find_identity(db, provider, subject)
    if identity is not None:
        identity.last_login_at = datetime.utcnow()
        if email:
            identity.email = email
        db.commit()
        return identity.user, "login"

    # 2. An existing local account with the same email.
    existing = None
    if email:
        existing = db.query(models.User).filter(
            func.lower(models.User.email) == email
        ).first()

    if existing is not None:
        if not provider.link_by_email:
            # The account-takeover guard. Linking must be explicit.
            raise OIDCPolicyError("oidc_account_not_linked")
        if claims.get("email_verified") is not True:
            raise OIDCPolicyError("oidc_email_not_verified")
        logger.warning(
            "OIDC: linking provider=%s sub=%s to existing user id=%s by email %s",
            provider.key, subject, existing.id, email,
        )
        _attach_identity(db, existing, provider, claims, email)
        db.commit()
        return existing, "linked"

    # 3. Just-in-time provisioning.
    if not provider.allow_signup:
        raise OIDCPolicyError("oidc_signup_disabled")
    if not email:
        raise OIDCPolicyError("oidc_no_email")
    if provider.allowed_domains:
        domain = email.rsplit("@", 1)[-1]
        if domain not in provider.allowed_domains:
            raise OIDCPolicyError("oidc_domain_not_allowed")

    try:
        user = _create_user(db, provider, claims, email)
        _attach_identity(db, user, provider, claims, email)
        db.commit()
    except IntegrityError:
        # Race between the uniqueness check and the insert — retry once.
        db.rollback()
        try:
            user = _create_user(db, provider, claims, email)
            _attach_identity(db, user, provider, claims, email)
            db.commit()
        except IntegrityError:
            db.rollback()
            raise OIDCPolicyError("oidc_provisioning_failed")

    logger.info("OIDC: provisioned user id=%s username=%s via %s",
                user.id, user.username, provider.key)
    return user, "created"
