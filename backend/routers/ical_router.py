import ipaddress
import logging
import socket
from datetime import datetime, timezone
from typing import Optional
from urllib.parse import urljoin, urlparse

import requests as http_requests
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

import models
from auth import get_current_user
from caldav_client import _parse_ics
from database import get_db

logger = logging.getLogger(__name__)
router = APIRouter()


class SubscriptionCreate(BaseModel):
    name: str
    url: str
    color: str = "#46bdc6"
    refresh_minutes: int = 60


class SubscriptionUpdate(BaseModel):
    name: Optional[str] = None
    url: Optional[str] = None
    color: Optional[str] = None
    enabled: Optional[bool] = None
    refresh_minutes: Optional[int] = None
    reminders_enabled: Optional[bool] = None


def _sub_dict(sub: models.ICalSubscription) -> dict:
    return {
        "id": sub.id,
        "name": sub.name,
        "url": sub.url,
        "color": sub.color,
        "enabled": sub.enabled,
        "reminders_enabled": bool(sub.reminders_enabled),
        "refresh_minutes": sub.refresh_minutes,
        "last_fetched": sub.last_fetched.isoformat() if sub.last_fetched else None,
    }


_MAX_ICS_BYTES = 5 * 1024 * 1024
_MAX_REDIRECTS = 5


def _host_is_public(host: str) -> bool:
    """False if the host resolves to any private/loopback/link-local address."""
    try:
        infos = socket.getaddrinfo(host, None)
    except socket.gaierror:
        return False
    for info in infos:
        try:
            ip = ipaddress.ip_address(info[4][0])
        except ValueError:
            return False
        if (ip.is_private or ip.is_loopback or ip.is_link_local
                or ip.is_reserved or ip.is_multicast or ip.is_unspecified):
            return False
    return True


def _validate_public_url(url: str) -> None:
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise ValueError("Nur http(s)-URLs sind erlaubt.")
    if not parsed.hostname:
        raise ValueError("Ungültige URL.")
    if not _host_is_public(parsed.hostname):
        raise ValueError("Interne/private Adressen sind nicht erlaubt.")


def _fetch_ics(url: str) -> str:
    """Download .ics content, blocking SSRF to internal/private hosts.

    Redirects are followed manually so every hop is re-validated (a public URL
    can otherwise 30x-redirect into the internal network). Response size is
    capped. (Residual risk: DNS rebinding between check and connect.)
    """
    if url.startswith("webcal://"):
        url = "https://" + url[len("webcal://"):]
    try:
        for _ in range(_MAX_REDIRECTS + 1):
            _validate_public_url(url)
            resp = http_requests.get(url, timeout=30, allow_redirects=False, stream=True)
            if resp.is_redirect and resp.headers.get("location"):
                url = urljoin(url, resp.headers["location"])
                resp.close()
                continue
            resp.raise_for_status()
            resp.encoding = "utf-8"
            chunks, total = [], 0
            for chunk in resp.iter_content(8192, decode_unicode=True):
                if not chunk:
                    continue
                chunks.append(chunk)
                total += len(chunk)
                if total > _MAX_ICS_BYTES:
                    resp.close()
                    raise ValueError("Datei zu groß (max. 5 MB).")
            return "".join(chunks)
        raise ValueError("Zu viele Weiterleitungen.")
    except http_requests.RequestException as e:
        raise ValueError(f"Fehler beim Abrufen der URL: {e}")


def _refresh_if_needed(sub: models.ICalSubscription, db: Session, force: bool = False):
    """Refresh cached ICS data if stale or forced."""
    now = datetime.now(timezone.utc)
    if (
        not force
        and sub.cached_ics
        and sub.last_fetched
        and (now - sub.last_fetched.replace(tzinfo=timezone.utc)).total_seconds()
        < sub.refresh_minutes * 60
    ):
        return  # Cache still fresh

    try:
        sub.cached_ics = _fetch_ics(sub.url)
        sub.last_fetched = now
        db.commit()
    except ValueError:
        logger.warning("Could not refresh iCal subscription %s", sub.id)
        if not sub.cached_ics:
            raise


def get_events_for_subscription(
    sub: models.ICalSubscription, start_dt: datetime, end_dt: datetime, db: Session = None
) -> list:
    """Parse cached ICS and filter events within the date range, applying local overrides."""
    if not sub.cached_ics:
        return []

    # Load overrides for this subscription
    overrides = {}
    if db:
        for ov in (
            db.query(models.ICalOverride)
            .filter(models.ICalOverride.subscription_id == sub.id)
            .all()
        ):
            overrides[ov.event_uid] = ov

    all_events = _parse_ics(sub.cached_ics, f"ical://{sub.id}")
    filtered = []
    for ev in all_events:
        uid = ev["id"]

        # Skip hidden (deleted) events
        ov = overrides.get(uid)
        if ov and ov.hidden:
            continue

        # Apply overrides
        if ov:
            if ov.title is not None:
                ev["title"] = ov.title
            if ov.start is not None:
                ev["start"] = ov.start
            if ov.end is not None:
                ev["end"] = ov.end
            if ov.all_day is not None:
                ev["allDay"] = ov.all_day
            if ov.location is not None:
                ev["location"] = ov.location
            if ov.description is not None:
                ev["description"] = ov.description
            if ov.color is not None:
                ev["color"] = ov.color

        try:
            ev_start = ev["start"]
            ev_end = ev["end"]
            if ev["allDay"]:
                if ev_end > start_dt.strftime("%Y-%m-%d") and ev_start < end_dt.strftime("%Y-%m-%d"):
                    filtered.append(ev)
            else:
                ev_s = datetime.fromisoformat(ev_start.replace("Z", "+00:00"))
                ev_e = datetime.fromisoformat(ev_end.replace("Z", "+00:00"))
                if ev_s.tzinfo is None:
                    ev_s = ev_s.replace(tzinfo=timezone.utc)
                if ev_e.tzinfo is None:
                    ev_e = ev_e.replace(tzinfo=timezone.utc)
                if ev_e > start_dt and ev_s < end_dt:
                    filtered.append(ev)
        except Exception:
            filtered.append(ev)

    for ev in filtered:
        ev["calendar_id"] = f"ical-{sub.id}"
        ev["calendar_name"] = sub.name
        ev["calendarColor"] = sub.color
        ev["source"] = "ical"

    return filtered


