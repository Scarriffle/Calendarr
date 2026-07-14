import json
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

import models
from auth import get_current_user
from database import get_db

router = APIRouter()


# Which settings can sync across a user's devices, and the default flag applied to
# an existing/new account until the user overrides it. This map is the single
# authority: GET returns the fully-resolved flags so no client duplicates default
# logic. Rollout rule: settings that already lived on the server default to True;
# the four newly-syncable device-local prefs default to False.
DEFAULT_SYNC = {
    "default_view": True,
    "week_start_day": True,
    "dim_past_events": True,
    "hour_height": True,
    "primary_color": True,
    "accent_color": True,
    "today_color": True,
    "text_color": True,
    "line_color": True,
    "bg_color": True,
    "month_divider_color": True,
    "month_label_color": True,
    "default_event_duration_minutes": True,
    "default_reminder_minutes": True,
    "language": False,
    "share_calendar_icon": False,
    "cache_months": False,
    "month_view_paged": False,
}


def _resolve_sync_flags(s: models.UserSettings) -> dict:
    """Fully-resolved {key: bool} for every syncable setting: stored overrides on
    top of DEFAULT_SYNC, junk keys dropped."""
    stored = {}
    if s.sync_flags:
        try:
            stored = json.loads(s.sync_flags) or {}
        except (ValueError, TypeError):
            stored = {}
    return {
        key: bool(stored[key]) if key in stored else default
        for key, default in DEFAULT_SYNC.items()
    }


class SettingsUpdate(BaseModel):
    default_view: Optional[str] = None
    week_start_day: Optional[str] = None
    primary_color: Optional[str] = None
    accent_color: Optional[str] = None
    today_color: Optional[str] = None
    dim_past_events: Optional[bool] = None
    text_contrast: Optional[int] = None
    line_contrast: Optional[int] = None
    hour_height: Optional[int] = None
    language: Optional[str] = None
    month_divider_color: Optional[str] = None
    month_label_color: Optional[str] = None
    text_color: Optional[str] = None
    line_color: Optional[str] = None
    bg_color:   Optional[str] = None
    private_event_visibility: Optional[str] = None
    group_visible_calendar_id: Optional[int] = None
    default_reminder_minutes: Optional[int] = None  # null = off
    default_event_duration_minutes: Optional[int] = None
    share_calendar_icon: Optional[str] = None
    cache_months: Optional[int] = None
    month_view_paged: Optional[bool] = None
    sync_flags: Optional[dict] = None  # partial {key: bool}, merged into stored map


def _settings_dict(s: models.UserSettings) -> dict:
    return {
        "default_view": s.default_view,
        "week_start_day": s.week_start_day or "monday",
        "primary_color": s.primary_color,
        "accent_color": s.accent_color,
        "today_color": s.today_color,
        "dim_past_events": s.dim_past_events,
        "text_contrast": s.text_contrast or 3,
        "line_contrast": s.line_contrast or 3,
        "hour_height": s.hour_height or 60,
        "language": s.language or "de",
        "month_divider_color": s.month_divider_color or "#7090c0",
        "month_label_color": s.month_label_color or "#7090c0",
        "text_color": s.text_color,
        "line_color": s.line_color,
        "bg_color":   s.bg_color,
        "private_event_visibility": s.private_event_visibility or "busy",
        "group_visible_calendar_id": s.group_visible_calendar_id,
        "default_reminder_minutes": s.default_reminder_minutes,
        "default_event_duration_minutes": s.default_event_duration_minutes or 60,
        "share_calendar_icon": s.share_calendar_icon,
        "cache_months": s.cache_months or 3,
        "month_view_paged": bool(s.month_view_paged),
        "sync_flags": _resolve_sync_flags(s),
    }


@router.get("/")
def get_settings(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    settings = (
        db.query(models.UserSettings)
        .filter(models.UserSettings.user_id == current_user.id)
        .first()
    )
    if not settings:
        settings = models.UserSettings(user_id=current_user.id)
        db.add(settings)
        db.commit()
        db.refresh(settings)
    return _settings_dict(settings)


@router.put("/")
def update_settings(
    data: SettingsUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    settings = (
        db.query(models.UserSettings)
        .filter(models.UserSettings.user_id == current_user.id)
        .first()
    )
    if not settings:
        settings = models.UserSettings(user_id=current_user.id)
        db.add(settings)

    if data.private_event_visibility is not None and data.private_event_visibility not in ("hidden", "busy"):
        raise HTTPException(422, "private_event_visibility must be 'hidden' or 'busy'")

    # A birthday calendar must never become the group-visible ("personal")
    # calendar — it may be shared directly, but not stand in as your calendar in
    # group views. Clients filter it out of the picker; this is the safety net.
    if data.group_visible_calendar_id:
        bcal = (
            db.query(models.LocalCalendar)
            .filter(
                models.LocalCalendar.id == data.group_visible_calendar_id,
                models.LocalCalendar.user_id == current_user.id,
            )
            .first()
        )
        if bcal is not None and bcal.is_birthday:
            raise HTTPException(422, "A birthday calendar can't be your group-visible calendar")

    # For these three override colours, an explicit null is meaningful
    # ("reset to default") and must be persisted as NULL. All other fields
    # keep the previous behaviour where a null/missing value is ignored.
    NULLABLE_OVERRIDES = {"text_color", "line_color", "bg_color", "group_visible_calendar_id", "default_reminder_minutes", "default_event_duration_minutes", "share_calendar_icon"}
    update_data = data.model_dump(exclude_unset=True)

    # Merge sync-flag overrides into the stored account-wide JSON map. Only known
    # syncable keys are kept; a partial map leaves untouched flags as they were.
    if "sync_flags" in update_data:
        incoming = update_data.pop("sync_flags") or {}
        current = {}
        if settings.sync_flags:
            try:
                current = json.loads(settings.sync_flags) or {}
            except (ValueError, TypeError):
                current = {}
        for key, val in incoming.items():
            if key in DEFAULT_SYNC:
                current[key] = bool(val)
        settings.sync_flags = json.dumps(current)

    for field, value in update_data.items():
        if field in NULLABLE_OVERRIDES:
            setattr(settings, field, value or None)
        elif value is not None:
            setattr(settings, field, value)

    db.commit()
    return {"ok": True}
