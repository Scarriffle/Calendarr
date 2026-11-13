"""Shared OAuth flow-state: a signed, cookie-bound state plus PKCE.

Lifted out of ``routers/oidc_router.py`` so the Google flow can use the same
mechanism instead of its own. Two properties matter:

* The state travelling in the URL is only an opaque id. The browser holds the
  signed payload in an HttpOnly cookie, so a callback that someone else
  fabricated cannot satisfy the check (double submit).
* ``typ`` namespaces the token. A cookie minted for one flow must never be
  accepted by another, which is why every caller passes its own value.
"""

from __future__ import annotations

import base64
import hashlib
import secrets
from datetime import datetime, timedelta
from typing import Optional

from fastapi import Request
from jose import JWTError, jwt

from auth import ALGORITHM, SECRET_KEY
from dav_util import public_base


def cookie_kwargs(request: Request, path: str, max_age: int) -> dict:
    return {
        "httponly": True,
        # Lax, NOT Strict: the cookie has to survive the provider's top-level
        # cross-site redirect back to the callback. With Strict the browser
        # drops it and every single login fails with state_mismatch.
        "samesite": "lax",
        "secure": public_base(request).startswith("https"),
        "path": path,
        "max_age": max_age,
    }


def encode_state(payload: dict, typ: str, ttl: int) -> str:
    data = dict(payload)
    data["typ"] = typ
    data["exp"] = datetime.utcnow() + timedelta(seconds=ttl)
    return jwt.encode(data, SECRET_KEY, algorithm=ALGORITHM)


def decode_state(token: str, typ: str) -> Optional[dict]:
    """Decode and verify, or None. Rejects a token minted for another flow."""
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        return None
    if payload.get("typ") != typ:
        return None
    return payload


def pkce_pair() -> tuple:
    """(verifier, S256 challenge)."""
    verifier = secrets.token_urlsafe(64)
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    challenge = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
    return verifier, challenge
