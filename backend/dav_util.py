"""Shared helpers for CalDAV publishing of local calendars.

Publishing is opt-in per calendar: a published calendar gets a secret
``dav_token`` and is reachable as a two-way CalDAV collection at
``/dav/{token}/``. ``dav_ctag`` changes on every event write so clients detect
changes; each event carries an ``etag`` that changes on write. Rotating the
token revokes existing subscriptions.
"""

from __future__ import annotations

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


def caldav_url(request, token: str) -> str:
    """Absolute CalDAV collection URL for a token, based on the request origin."""
    base = str(request.base_url).rstrip("/")
    return f"{base}/dav/{token}/"
