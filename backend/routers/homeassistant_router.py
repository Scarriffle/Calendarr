import json
import logging
import secrets
import ssl
import time
from datetime import datetime, timezone
from typing import Optional
from urllib.parse import urlencode

import requests as http_requests
import websocket as ws_client
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import RedirectResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session

import models
from auth import get_current_user
from database import get_db

logger = logging.getLogger(__name__)
router = APIRouter()

HA_DEFAULT_COLOR = "#03a9f4"

# In-memory store for pending OAuth states (short-lived, ~10 min TTL)
_pending_oauth: dict[str, dict] = {}


def _cleanup_pending():
    now = time.time()
    for k in [k for k, v in _pending_oauth.items() if v["expires"] < now]:
        _pending_oauth.pop(k, None)


# ── Auth helpers ──────────────────────────────────────────

def _ha_refresh(url: str, refresh_token: str, client_id: str) -> tuple:
    """Refresh grant → (access_token, expires_in)"""
    resp = http_requests.post(
        f"{url.rstrip('/')}/auth/token",
        data={
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "client_id": client_id,
        },
        timeout=10,
        verify=False,
    )
    resp.raise_for_status()
    data = resp.json()
    return data["access_token"], data.get("expires_in", 1800)


def _get_valid_token(account: models.HomeAssistantAccount, db: Session) -> str:
    """Return a valid access token, refreshing if necessary."""
    if account.auth_method != "oauth":
        return account.token  # Long-Lived Token läuft nicht ab
    now = datetime.now(timezone.utc)
    if account.token_expiry and account.token_expiry.replace(tzinfo=timezone.utc) > now:
        return account.token
    # Needs refresh
    try:
        access_token, expires_in = _ha_refresh(
            account.url, account.refresh_token, account.client_id or ""
        )
    except Exception as exc:
        logger.error("HA token refresh failed for %s: %s", account.name, exc)
        raise HTTPException(401, "Home Assistant Token abgelaufen, bitte Konto neu verbinden")
    account.token = access_token
    account.token_expiry = datetime.fromtimestamp(now.timestamp() + expires_in, tz=timezone.utc)
    db.commit()
    return access_token


# ── HA API helpers ────────────────────────────────────────

def _ha_get_calendars(url: str, token: str) -> list:
    try:
        resp = http_requests.get(
            f"{url.rstrip('/')}/api/calendars",
            headers={"Authorization": f"Bearer {token}"},
            timeout=10,
            verify=False,
        )
        resp.raise_for_status()
        return resp.json()
    except http_requests.exceptions.ConnectionError:
        raise HTTPException(503, "Home Assistant nicht erreichbar")
    except http_requests.exceptions.Timeout:
        raise HTTPException(503, "Home Assistant antwortet nicht (Timeout)")
    except http_requests.exceptions.HTTPError as e:
        if e.response is not None and e.response.status_code == 401:
            raise HTTPException(400, "Ungültiger Access Token")
        raise HTTPException(502, f"Home Assistant Fehler: {e}")


def _ha_get_events(url: str, token: str, entity_id: str, start_dt: datetime, end_dt: datetime) -> list:
    try:
        resp = http_requests.get(
            f"{url.rstrip('/')}/api/calendars/{entity_id}",
            headers={"Authorization": f"Bearer {token}"},
            params={"start": start_dt.isoformat(), "end": end_dt.isoformat()},
            timeout=15,
            verify=False,
        )
        resp.raise_for_status()
        return resp.json()
    except http_requests.exceptions.ConnectionError:
        raise http_requests.exceptions.ConnectionError(f"HA nicht erreichbar für {entity_id}")
    except http_requests.exceptions.Timeout:
        raise http_requests.exceptions.Timeout(f"HA Timeout für {entity_id}")


def _ha_format_dt(s: str) -> str:
    """Convert ISO datetime to HA format with timezone, no milliseconds.

    HA's cv.datetime accepts ISO 8601. Keep the timezone offset so HA
    interprets the time correctly regardless of HA's local timezone.
    """
    # Frontend sends "2026-05-07T15:00:00.000Z"; normalize Z to +00:00
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        # Strip fractional seconds if fromisoformat can't handle them
        import re
        s2 = re.sub(r"\.\d+", "", s)
        dt = datetime.fromisoformat(s2)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.isoformat(timespec="seconds")