# ── Subscription CRUD ─────────────────────────────────────

@router.get("/subscriptions")
def list_subscriptions(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    subs = (
        db.query(models.ICalSubscription)
        .filter(models.ICalSubscription.user_id == current_user.id)
        .all()
    )
    return [_sub_dict(s) for s in subs]


@router.post("/subscriptions")
def create_subscription(
    data: SubscriptionCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    # Validate URL by fetching it
    try:
        ics_content = _fetch_ics(data.url)
    except ValueError as e:
        raise HTTPException(400, str(e))

    sub = models.ICalSubscription(
        user_id=current_user.id,
        name=data.name,
        url=data.url,
        color=data.color,
        refresh_minutes=data.refresh_minutes,
        cached_ics=ics_content,
        last_fetched=datetime.now(timezone.utc),
    )
    db.add(sub)
    db.commit()
    db.refresh(sub)
    return _sub_dict(sub)


@router.put("/subscriptions/{sub_id}")
def update_subscription(
    sub_id: int,
    data: SubscriptionUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    sub = (
        db.query(models.ICalSubscription)
        .filter(
            models.ICalSubscription.id == sub_id,
            models.ICalSubscription.user_id == current_user.id,
        )
        .first()
    )
    if not sub:
        raise HTTPException(404, "Subscription not found")
    if data.name is not None:
        sub.name = data.name
    if data.url is not None:
        sub.url = data.url
    if data.color is not None:
        sub.color = data.color
    if data.enabled is not None:
        sub.enabled = data.enabled
    if data.refresh_minutes is not None:
        sub.refresh_minutes = data.refresh_minutes
    if data.reminders_enabled is not None:
        sub.reminders_enabled = data.reminders_enabled
    db.commit()
    return {"ok": True}


@router.delete("/subscriptions/{sub_id}")
def delete_subscription(
    sub_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    sub = (
        db.query(models.ICalSubscription)
        .filter(
            models.ICalSubscription.id == sub_id,
            models.ICalSubscription.user_id == current_user.id,
        )
        .first()
    )
    if not sub:
        raise HTTPException(404, "Subscription not found")
    db.delete(sub)
    db.commit()
    return {"ok": True}


@router.post("/subscriptions/{sub_id}/refresh")
def refresh_subscription(
    sub_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    sub = (
        db.query(models.ICalSubscription)
        .filter(
            models.ICalSubscription.id == sub_id,
            models.ICalSubscription.user_id == current_user.id,
        )
        .first()
    )
    if not sub:
        raise HTTPException(404, "Subscription not found")
    try:
        _refresh_if_needed(sub, db, force=True)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return _sub_dict(sub)


# ── Event overrides (edit/delete iCal events locally) ─────

class ICalEventUpdate(BaseModel):
    title: Optional[str] = None
    start: Optional[str] = None
    end: Optional[str] = None
    allDay: Optional[bool] = None
    location: Optional[str] = None
    description: Optional[str] = None
    color: Optional[str] = None


@router.put("/events/{sub_id}/{event_uid}")
def update_ical_event(
    sub_id: int,
    event_uid: str,
    data: ICalEventUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    sub = (
        db.query(models.ICalSubscription)
        .filter(
            models.ICalSubscription.id == sub_id,
            models.ICalSubscription.user_id == current_user.id,
        )
        .first()
    )
    if not sub:
        raise HTTPException(404, "Subscription not found")

    ov = (
        db.query(models.ICalOverride)
        .filter(
            models.ICalOverride.subscription_id == sub_id,
            models.ICalOverride.event_uid == event_uid,
        )
        .first()
    )
    if not ov:
        ov = models.ICalOverride(subscription_id=sub_id, event_uid=event_uid)
        db.add(ov)

    if data.title is not None:
        ov.title = data.title
    if data.start is not None:
        ov.start = data.start
    if data.end is not None:
        ov.end = data.end
    if data.allDay is not None:
        ov.all_day = data.allDay
    if data.location is not None:
        ov.location = data.location
    if data.description is not None:
        ov.description = data.description
    if data.color is not None:
        ov.color = data.color
    db.commit()
    return {"ok": True}


@router.delete("/events/{sub_id}/{event_uid}")
def delete_ical_event(
    sub_id: int,
    event_uid: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    sub = (
        db.query(models.ICalSubscription)
        .filter(
            models.ICalSubscription.id == sub_id,
            models.ICalSubscription.user_id == current_user.id,
        )
        .first()
    )
    if not sub:
        raise HTTPException(404, "Subscription not found")

    ov = (
        db.query(models.ICalOverride)
        .filter(
            models.ICalOverride.subscription_id == sub_id,
            models.ICalOverride.event_uid == event_uid,
        )
        .first()
    )
    if not ov:
        ov = models.ICalOverride(subscription_id=sub_id, event_uid=event_uid, hidden=True)
        db.add(ov)
    else:
        ov.hidden = True
    db.commit()
    return {"ok": True}
