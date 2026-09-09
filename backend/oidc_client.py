"""OpenID Connect protocol client: discovery, JWKS, token exchange, validation.

HTTP goes through ``requests`` (already a dependency, and what the Google and
Home Assistant routers use); everything cryptographic goes through Authlib.
We deliberately use only ``authlib.jose`` and not
``authlib.integrations.starlette_client``, which would drag in
``SessionMiddleware``/``itsdangerous`` and a second authentication surface
alongside the existing bearer JWT.

Unlike ``homeassistant_router``, every request here verifies TLS.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import logging
import time
from typing import Optional

import requests as http_requests
from authlib.jose import JsonWebKey, JsonWebToken
from authlib.oidc.core import CodeIDToken

from oidc_config import OIDCProvider, accepted_issuers

logger = logging.getLogger(__name__)

HTTP_TIMEOUT = 10
DISCOVERY_TTL = 3600
JWKS_TTL = 3600
# Never refetch the JWKS more than once a minute, so an unknown `kid` cannot be
# used to hammer the identity provider.
JWKS_MIN_REFETCH = 60

# Signature algorithms we accept. This allow-list is the single most important
# line in this module: the module-level ``authlib.jose.jwt`` helper honours
# whatever `alg` the token header declares, which is the classic "alg: none" /
# algorithm-confusion hole. Asymmetric only — an HMAC algorithm here would let
# anyone who can read the (public) JWKS mint their own tokens.
SIGNING_ALGORITHMS = ["RS256", "RS384", "RS512", "PS256", "PS384", "PS512",
                      "ES256", "ES384", "ES512"]

_JWT = JsonWebToken(SIGNING_ALGORITHMS)

_AT_HASH_DIGESTS = {"256": hashlib.sha256, "384": hashlib.sha384, "512": hashlib.sha512}


class OIDCError(Exception):
    """Protocol-level failure. ``slug`` is a stable, user-safe error code."""

    def __init__(self, slug: str, detail: str = ""):
        super().__init__(detail or slug)
        self.slug = slug
        self.detail = detail or slug


# ── caches ───────────────────────────────────────────────────────────────────
_discovery_cache: dict = {}   # provider key -> (fetched_at, document)
_jwks_cache: dict = {}        # provider key -> (fetched_at, key_set)


def reset_cache() -> None:
    """Drop discovery and JWKS caches — used by tests."""
    _discovery_cache.clear()
    _jwks_cache.clear()


def _http_get(url: str, timeout: int = HTTP_TIMEOUT) -> dict:
    """The single network seam for GETs, so tests can stub one function.

    Transport failures (DNS, timeout, TLS) must surface as OIDCError like any
    other protocol failure — otherwise an unreachable provider turns into an
    HTTP 500 instead of a clean "try again" on the login screen.
    """
    try:
        resp = http_requests.get(url, timeout=timeout)
    except http_requests.RequestException as e:
        raise OIDCError("oidc_provider_unreachable", f"GET {url}: {e}")
    if resp.status_code != 200:
        raise OIDCError("oidc_discovery_failed", f"GET {url} -> {resp.status_code}")
    try:
        return resp.json()
    except ValueError:
        raise OIDCError("oidc_discovery_failed", f"GET {url}: response is not JSON")


def discovery_url(provider: OIDCProvider) -> str:
    return provider.issuer.rstrip("/") + "/.well-known/openid-configuration"


def discover(provider: OIDCProvider, force: bool = False) -> dict:
    """Fetch and cache the provider's OpenID configuration document."""
    cached = _discovery_cache.get(provider.key)
    if cached and not force and (time.time() - cached[0]) < DISCOVERY_TTL:
        return cached[1]

    doc = _http_get(discovery_url(provider))

    # Mix-up defence: the document must claim the issuer we configured.
    doc_issuer = (doc.get("issuer") or "").rstrip("/")
    if doc_issuer and doc_issuer != provider.issuer.rstrip("/"):
        raise OIDCError(
            "oidc_issuer_mismatch",
            f"discovery issuer {doc_issuer!r} != configured {provider.issuer!r}",
        )

    _discovery_cache[provider.key] = (time.time(), doc)
    return doc


def _endpoint(provider: OIDCProvider, name: str) -> str:
    url = discover(provider).get(name)
    if not url:
        raise OIDCError("oidc_discovery_incomplete", f"{name} missing from discovery")
    return url


def authorization_endpoint(provider: OIDCProvider) -> str:
    return _endpoint(provider, "authorization_endpoint")


def token_endpoint(provider: OIDCProvider) -> str:
    return _endpoint(provider, "token_endpoint")


def jwks_key_set(provider: OIDCProvider, force: bool = False):
    """Fetch and cache the provider's JWKS as an Authlib key set."""
    cached = _jwks_cache.get(provider.key)
    now = time.time()
    if cached and not force and (now - cached[0]) < JWKS_TTL:
        return cached[1]
    if cached and force and (now - cached[0]) < JWKS_MIN_REFETCH:
        # Rate-limit forced refetches so unknown kids can't be used as a DoS.
        return cached[1]

    jwks = _http_get(_endpoint(provider, "jwks_uri"))
    key_set = JsonWebKey.import_key_set(jwks)
    _jwks_cache[provider.key] = (now, key_set)
    return key_set


