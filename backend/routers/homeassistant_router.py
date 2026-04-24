import logging
from datetime import datetime, timezone
from typing import Optional

import requests as http_requests
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

import models
from auth import get_current_user
from database import get_db

logger = logging.getLogger(__name__)
router = APIRouter()

HA_DEFAULT_COLOR = "#03a9f4"
HA_CLIENT_ID = "http://localhost/"


# ── Auth helpers ──────────────────────────────────────────

def _ha_login(url: str, username: str, password: str) -> tuple:
    """Password grant → (access_token, refresh_token, expires_in)"""
    try:
        resp = http_requests.post(
            f"{url.rstrip('/')}/auth/token",
            data={
                "grant_type": "password",
                "username": username,
                "password": password,
                "client_id": HA_CLIENT_ID,
            },
            timeout=10,
            verify=False,
        )
    except http_requests.exceptions.ConnectionError:
        raise HTTPException(503, "Home Assistant nicht erreichbar")
    except http_requests.exceptions.Timeout:
        raise HTTPException(503, "Home Assistant antwortet nicht (Timeout)")
    if resp.status_code in (400, 401):
        raise HTTPException(400, "Ungültige Anmeldedaten")
    resp.raise_for_status()
    data = resp.json()
    return data["access_token"], data.get("refresh_token", ""), data.get("expires_in", 1800)


def _ha_refresh(url: str, refresh_token: str) -> tuple:
    """Refresh grant → (access_token, expires_in)"""
    resp = http_requests.post(
        f"{url.rstrip('/')}/auth/token",
        data={
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "client_id": HA_CLIENT_ID,
        },
        timeout=10,
        verify=False,
    )
    resp.raise_for_status()
    data = resp.json()
    return data["access_token"], data.get("expires_in", 1800)


def _get_valid_token(account: models.HomeAssistantAccount, db: Session) -> str:
    """Return a valid access token, refreshing if necessary."""
    if account.auth_method != "password":
        return account.token  # Long-Lived Token läuft nicht ab
    now = datetime.now(timezone.utc)
    if account.token_expiry and account.token_expiry.replace(tzinfo=timezone.utc) > now:
        return account.token
    # Needs refresh
    try:
        access_token, expires_in = _ha_refresh(account.url, account.refresh_token)
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
    token: Optional[str] = None
    username: Optional[str] = None
    password: Optional[str] = None


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
    now = datetime.now(timezone.utc)

    if data.username and data.password:
        access_token, refresh_tok, expires_in = _ha_login(data.url, data.username, data.password)
        auth_method = "password"
        stored_refresh = refresh_tok
        token_expiry = datetime.fromtimestamp(now.timestamp() + expires_in, tz=timezone.utc)
    elif data.token:
        access_token = data.token
        auth_method = "token"
        stored_refresh = None
        token_expiry = None
    else:
        raise HTTPException(400, "Token oder Benutzername/Passwort erforderlich")

    remote_cals = _ha_get_calendars(data.url, access_token)

    account = models.HomeAssistantAccount(
        user_id=current_user.id,
        name=data.name,
        url=data.url,
        token=access_token,
        auth_method=auth_method,
        refresh_token=stored_refresh,
        token_expiry=token_expiry,
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
