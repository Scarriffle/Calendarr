from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

import models
from auth import get_current_user
from database import get_db

router = APIRouter()


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

    # For these three override colours, an explicit null is meaningful
    # ("reset to default") and must be persisted as NULL. All other fields
    # keep the previous behaviour where a null/missing value is ignored.
    NULLABLE_OVERRIDES = {"text_color", "line_color", "bg_color", "group_visible_calendar_id"}
    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        if field in NULLABLE_OVERRIDES:
            setattr(settings, field, value or None)
        elif value is not None:
            setattr(settings, field, value)

    db.commit()
    return {"ok": True}