def _ha_build_event_body(entity_id: str, data: dict) -> dict:
    """Build a service-call body for create_event / update_event."""
    body = {"entity_id": entity_id}
    if data.get("title"):
        body["summary"] = data["title"]
    if data.get("description"):
        body["description"] = data["description"]
    if data.get("location"):
        body["location"] = data["location"]
    if data.get("start") and data.get("end"):
        if data.get("allDay"):
            body["start_date"] = data["start"][:10]
            body["end_date"] = data["end"][:10]
        else:
            body["start_date_time"] = _ha_format_dt(data["start"])
            body["end_date_time"] = _ha_format_dt(data["end"])
    return body


def _ha_ws_call(url: str, token: str, command: dict) -> dict:
    """Send a single WebSocket command to HA and return the result.

    Used for calendar/event/delete and calendar/event/update which are
    only exposed via WebSocket, not as service calls.
    """
    # Convert http(s):// → ws(s)://
    if url.startswith("https://"):
        ws_url = "wss://" + url[len("https://"):].rstrip("/") + "/api/websocket"
        sslopt = {"cert_reqs": ssl.CERT_NONE}
    elif url.startswith("http://"):
        ws_url = "ws://" + url[len("http://"):].rstrip("/") + "/api/websocket"
        sslopt = None
    else:
        raise Exception(f"Ungültige HA-URL: {url}")

    sock = ws_client.create_connection(ws_url, timeout=15, sslopt=sslopt)
    try:
        # 1. auth_required
        msg = json.loads(sock.recv())
        if msg.get("type") != "auth_required":
            raise Exception(f"Unerwartete WS-Antwort: {msg}")
        # 2. send auth
        sock.send(json.dumps({"type": "auth", "access_token": token}))
        msg = json.loads(sock.recv())
        if msg.get("type") != "auth_ok":
            raise Exception(f"WS Auth fehlgeschlagen: {msg.get('message', msg)}")
        # 3. send command
        cmd = {"id": 1, **command}
        logger.info("HA WS command: %s", cmd)
        sock.send(json.dumps(cmd))
        # 4. receive result (might receive other messages first, ignore them)
        for _ in range(10):
            msg = json.loads(sock.recv())
            if msg.get("id") == 1:
                if msg.get("success"):
                    return msg.get("result", {})
                err = msg.get("error", {})
                raise Exception(f"{err.get('code', 'error')}: {err.get('message', 'Unbekannter Fehler')}")
        raise Exception("Keine Antwort von HA WebSocket")
    finally:
        try:
            sock.close()
        except Exception:
            pass


def _ha_ws_event_payload(data: dict) -> dict:
    """Build the 'event' payload for calendar/event/create|update WS commands."""
    payload = {}
    if data.get("title"):
        payload["summary"] = data["title"]
    if data.get("description"):
        payload["description"] = data["description"]
    if data.get("location"):
        payload["location"] = data["location"]
    if data.get("start") and data.get("end"):
        if data.get("allDay"):
            payload["dtstart"] = data["start"][:10]
            payload["dtend"] = data["end"][:10]
        else:
            payload["dtstart"] = _ha_format_dt(data["start"])
            payload["dtend"] = _ha_format_dt(data["end"])
    return payload


def _ha_create_event(url: str, token: str, entity_id: str, data: dict) -> dict:
    """Create a new event. Tries WebSocket command first, falls back to service call."""
    # Try WebSocket calendar/event/create
    try:
        return _ha_ws_call(url, token, {
            "type": "calendar/event/create",
            "entity_id": entity_id,
            "event": _ha_ws_event_payload(data),
        })
    except Exception as exc:
        logger.info("HA WS create failed (%s), falling back to service call", exc)

    # Fallback: service call
    base = url.rstrip("/")
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    body = _ha_build_event_body(entity_id, data)
    logger.info("HA create_event body: %s", body)
    resp = http_requests.post(
        f"{base}/api/services/calendar/create_event",
        headers=headers, json=body, timeout=15, verify=False,
    )
    if not resp.ok:
        try:
            detail = resp.json().get("message", resp.text[:500])
        except Exception:
            detail = resp.text[:500] if resp.text else f"HTTP {resp.status_code}"
        raise Exception(f"HA create_event ({resp.status_code}): {detail}")
    return {}


