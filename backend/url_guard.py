"""Where the server is allowed to connect when a user names the target.

Lifted out of ``routers/ical_router.py`` so Home Assistant and CalDAV get the
same treatment — both accept a URL from any logged-in user (not just admins)
and connect to it, which is a server-side request forgery surface.

Two levels, because the features differ:

* :func:`validate_public_url` — for iCal subscriptions. A subscription points
  at a public feed, so everything internal is refused.
* :func:`validate_reachable_url` — for Home Assistant and CalDAV. Reaching a
  box on the home LAN *is* the feature, so private ranges stay allowed; what
  is refused is loopback and the link-local block that holds the cloud
  metadata service at 169.254.169.254.

shortcut: both resolve the name and then hand the URL to requests, which
resolves it again — a name whose answer changes in between (DNS rebinding)
slips through. Upgrade by pinning the resolved address into the connection.
"""

from __future__ import annotations

import ipaddress
import socket
from urllib.parse import urlparse


def _resolved_ips(host: str):
    """Every address the name resolves to, or None when it does not resolve."""
    try:
        infos = socket.getaddrinfo(host, None)
    except socket.gaierror:
        return None
    out = []
    for info in infos:
        try:
            out.append(ipaddress.ip_address(info[4][0]))
        except ValueError:
            return None
    return out or None


def host_is_public(host: str) -> bool:
    """False if the host resolves to any private/loopback/link-local address."""
    ips = _resolved_ips(host)
    if ips is None:
        return False
    for ip in ips:
        if (ip.is_private or ip.is_loopback or ip.is_link_local
                or ip.is_reserved or ip.is_multicast or ip.is_unspecified):
            return False
    return True


def host_is_reachable(host: str) -> bool:
    """False only for the targets no feature legitimately needs.

    Private ranges stay allowed — a Home Assistant or CalDAV server on the
    LAN is the normal case. Loopback would reach services running on the
    Calendarr host itself, and link-local covers the cloud metadata endpoint.
    """
    ips = _resolved_ips(host)
    if ips is None:
        return False
    for ip in ips:
        if (ip.is_loopback or ip.is_link_local
                or ip.is_reserved or ip.is_multicast or ip.is_unspecified):
            return False
    return True


def _parse(url: str):
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise ValueError("Nur http(s)-URLs sind erlaubt.")
    if not parsed.hostname:
        raise ValueError("Ungültige URL.")
    return parsed


def validate_public_url(url: str) -> None:
    """Raise ValueError unless the URL points somewhere on the public internet."""
    parsed = _parse(url)
    if not host_is_public(parsed.hostname):
        raise ValueError("Interne/private Adressen sind nicht erlaubt.")


def validate_reachable_url(url: str) -> None:
    """Raise ValueError for loopback/link-local/reserved targets. LAN is fine."""
    parsed = _parse(url)
    if not host_is_reachable(parsed.hostname):
        raise ValueError(
            "Diese Adresse ist nicht erlaubt (localhost bzw. interne "
            "Metadaten-Adressen)."
        )
