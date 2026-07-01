"""Shared helpers for CalDAV publishing of local calendars.

Publishing is opt-in per calendar: a published calendar gets a secret
``dav_token`` and is reachable as a two-way CalDAV collection at
``/dav/{token}/``. ``dav_ctag`` changes on every event write so clients detect
changes; each event carries an ``etag`` that changes on write. Rotating the
token revokes existing subscriptions.
"""

from __future__ import annotations

import os
import secrets
import uuid


def new_token() -> str:
    """A URL-safe, unguessable token used as the CalDAV collection path."""
    return secrets.token_urlsafe(24)


def new_tag() -> str:
    """A fresh ctag/etag value."""
    return uuid.uuid4().hex


def bump_dav(cal, event=None) -> None:
    """Mark a calendar (and optionally an event) as changed for CalDAV clients.

    Safe to call unconditionally on every local-event write — it only refreshes
    opaque change tags, so unpublished calendars are unaffected.
    """
    if cal is not None:
        cal.dav_ctag = new_tag()
    if event is not None:
        event.etag = new_tag()


def public_base(request) -> str:
    """Public origin (scheme://host) as clients actually reach us.

    Behind a reverse proxy (e.g. Nginx Proxy Manager) the app only sees
    ``http://…:8080`` internally, so honour ``X-Forwarded-Proto/-Host`` and an
    optional ``PUBLIC_BASE_URL`` override so published URLs are the real https
    ones.
    """
    env = os.environ.get("PUBLIC_BASE_URL")
    if env:
        return env.rstrip("/")
    h = request.headers
    proto = (h.get("x-forwarded-proto") or request.url.scheme or "http").split(",")[0].strip()
    host = (h.get("x-forwarded-host") or h.get("host") or request.url.netloc).split(",")[0].strip()
    return f"{proto}://{host}"


def caldav_url(request, token: str) -> str:
    """Absolute per-calendar CalDAV collection URL (secret token, no login)."""
    return f"{public_base(request)}/dav/{token}/"


def caldav_login_url(request) -> str:
    """Absolute discovery URL for username/password (Basic Auth) CalDAV access."""
    return f"{public_base(request)}/caldav/"