def exchange_code(provider: OIDCProvider, code: str, redirect_uri: str,
                  code_verifier: str) -> dict:
    """Trade an authorization code for tokens (always with PKCE)."""
    data = {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": redirect_uri,
        "client_id": provider.client_id,
        "code_verifier": code_verifier,
    }
    # Confidential client -> client_secret_post. Public client -> PKCE only.
    if provider.client_secret:
        data["client_secret"] = provider.client_secret

    try:
        resp = http_requests.post(
            token_endpoint(provider), data=data, timeout=HTTP_TIMEOUT,
            headers={"Accept": "application/json"},
        )
    except http_requests.RequestException as e:
        raise OIDCError("oidc_provider_unreachable", f"token endpoint: {e}")
    if resp.status_code != 200:
        logger.warning("OIDC token exchange failed (%s): %s",
                       resp.status_code, resp.text[:300])
        raise OIDCError("oidc_token_exchange_failed")
    try:
        tokens = resp.json()
    except ValueError:
        raise OIDCError("oidc_token_exchange_failed", "token response is not JSON")
    if not tokens.get("id_token"):
        raise OIDCError("oidc_no_id_token")
    return tokens


def fetch_userinfo(provider: OIDCProvider, access_token: str) -> dict:
    """Userinfo lookup — only used when the ID token carries no email."""
    try:
        url = _endpoint(provider, "userinfo_endpoint")
        resp = http_requests.get(
            url, timeout=HTTP_TIMEOUT,
            headers={"Authorization": f"Bearer {access_token}"},
        )
        if resp.status_code != 200:
            return {}
        return resp.json()
    except Exception:
        return {}


def _verify_at_hash(claims, access_token: str) -> None:
    """Bind the ID token to its access token (OIDC core 3.1.3.6)."""
    at_hash = claims.get("at_hash")
    if not at_hash or not access_token:
        return
    alg = (claims.header or {}).get("alg", "")
    digest_fn = _AT_HASH_DIGESTS.get(alg[-3:])
    if digest_fn is None:
        return
    digest = digest_fn(access_token.encode("ascii")).digest()
    expected = base64.urlsafe_b64encode(digest[: len(digest) // 2]).rstrip(b"=").decode()
    if not hmac.compare_digest(expected, at_hash):
        raise OIDCError("oidc_at_hash_mismatch")


def validate_id_token(provider: OIDCProvider, id_token: str, *,
                      expected_audience: str,
                      nonce: Optional[str] = None,
                      access_token: Optional[str] = None) -> dict:
    """Verify an ID token's signature and claims. Returns the claim dict.

    Raises :class:`OIDCError` with a stable slug on any failure.
    """
    issuers = accepted_issuers(provider)

    def _decode(force_jwks: bool):
        key_set = jwks_key_set(provider, force=force_jwks)
        return _JWT.decode(
            id_token, key_set, claims_cls=CodeIDToken,
            claims_options={
                "iss": {"essential": True, "values": sorted(issuers)},
                "aud": {"essential": True, "values": [expected_audience]},
                "exp": {"essential": True},
                "sub": {"essential": True},
            },
            claims_params={"nonce": nonce, "client_id": expected_audience,
                           "access_token": access_token},
        )

    try:
        claims = _decode(force_jwks=False)
    except OIDCError:
        raise
    except Exception as first_error:
        # The provider may have rotated its signing key since we cached the
        # JWKS. One rate-limited refetch avoids needing a restart.
        try:
            claims = _decode(force_jwks=True)
        except Exception:
            logger.info("OIDC id_token signature/decode failed: %s", first_error)
            raise OIDCError("oidc_invalid_token")

    try:
        claims.validate(leeway=60)
    except Exception as e:
        logger.info("OIDC id_token claim validation failed: %s", e)
        raise OIDCError("oidc_invalid_token")

    # Explicit re-checks. Authlib already covers these, but stating them here
    # makes the security contract readable and testable without depending on
    # Authlib's internal claim-validation details.
    if (claims.get("iss") or "").rstrip("/") not in {i.rstrip("/") for i in issuers}:
        raise OIDCError("oidc_bad_issuer")

    aud = claims.get("aud")
    aud_list = aud if isinstance(aud, list) else [aud]
    if expected_audience not in aud_list:
        raise OIDCError("oidc_bad_audience")

    # With a multi-valued `aud`, `azp` must name the client the token is for.
    if len(aud_list) > 1:
        azp = claims.get("azp")
        if azp and azp != expected_audience:
            raise OIDCError("oidc_bad_azp")

    if not claims.get("sub"):
        raise OIDCError("oidc_no_subject")

    if nonce is not None and claims.get("nonce") != nonce:
        raise OIDCError("oidc_nonce_mismatch")

    if access_token:
        _verify_at_hash(claims, access_token)

    return dict(claims)
