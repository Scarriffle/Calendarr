import io
import base64
from pathlib import Path
from typing import Optional

import pyotp
import qrcode
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from PIL import Image
from pydantic import BaseModel
from sqlalchemy.orm import Session

import models
from auth import get_current_user, get_password_hash, verify_password
from database import DATA_DIR, get_db

router = APIRouter()

AVATAR_DIR = DATA_DIR / "avatars"
AVATAR_DIR.mkdir(parents=True, exist_ok=True)
MAX_AVATAR_SIZE = 2 * 1024 * 1024  # 2 MB
ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp"}


# ── Schemas ───────────────────────────────────────────────
class ProfileUpdate(BaseModel):
    email: Optional[str] = None


class PasswordChange(BaseModel):
    current_password: str
    new_password: str


class TOTPVerify(BaseModel):
    code: str


class TOTPDisable(BaseModel):
    password: str


# ── Profile ───────────────────────────────────────────────
@router.get("/")
def get_profile(current_user: models.User = Depends(get_current_user)):
    return {
        "id": current_user.id,
        "username": current_user.username,
        "email": current_user.email,
        "is_admin": current_user.is_admin,
        "has_avatar": current_user.avatar_filename is not None,
        "totp_enabled": current_user.totp_enabled,
    }


@router.put("/")
def update_profile(
    data: ProfileUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if data.email is not None:
        current_user.email = data.email or None
    db.commit()
    return {"ok": True}


# ── Avatar ────────────────────────────────────────────────
@router.post("/avatar")
async def upload_avatar(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if file.content_type not in ALLOWED_TYPES:
        raise HTTPException(400, "Nur JPEG, PNG oder WebP erlaubt")

    data = await file.read()
    if len(data) > MAX_AVATAR_SIZE:
        raise HTTPException(400, "Datei zu groß (max. 2 MB)")

    # Resize to 256x256
    img = Image.open(io.BytesIO(data))
    img = img.convert("RGB")
    img.thumbnail((256, 256))

    filename = f"user_{current_user.id}.jpg"
    path = AVATAR_DIR / filename
    img.save(str(path), "JPEG", quality=85)

    current_user.avatar_filename = filename
    db.commit()
    return {"ok": True}


@router.get("/avatar")
def get_avatar(current_user: models.User = Depends(get_current_user)):
    if not current_user.avatar_filename:
        raise HTTPException(404, "Kein Profilbild")
    path = AVATAR_DIR / current_user.avatar_filename
    if not path.exists():
        raise HTTPException(404, "Kein Profilbild")
    return FileResponse(str(path), media_type="image/jpeg")


@router.get("/avatar/{user_id}")
def get_user_avatar(user_id: int, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user or not user.avatar_filename:
        raise HTTPException(404, "Kein Profilbild")
    path = AVATAR_DIR / user.avatar_filename
    if not path.exists():
        raise HTTPException(404, "Kein Profilbild")
    return FileResponse(str(path), media_type="image/jpeg")


@router.delete("/avatar")
def delete_avatar(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if current_user.avatar_filename:
        path = AVATAR_DIR / current_user.avatar_filename
        if path.exists():
            path.unlink()
        current_user.avatar_filename = None
        db.commit()
    return {"ok": True}


# ── Password ──────────────────────────────────────────────
@router.post("/password")
def change_password(
    data: PasswordChange,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if not verify_password(data.current_password, current_user.password_hash):
        raise HTTPException(400, "Aktuelles Passwort ist falsch")
    if len(data.new_password) < 6:
        raise HTTPException(400, "Passwort muss mindestens 6 Zeichen haben")
    current_user.password_hash = get_password_hash(data.new_password)
    db.commit()
    return {"ok": True}


# ── 2FA / TOTP ───────────────────────────────────────────
@router.post("/2fa/setup")
def setup_totp(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    secret = pyotp.random_base32()
    current_user.totp_secret = secret
    db.commit()

    totp = pyotp.TOTP(secret)
    uri = totp.provisioning_uri(name=current_user.username, issuer_name="Calendarr")

    # Generate QR code as base64
    qr = qrcode.make(uri, box_size=6, border=2)
    buf = io.BytesIO()
    qr.save(buf, format="PNG")
    qr_b64 = base64.b64encode(buf.getvalue()).decode()

    return {
        "secret": secret,
        "qr_code": f"data:image/png;base64,{qr_b64}",
    }


@router.post("/2fa/enable")
def enable_totp(
    data: TOTPVerify,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if not current_user.totp_secret:
        raise HTTPException(400, "2FA wurde noch nicht eingerichtet")

    totp = pyotp.TOTP(current_user.totp_secret)
    if not totp.verify(data.code, valid_window=1):
        raise HTTPException(400, "Ungültiger Code")

    current_user.totp_enabled = True
    db.commit()
    return {"ok": True}


@router.post("/2fa/disable")
def disable_totp(
    data: TOTPDisable,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if not verify_password(data.password, current_user.password_hash):
        raise HTTPException(400, "Passwort ist falsch")

    current_user.totp_secret = None
    current_user.totp_enabled = False
    db.commit()
    return {"ok": True}