def _ha_update_event(url: str, token: str, entity_id: str, uid: str, data: dict):
    """Update an event. Tries calendar/event/update first; if the integration
    doesn't support update (e.g. Google Calendar via HA), falls back to
    delete+create so the user still sees their changes."""
    try:
        return _ha_ws_call(url, token, {
            "type": "calendar/event/update",
            "entity_id": entity_id,
            "uid": uid,
            "event": _ha_ws_event_payload(data),
        })
    except Exception as exc:
        msg = str(exc).lower()
        if "not_supported" not in msg and "does not support" not in msg:
            raise
        logger.info("HA update not supported for %s, falling back to delete+create", entity_id)

    # Fallback: delete the old event, then create a new one
    try:
        _ha_ws_call(url, token, {
            "type": "calendar/event/delete",
            "entity_id": entity_id,
            "uid": uid,
        })
    except Exception as exc:
        logger.warning("HA delete during update fallback failed: %s", exc)
        # Continue anyway — try the create

    return _ha_ws_call(url, token, {
        "type": "calendar/event/create",
        "entity_id": entity_id,
        "event": _ha_ws_event_payload(data),
    })


def _ha_delete_event(url: str, token: str, entity_id: str, uid: str):
    """Delete an event via WebSocket command (the only reliable path)."""
    return _ha_ws_call(url, token, {
        "type": "calendar/event/delete",
        "entity_id": entity_id,
        "uid": uid,
    })


def _parse_ha_event(ev: dict, cal_db_id: int, cal_name: str, cal_color: str) -> dict:
    start = ev.get("start", {})
    end = ev.get("end", {})
    all_day = "date" in start and "dateTime" not in start
    return {
        "id": ev.get("uid") or f"ha-{cal_db_id}-{ev.get('summary', '')}",
        "url": f"homeassistant://{cal_db_id}/{ev.get('uid', '')}",
        "title": ev.get("summary", "(Kein Titel)"),
        "start": start.get("dateTime") or start.get("date", ""),
        "end": end.get("dateTime") or end.get("date", ""),
        "allDay": all_day,
        "location": ev.get("location", ""),
        "description": ev.get("description", ""),
        "color": None,
        "calendar_id": f"homeassistant-{cal_db_id}",
        "calendar_name": cal_name,
        "calendarColor": cal_color,
        "source": "homeassistant",
    }


def get_ha_events(account: models.HomeAssistantAccount, start_dt: datetime, end_dt: datetime, db: Session) -> list:
    all_events = []
    try:
        token = _get_valid_token(account, db)
    except Exception as exc:
        logger.error("HA token error for %s: %s", account.name, exc)
        raise
    for cal in account.calendars:
        if not cal.enabled or cal.sidebar_hidden:
            continue
        try:
            raw = _ha_get_events(account.url, token, cal.entity_id, start_dt, end_dt)
            color = cal.color or HA_DEFAULT_COLOR
            for ev in raw:
                all_events.append(_parse_ha_event(ev, cal.id, cal.name, color))
        except Exception as exc:
            logger.error("HA event fetch error %s (%s): %s", cal.entity_id, account.name, exc)
    return all_events


# ── Serialization ─────────────────────────────────────────

def _account_dict(a: models.HomeAssistantAccount) -> dict:
    return {
        "id": a.id,
        "name": a.name,
        "url": a.url,
        "auth_method": a.auth_method or "token",
        "calendars": [
            {
                "id": c.id,
                "name": c.name,
                "entity_id": c.entity_id,
                "color": c.color or HA_DEFAULT_COLOR,
                "enabled": c.enabled,
                "sidebar_hidden": bool(c.sidebar_hidden),
            }
            for c in a.calendars
        ],
    }


# ── Pydantic models ───────────────────────────────────────

class HAAccountCreate(BaseModel):
    name: str
    url: str
    token: str


class HAOAuthStart(BaseModel):
    name: str
    url: str
    client_id: str
    redirect_uri: str


class HACalendarUpdate(BaseModel):
    enabled: Optional[bool] = None
    color: Optional[str] = None
    name: Optional[str] = None
    sidebar_hidden: Optional[bool] = None


# ── Endpoints ─────────────────────────────────────────────

