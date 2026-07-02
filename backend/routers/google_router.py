import logging
import os
from datetime import datetime, timezone
from typing import Optional
from urllib.parse import urlencode

import requests as http_requests
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import RedirectResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session

import models
from auth import get_current_user
from database import get_db

logger = logging.getLogger(__name__)
router = APIRouter()

GOOGLE_CLIENT_ID = os.environ.get("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = os.environ.get("GOOGLE_CLIENT_SECRET", "")
GOOGLE_REDIRECT_URI = os.environ.get("GOOGLE_REDIRECT_URI", "")

SCOPES = "https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/userinfo.email"
AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
CALENDAR_API = "https://www.googleapis.com/calendar/v3"

# System/virtual Google calendars that should never be shown
SKIP_GOOGLE_CALENDAR_IDS = {
    "#weekNum@group.v.calendar.google.com",  # Kalenderwochen / Week numbers
}


def _is_system_calendar(cal_id: str) -> bool:
    """Return True for virtual/system calendars that should be hidden."""
    return cal_id in SKIP_GOOGLE_CALENDAR_IDS or "weeknum" in cal_id.lower()


def _google_configured() -> bool:
    return bool(GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET)


def _refresh_access_token(account: models.GoogleAccount, db: Session) -> str:
    """Refresh the access token if expired, return valid access token."""
    now = datetime.now(timezone.utc)
    if account.token_expiry and account.token_expiry.replace(tzinfo=timezone.utc) > now:
        return account.access_token

    resp = http_requests.post(TOKEN_URL, data={
        "client_id": GOOGLE_CLIENT_ID,
        "client_secret": GOOGLE_CLIENT_SECRET,
        "refresh_token": account.refresh_token,
        "grant_type": "refresh_token",
    }, timeout=15)
    if resp.status_code != 200:
        logger.error("Google token refresh failed: %s", resp.text)
        raise HTTPException(401, "Google-Token abgelaufen, bitte neu verbinden")

    data = resp.json()
    account.access_token = data["access_token"]
    account.token_expiry = datetime.fromtimestamp(
        now.timestamp() + data.get("expires_in", 3600), tz=timezone.utc
    )
    db.commit()
    return account.access_token


def _google_api(token: str, path: str, method: str = "GET", json_body=None, params=None):
    """Make an authenticated request to Google Calendar API."""
    headers = {"Authorization": f"Bearer {token}"}
    url = f"{CALENDAR_API}{path}"
    if method == "GET":
        resp = http_requests.get(url, headers=headers, params=params, timeout=15)
    elif method == "POST":
        resp = http_requests.post(url, headers=headers, json=json_body, timeout=15)
    elif method == "PUT":
        resp = http_requests.put(url, headers=headers, json=json_body, timeout=15)
    elif method == "PATCH":
        resp = http_requests.patch(url, headers=headers, json=json_body, timeout=15)
    elif method == "DELETE":
        resp = http_requests.delete(url, headers=headers, timeout=15)
        if resp.status_code == 204:
            return {"ok": True}
    else:
        raise ValueError(f"Unsupported method: {method}")

    if resp.status_code >= 400:
        logger.error("Google API error %s %s: %s", method, path, resp.text)
        raise HTTPException(resp.status_code, f"Google API Fehler: {resp.status_code}")
    return resp.json() if resp.text else {}


def _build_event_body(data: dict) -> dict:
    """Convert our event format to Google Calendar API format."""
    body = {"summary": data.get("title", "")}
    if data.get("location"):
        body["location"] = data["location"]
    if data.get("description"):
        body["description"] = data["description"]

    if data.get("allDay"):
        body["start"] = {"date": data["start"][:10]}
        body["end"] = {"date": data["end"][:10]}
    else:
        body["start"] = {"dateTime": data["start"]}
        body["end"] = {"dateTime": data["end"]}
    return body


def _parse_google_event(ev: dict, gcal_db_id: int, cal_name: str, cal_color: str) -> dict:
    """Convert Google Calendar event to our format."""
    start = ev.get("start", {})
    end = ev.get("end", {})
    all_day = "date" in start

    return {
        "id": ev["id"],
        "url": f"google://{gcal_db_id}/{ev['id']}",
        "title": ev.get("summary", "(Kein Titel)"),
        "start": start.get("date") or start.get("dateTime", ""),
        "end": end.get("date") or end.get("dateTime", ""),
        "allDay": all_day,
        "location": ev.get("location", ""),
        "description": ev.get("description", ""),
        "color": None,
        "calendar_id": f"google-{gcal_db_id}",
        "calendar_name": cal_name,
        "calendarColor": cal_color,
        "source": "google",
    }


def _account_dict(a: models.GoogleAccount) -> dict:
    return {
        "id": a.id,
        "email": a.email,
        "calendars": [
            {
                "id": c.id,
                "name": c.name,
                "color": c.color or "#4285f4",
                "enabled": c.enabled,
                "sidebar_hidden": bool(c.sidebar_hidden),
                "reminders_enabled": bool(c.reminders_enabled),
            }
            for c in a.calendars
            if not _is_system_calendar(c.cal_id)
        ],
    }


def _sync_google_calendars(account: models.GoogleAccount, db: Session):
    """Fetch calendar list from Google and persist/update GoogleCalendar records."""
    try:
        token = _refresh_access_token(account, db)
        cal_list = _google_api(token, "/users/me/calendarList")
        # Remove any previously stored system calendars (e.g. locale-specific weeknum variants)
        for c in list(account.calendars):
            if _is_system_calendar(c.cal_id):
                db.delete(c)
        existing = {c.cal_id: c for c in account.calendars if not _is_system_calendar(c.cal_id)}
        for cal in cal_list.get("items", []):
            if cal.get("deleted"):
                continue
            cal_id = cal["id"]
            if _is_system_calendar(cal_id):
                continue
            if cal_id not in existing:
                db.add(models.GoogleCalendar(
                    account_id=account.id,
                    cal_id=cal_id,
                    name=cal.get("summary", cal_id),
                    color=cal.get("backgroundColor", "#4285f4"),
                    enabled=True,
                ))
            else:
                existing[cal_id].name = cal.get("summary", cal_id)
                if not existing[cal_id].color:
                    existing[cal_id].color = cal.get("backgroundColor", "#4285f4")
        db.commit()
        db.refresh(account)
    except Exception as exc:
        logger.error("Error syncing Google calendars for %s: %s", account.email, exc)


# ── OAuth2 Flow ──────────────────────────────────────────

@router.get("/configured")
def is_configured():
    return {"configured": _google_configured()}


@router.get("/auth-url")
def get_auth_url(current_user: models.User = Depends(get_current_user)):
    if not _google_configured():
        raise HTTPException(400, "Google OAuth nicht konfiguriert")

    redirect_uri = GOOGLE_REDIRECT_URI or ""
    params = {
        "client_id": GOOGLE_CLIENT_ID,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": SCOPES,
        "access_type": "offline",
        "prompt": "consent",
        "state": str(current_user.id),
    }
    return {"url": f"{AUTH_URL}?{urlencode(params)}"}


@router.get("/callback")
def oauth_callback(
    code: str = Query(...),
    state: str = Query(""),
    db: Session = Depends(get_db),
):
    if not _google_configured():
        raise HTTPException(400, "Google OAuth nicht konfiguriert")

    # Exchange code for tokens
    resp = http_requests.post(TOKEN_URL, data={
        "client_id": GOOGLE_CLIENT_ID,
        "client_secret": GOOGLE_CLIENT_SECRET,
        "code": code,
        "grant_type": "authorization_code",
        "redirect_uri": GOOGLE_REDIRECT_URI,
    }, timeout=15)

    if resp.status_code != 200:
        logger.error("Google token exchange failed: %s", resp.text)
        raise HTTPException(400, "Fehler beim Google-Login")

    tokens = resp.json()
    access_token = tokens["access_token"]
    refresh_token = tokens.get("refresh_token", "")
    expires_in = tokens.get("expires_in", 3600)

    # Get user email
    user_info = http_requests.get(
        "https://www.googleapis.com/oauth2/v2/userinfo",
        headers={"Authorization": f"Bearer {access_token}"},
        timeout=10,
    ).json()
    email = user_info.get("email", "Unbekannt")

    user_id = int(state) if state.isdigit() else None
    if not user_id:
        raise HTTPException(400, "Ungültiger State-Parameter")

    # Check if account already exists
    existing = (
        db.query(models.GoogleAccount)
        .filter(models.GoogleAccount.user_id == user_id, models.GoogleAccount.email == email)
        .first()
    )
    if existing:
        existing.access_token = access_token
        if refresh_token:
            existing.refresh_token = refresh_token
        existing.token_expiry = datetime.fromtimestamp(
            datetime.now(timezone.utc).timestamp() + expires_in, tz=timezone.utc
        )
        db.commit()
        account = existing
    else:
        account = models.GoogleAccount(
            user_id=user_id,
            email=email,
            access_token=access_token,
            refresh_token=refresh_token,
            token_expiry=datetime.fromtimestamp(
                datetime.now(timezone.utc).timestamp() + expires_in, tz=timezone.utc
            ),
        )
        db.add(account)
        db.commit()
        db.refresh(account)

    # Sync calendars after connecting/reconnecting
    _sync_google_calendars(account, db)

    return RedirectResponse(url="/", status_code=302)


# ── Account Management ───────────────────────────────────

@router.get("/accounts")
def list_accounts(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    accounts = (
        db.query(models.GoogleAccount)
        .filter(models.GoogleAccount.user_id == current_user.id)
        .all()
    )
    # Auto-sync calendars for accounts that have none yet
    for acc in accounts:
        if not acc.calendars:
            _sync_google_calendars(acc, db)
    return [_account_dict(a) for a in accounts]


@router.delete("/accounts/{account_id}")
def delete_account(
    account_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    acc = (
        db.query(models.GoogleAccount)
        .filter(models.GoogleAccount.id == account_id, models.GoogleAccount.user_id == current_user.id)
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
        db.query(models.GoogleAccount)
        .filter(models.GoogleAccount.id == account_id, models.GoogleAccount.user_id == current_user.id)
        .first()
    )
    if not acc:
        raise HTTPException(404, "Account not found")
    _sync_google_calendars(acc, db)
    db.refresh(acc)
    return _account_dict(acc)


# ── Calendar Management ──────────────────────────────────

class GoogleCalendarUpdate(BaseModel):
    enabled: Optional[bool] = None
    color: Optional[str] = None
    name: Optional[str] = None
    sidebar_hidden: Optional[bool] = None
    reminders_enabled: Optional[bool] = None


@router.put("/calendars/{calendar_id}")
def update_calendar(
    calendar_id: int,
    data: GoogleCalendarUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    gcal = (
        db.query(models.GoogleCalendar)
        .join(models.GoogleAccount)
        .filter(
            models.GoogleCalendar.id == calendar_id,
            models.GoogleAccount.user_id == current_user.id,
        )
        .first()
    )
    if not gcal:
        raise HTTPException(404, "Calendar not found")
    if data.enabled is not None:
        gcal.enabled = data.enabled
    if data.color is not None:
        gcal.color = data.color
    if data.name is not None:
        gcal.name = data.name
    if data.sidebar_hidden is not None:
        gcal.sidebar_hidden = data.sidebar_hidden
    if data.reminders_enabled is not None:
        gcal.reminders_enabled = data.reminders_enabled
    db.commit()
    return {"ok": True}


# ── Events ───────────────────────────────────────────────

def get_google_events(account: models.GoogleAccount, start_dt: datetime, end_dt: datetime, db: Session) -> tuple:
    """Fetch events from all enabled Google calendars for an account.

    Returns (events, errors) — errors is a list of
    {"source": "google", "name": ..., "message": ...} dicts for any
    calendar that failed to sync. Never includes raw exception text.
    """
    try:
        token = _refresh_access_token(account, db)
    except Exception as exc:
        logger.error("Token refresh failed for Google account %s: %s", account.email, exc)
        raise

    all_events = []
    errors = []
    for gcal in account.calendars:
        if not gcal.enabled or gcal.sidebar_hidden:
            continue
        if _is_system_calendar(gcal.cal_id):
            continue
        try:
            events_resp = _google_api(token, f"/calendars/{gcal.cal_id}/events", params={
                "timeMin": start_dt.isoformat(),
                "timeMax": end_dt.isoformat(),
                "singleEvents": "true",
                "maxResults": 500,
            })
            for ev in events_resp.get("items", []):
                if ev.get("status") == "cancelled":
                    continue
                all_events.append(_parse_google_event(ev, gcal.id, gcal.name, gcal.color or "#4285f4"))
        except Exception as exc:
            logger.error("Error fetching events for calendar %s (%s): %s", gcal.name, gcal.cal_id, exc)
            errors.append({
                "source": "google",
                "name": f"{account.email} – {gcal.name}",
                "message": "Sync fehlgeschlagen",
            })

    return all_events, errors


class GoogleEventCreate(BaseModel):
    calendar_db_id: int
    title: str
    start: str
    end: str
    allDay: bool = False
    location: Optional[str] = None
    description: Optional[str] = None


class GoogleEventUpdate(BaseModel):
    title: Optional[str] = None
    start: Optional[str] = None
    end: Optional[str] = None
    allDay: Optional[bool] = None
    location: Optional[str] = None
    description: Optional[str] = None


@router.post("/events")
def create_event(
    data: GoogleEventCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    gcal = (
        db.query(models.GoogleCalendar)
        .join(models.GoogleAccount)
        .filter(
            models.GoogleCalendar.id == data.calendar_db_id,
            models.GoogleAccount.user_id == current_user.id,
        )
        .first()
    )
    if not gcal:
        raise HTTPException(404, "Google calendar not found")

    token = _refresh_access_token(gcal.account, db)
    body = _build_event_body(data.model_dump())
    result = _google_api(token, f"/calendars/{gcal.cal_id}/events", method="POST", json_body=body)
    return {"id": result.get("id"), "ok": True}


@router.put("/events/{gcal_db_id}/{event_id}")
def update_event(
    gcal_db_id: int,
    event_id: str,
    data: GoogleEventUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    gcal = (
        db.query(models.GoogleCalendar)
        .join(models.GoogleAccount)
        .filter(
            models.GoogleCalendar.id == gcal_db_id,
            models.GoogleAccount.user_id == current_user.id,
        )
        .first()
    )
    if not gcal:
        raise HTTPException(404, "Google calendar not found")

    token = _refresh_access_token(gcal.account, db)
    body = _build_event_body(data.model_dump(exclude_none=True))
    _google_api(token, f"/calendars/{gcal.cal_id}/events/{event_id}", method="PATCH", json_body=body)
    return {"ok": True}


@router.delete("/events/{gcal_db_id}/{event_id}")
def delete_event(
    gcal_db_id: int,
    event_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    gcal = (
        db.query(models.GoogleCalendar)
        .join(models.GoogleAccount)
        .filter(
            models.GoogleCalendar.id == gcal_db_id,
            models.GoogleAccount.user_id == current_user.id,
        )
        .first()
    )
    if not gcal:
        raise HTTPException(404, "Google calendar not found")

    token = _refresh_access_token(gcal.account, db)
    _google_api(token, f"/calendars/{gcal.cal_id}/events/{event_id}", method="DELETE")
    return {"ok": True}
