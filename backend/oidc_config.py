"""OpenID Connect provider configuration, read from environment variables.

A provider is declared by listing its key in ``OIDC_PROVIDERS`` and adding a
block of ``OIDC_<KEY>_<FIELD>`` variables::

    OIDC_PROVIDERS=authentik
    OIDC_AUTHENTIK_ISSUER=https://authentik.example.com/application/o/calendarr/
    OIDC_AUTHENTIK_CLIENT_ID=...
    OIDC_AUTHENTIK_CLIENT_SECRET=...

Adding a second provider is therefore a pure configuration change — append the
key to ``OIDC_PROVIDERS``, add its block, restart. No code change.

Everything here is read lazily via :func:`get_providers` rather than at import
time, because ``backend/tests/conftest.py`` sets the environment *after* the
app modules are imported.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass, field
from typing import Optional

logger = logging.getLogger(__name__)

# Values accepted as "true" in the boolean env vars.
_TRUE = {"1", "true", "yes", "on"}

DEFAULT_SCOPES = "openid profile email"


@dataclass(frozen=True)
class OIDCProvider:
    """One configured identity provider."""

    key: str                                  # url-safe, lowercase, e.g. "authentik"
    name: str                                 # display label, e.g. "Authentik"
    issuer: str                               # the exact `iss` we accept
    client_id: str                            # web/confidential client
    client_secret: str = ""                   # empty => public client, PKCE only
    scopes: str = DEFAULT_SCOPES
    redirect_uri: str = ""                    # empty => derived from public_base()
    mobile_client_ids: tuple = ()             # public native clients (AppAuth)
    mobile_scopes: str = ""                   # scopes the apps request (see below)
    mobile_issuer: str = ""                   # only if mobile uses a 2nd application
    allow_signup: bool = False                # just-in-time provisioning
    allowed_domains: tuple = ()               # email domain allowlist for signup
    link_by_email: bool = False               # auto-link to an existing account
    username_claim: str = "preferred_username"
    icon: str = ""

    @property
    def is_public(self) -> bool:
        """True when no client secret is configured (PKCE-only web client)."""
        return not self.client_secret


def _env(key: str, field_name: str, default: str = "") -> str:
    return os.environ.get(f"OIDC_{key.upper()}_{field_name}", default).strip()


def _env_bool(key: str, field_name: str, default: bool = False) -> bool:
    raw = _env(key, field_name)
    if not raw:
        return default
    return raw.lower() in _TRUE


def _env_list(key: str, field_name: str) -> tuple:
    raw = _env(key, field_name)
    return tuple(p.strip().lower() for p in raw.split(",") if p.strip())


def _build_provider(key: str) -> Optional[OIDCProvider]:
    """Build one provider from the environment, or None when unusable."""
    issuer = _env(key, "ISSUER")
    client_id = _env(key, "CLIENT_ID")

    # A half-configured provider must never half-work: dropping it keeps the
    # login screen honest (no button) instead of failing mid-flow.
    if not issuer or not client_id:
        logger.warning(
            "OIDC provider %r ignored: OIDC_%s_ISSUER and OIDC_%s_CLIENT_ID are both required",
            key, key.upper(), key.upper(),
        )
        return None

    mobile_ids = tuple(
        p.strip() for p in _env(key, "MOBILE_CLIENT_ID").split(",") if p.strip()
    )

    scopes = _env(key, "SCOPES") or DEFAULT_SCOPES
    # The native apps need a refresh token, which requires `offline_access`.
    # Since Authentik 2024.2 that scope must be mapped explicitly, and some
    # other providers reject an unknown scope outright — so it is the server,
    # not the app, that decides. Overridable per provider without a code change.
    mobile_scopes = _env(key, "MOBILE_SCOPES")
    if not mobile_scopes:
        wanted = scopes.split()
        if "offline_access" not in wanted:
            wanted.append("offline_access")
        mobile_scopes = " ".join(wanted)

    return OIDCProvider(
        key=key,
        name=_env(key, "NAME") or key.capitalize(),
        issuer=issuer,
        client_id=client_id,
        client_secret=_env(key, "CLIENT_SECRET"),
        scopes=scopes,
        mobile_scopes=mobile_scopes,
        redirect_uri=_env(key, "REDIRECT_URI"),
        mobile_client_ids=mobile_ids,
        mobile_issuer=_env(key, "MOBILE_ISSUER"),
        allow_signup=_env_bool(key, "ALLOW_SIGNUP"),
        allowed_domains=_env_list(key, "ALLOWED_DOMAINS"),
        link_by_email=_env_bool(key, "LINK_BY_EMAIL"),
        username_claim=_env(key, "USERNAME_CLAIM") or "preferred_username",
        icon=_env(key, "ICON"),
    )


def load_providers() -> dict:
    """Parse the environment fresh. Prefer :func:`get_providers` (memoised)."""
    keys = [
        k.strip().lower()
        for k in os.environ.get("OIDC_PROVIDERS", "").split(",")
        if k.strip()
    ]
    providers = {}
    for key in keys:
        if key in providers:
            continue
        provider = _build_provider(key)
        if provider is not None:
            providers[key] = provider
    return providers


_cache: Optional[dict] = None


def get_providers(refresh: bool = False) -> dict:
    """All usable providers, keyed by provider key. Memoised."""
    global _cache
    if _cache is None or refresh:
        _cache = load_providers()
    return _cache


def get_provider(key: str) -> Optional[OIDCProvider]:
    return get_providers().get((key or "").strip().lower())


def is_enabled() -> bool:
    return bool(get_providers())


def reset_cache() -> None:
    """Drop the memoised providers — used by tests after changing the env."""
    global _cache
    _cache = None


def _normalise_issuer(issuer: str) -> str:
    return (issuer or "").rstrip("/")


def accepted_issuers(provider: OIDCProvider) -> set:
    """Issuer values we accept in an `iss` claim.

    Authentik's issuer ends in a slash while some tooling drops it, so accept
    both spellings. A second Authentik *application* for the mobile client has
    its own issuer URL, hence ``mobile_issuer``.
    """
    out = set()
    for raw in (provider.issuer, provider.mobile_issuer):
        if not raw:
            continue
        bare = _normalise_issuer(raw)
        out.add(bare)
        out.add(bare + "/")
    return out


def accepted_audiences(provider: OIDCProvider) -> set:
    """Client ids that may appear in an `aud` claim for this provider."""
    out = {provider.client_id}
    out.update(provider.mobile_client_ids)
    return {a for a in out if a}
