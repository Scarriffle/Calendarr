"""Birthday sync device tracking.

The iOS app reports, after each Contacts birthday sync, which device it was and
how many birthdays it manages. The web shows this as a "birthdays come from
these devices" list. Birthday events themselves are ordinary local events
(see local_router); this router only tracks the sync sources.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

import models
from auth import get_current_user
from database import get_db

router = APIRouter()


class SyncReport(BaseModel):
    device_id: str
    device_name: str
    count: int = 0


@router.post("/sync-report")
def report_sync(
    data: SyncReport,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Upsert the (user, device) sync record after a Contacts birthday sync."""
    row = (
        db.query(models.BirthdaySyncDevice)
        .filter(
            models.BirthdaySyncDevice.user_id == current_user.id,
            models.BirthdaySyncDevice.device_id == data.device_id,
        )
        .first()
    )
    now = datetime.now(timezone.utc).isoformat()
    name = (data.device_name or "Gerät")[:120]
    if row is None:
        db.add(models.BirthdaySyncDevice(
            user_id=current_user.id, device_id=data.device_id,
            device_name=name, last_sync=now, count=data.count,
        ))
    else:
        row.device_name = name
        row.last_sync = now
        row.count = data.count
    db.commit()
    return {"ok": True}


@router.get("/devices")
def list_devices(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    rows = (
        db.query(models.BirthdaySyncDevice)
        .filter(models.BirthdaySyncDevice.user_id == current_user.id)
        .order_by(models.BirthdaySyncDevice.last_sync.desc())
        .all()
    )
    return [
        {
            "device_id": r.device_id,
            "device_name": r.device_name,
            "last_sync": r.last_sync,
            "count": r.count,
        }
        for r in rows
    ]