@router.get("/accounts")
def list_accounts(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    accounts = (
        db.query(models.HomeAssistantAccount)
        .filter(models.HomeAssistantAccount.user_id == current_user.id)
        .all()
    )
    return [_account_dict(a) for a in accounts]


@router.post("/accounts")
def add_account(
    data: HAAccountCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Create a HA account from a Long-Lived Access Token."""
    remote_cals = _ha_get_calendars(data.url, data.token)

    account = models.HomeAssistantAccount(
        user_id=current_user.id,
        name=data.name,
        url=data.url,
        token=data.token,
        auth_method="token",
        refresh_token=None,
        token_expiry=None,
    )
    db.add(account)
    db.flush()

    for cal in remote_cals:
        entity_id = cal.get("entity_id", "")
        if not entity_id:
            continue
        db.add(models.HomeAssistantCalendar(
            account_id=account.id,
            entity_id=entity_id,
            name=cal.get("name") or entity_id,
            color=None,
            enabled=True,
        ))

    db.commit()
    db.refresh(account)
    return _account_dict(account)


@router.post("/auth-url")
def oauth_start(
    data: HAOAuthStart,
    current_user: models.User = Depends(get_current_user),
):
    """Start the OAuth flow: store pending state, return HA authorization URL."""
    _cleanup_pending()
    state_token = secrets.token_urlsafe(32)
    _pending_oauth[state_token] = {
        "user_id": current_user.id,
        "ha_url": data.url.rstrip('/'),
        "name": data.name,
        "client_id": data.client_id,
        "redirect_uri": data.redirect_uri,
        "expires": time.time() + 600,
    }
    params = {
        "client_id": data.client_id,
        "redirect_uri": data.redirect_uri,
        "state": state_token,
        "response_type": "code",
    }
    return {"url": f"{data.url.rstrip('/')}/auth/authorize?{urlencode(params)}"}


@router.get("/callback")
def oauth_callback(
    request: Request,
    code: str = Query(""),
    state: str = Query(""),
    error: str = Query(""),
    db: Session = Depends(get_db),
):
    """Callback from Home Assistant after user authorization."""
    if error or not code:
        return RedirectResponse(url=f"/?ha_error={error or 'no_code'}", status_code=302)

    pending = _pending_oauth.pop(state, None)
    if not pending or pending["expires"] < time.time():
        return RedirectResponse(url="/?ha_error=state_expired", status_code=302)

    ha_url = pending["ha_url"]
    client_id = pending["client_id"]

    # Exchange code for tokens
    try:
        resp = http_requests.post(
            f"{ha_url}/auth/token",
            data={
                "grant_type": "authorization_code",
                "code": code,
                "client_id": client_id,
            },
            timeout=15,
            verify=False,
        )
    except Exception as exc:
        logger.error("HA token exchange connection error: %s", exc)
        return RedirectResponse(url="/?ha_error=ha_unreachable", status_code=302)

    if resp.status_code != 200:
        logger.error("HA token exchange failed (%s): %s", resp.status_code, resp.text)
        return RedirectResponse(url="/?ha_error=token_exchange_failed", status_code=302)

    tokens = resp.json()
    access_token = tokens["access_token"]
    refresh_token = tokens.get("refresh_token", "")
    expires_in = tokens.get("expires_in", 1800)
    now = datetime.now(timezone.utc)

    try:
        remote_cals = _ha_get_calendars(ha_url, access_token)
    except HTTPException as exc:
        logger.error("HA calendar fetch failed after OAuth: %s", exc.detail)
        return RedirectResponse(url="/?ha_error=calendars_failed", status_code=302)

    account = models.HomeAssistantAccount(
        user_id=pending["user_id"],
        name=pending["name"],
        url=ha_url,
        token=access_token,
        auth_method="oauth",
        refresh_token=refresh_token,
        token_expiry=datetime.fromtimestamp(now.timestamp() + expires_in, tz=timezone.utc),
        client_id=client_id,
    )
    db.add(account)
    db.flush()

    for cal in remote_cals:
        entity_id = cal.get("entity_id", "")
        if not entity_id:
            continue
        db.add(models.HomeAssistantCalendar(
            account_id=account.id,
            entity_id=entity_id,
            name=cal.get("name") or entity_id,
            color=None,
            enabled=True,
        ))

    db.commit()
    return RedirectResponse(url="/?ha_connected=1", status_code=302)


@router.delete("/accounts/{account_id}")
def delete_account(
    account_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    acc = (
        db.query(models.HomeAssistantAccount)
        .filter(
            models.HomeAssistantAccount.id == account_id,
            models.HomeAssistantAccount.user_id == current_user.id,
        )
        .first()
    )
    if not acc:
        raise HTTPException(404, "Account not found")
    db.delete(acc)
    db.commit()
    return {"ok": True}


@router.post("/accounts/{account_id}/sync")
def sync_account(
    account_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    acc = (
        db.query(models.HomeAssistantAccount)
        .filter(
            models.HomeAssistantAccount.id == account_id,
            models.HomeAssistantAccount.user_id == current_user.id,
        )
        .first()
    )
    if not acc:
        raise HTTPException(404, "Account not found")

    token = _get_valid_token(acc, db)
    remote_cals = _ha_get_calendars(acc.url, token)
    existing = {c.entity_id: c for c in acc.calendars}

    for cal in remote_cals:
        entity_id = cal.get("entity_id", "")
        if not entity_id:
            continue
        if entity_id not in existing:
            db.add(models.HomeAssistantCalendar(
                account_id=acc.id,
                entity_id=entity_id,
                name=cal.get("name") or entity_id,
                color=None,
                enabled=True,
            ))
        else:
            existing[entity_id].name = cal.get("name") or entity_id

    db.commit()
    db.refresh(acc)
    return _account_dict(acc)


@router.put("/calendars/{calendar_id}")
def update_calendar(
    calendar_id: int,
    data: HACalendarUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    cal = (
        db.query(models.HomeAssistantCalendar)
        .join(models.HomeAssistantAccount)
        .filter(
            models.HomeAssistantCalendar.id == calendar_id,
            models.HomeAssistantAccount.user_id == current_user.id,
        )
        .first()
    )
    if not cal:
        raise HTTPException(404, "Calendar not found")
    if data.enabled is not None:
        cal.enabled = data.enabled
    if data.color is not None:
        cal.color = data.color
    if data.name is not None:
        cal.name = data.name
    if data.sidebar_hidden is not None:
        cal.sidebar_hidden = data.sidebar_hidden
    db.commit()
    return {"ok": True}


# ── Event CRUD ───────────────────────────────────────────

class HAEventUpdate(BaseModel):
    title: Optional[str] = None
    start: Optional[str] = None
    end: Optional[str] = None
    allDay: Optional[bool] = None
    location: Optional[str] = None
    description: Optional[str] = None


class HAEventCreate(BaseModel):
    calendar_id: int
    title: str
    start: str
    end: str
    allDay: bool = False
    location: Optional[str] = None
    description: Optional[str] = None


@router.post("/events")
def create_event(
    data: HAEventCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    cal = (
        db.query(models.HomeAssistantCalendar)
        .join(models.HomeAssistantAccount)
        .filter(
            models.HomeAssistantCalendar.id == data.calendar_id,
            models.HomeAssistantAccount.user_id == current_user.id,
        )
        .first()
    )
    if not cal:
        raise HTTPException(404, "Calendar not found")
    account = cal.account
    token = _get_valid_token(account, db)
    try:
        _ha_create_event(
            account.url, token, cal.entity_id,
            data.model_dump(exclude_none=True),
        )
        return {"ok": True}
    except Exception as exc:
        raise HTTPException(500, f"HA event create failed: {exc}")


@router.put("/events/{calendar_id}/{uid}")
def update_event(
    calendar_id: int,
    uid: str,
    data: HAEventUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    cal = (
        db.query(models.HomeAssistantCalendar)
        .join(models.HomeAssistantAccount)
        .filter(
            models.HomeAssistantCalendar.id == calendar_id,
            models.HomeAssistantAccount.user_id == current_user.id,
        )
        .first()
    )
    if not cal:
        raise HTTPException(404, "Calendar not found")
    account = cal.account
    token = _get_valid_token(account, db)
    try:
        _ha_update_event(
            account.url, token, cal.entity_id, uid,
            data.model_dump(exclude_none=True),
        )
        return {"ok": True}
    except Exception as exc:
        raise HTTPException(500, f"HA event update failed: {exc}")


@router.delete("/events/{calendar_id}/{uid}")
def delete_event(
    calendar_id: int,
    uid: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    cal = (
        db.query(models.HomeAssistantCalendar)
        .join(models.HomeAssistantAccount)
        .filter(
            models.HomeAssistantCalendar.id == calendar_id,
            models.HomeAssistantAccount.user_id == current_user.id,
        )
        .first()
    )
    if not cal:
        raise HTTPException(404, "Calendar not found")
    account = cal.account
    token = _get_valid_token(account, db)
    try:
        _ha_delete_event(account.url, token, cal.entity_id, uid)
        return {"ok": True}
    except Exception as exc:
        raise HTTPException(500, f"HA event delete failed: {exc}")
