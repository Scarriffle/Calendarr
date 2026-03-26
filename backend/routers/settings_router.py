from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

import models
from auth import get_current_user
from database import get_db

router = APIRouter()


class SettingsUpdate(BaseModel):
    default_view: Optional[str] = None
    primary_color: Optional[str] = None
    accent_color: Optional[str] = None
    today_color: Optional[str] = None
    dim_past_events: Optional[bool] = None


def _settings_dict(s: models.UserSettings) -> dict:
    return {
        "default_view": s.default_view,
        "primary_color": s.primary_color,
        "accent_color": s.accent_color,
        "today_color": s.today_color,
        "dim_past_events": s.dim_past_events,
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

    for field, value in data.model_dump(exclude_none=True).items():
        setattr(settings, field, value)

    db.commit()
    return {"ok": True}
