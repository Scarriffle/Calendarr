import io
import re
import base64
import secrets
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import pyotp
import qrcode
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import FileResponse, Response
from PIL import Image
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from sqlalchemy import func

import models
from auth import create_access_token, get_current_user, get_password_hash, verify_password
from database import DATA_DIR, get_db

router = APIRouter()

AVATAR_DIR = DATA_DIR / "avatars"
AVATAR_DIR.mkdir(parents=True, exist_ok=True)
MAX_AVATAR_SIZE = 5 * 1024 * 1024  # 5 MB
ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp"}


# ── Schemas ───────────────────────────────────────────────
class ProfileUpdate(BaseModel):
    # Length caps (SQLite ignores VARCHAR limits, so enforce here).
    email: Optional[str] = Field(default=None, max_length=120)
    display_name: Optional[str] = Field(default=None, max_length=80)
    username: Optional[str] = Field(default=None, max_length=50)  # login name (stored lowercase)


def _strip_controls(s: str) -> str:
    """Remove control characters (defends against injected newlines / NULs that
    could be reflected in other clients' calendar/sharing/group views)."""
    return re.sub(r"[\x00-\x1f\x7f]", "", s).strip()


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
        "display_name": current_user.display_name or current_user.username,
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
    result = {"ok": True}
    if data.email is not None:
        email = _strip_controls(data.email)
        if email:
            if "@" not in email or "." not in email.split("@")[-1]:
                raise HTTPException(422, "Invalid email address")
            clash = (
                db.query(models.User)
                .filter(func.lower(models.User.email) == email.lower(),
                        models.User.id != current_user.id)
                .first()
            )
            if clash:
                raise HTTPException(400, "Email already in use")
            current_user.email = email
        else:
            current_user.email = None
    if data.display_name is not None:
        dn = _strip_controls(data.display_name)
        current_user.display_name = dn or current_user.username
    if data.username is not None:
        new_login = _strip_controls(data.username).lower()
        if not new_login:
            raise HTTPException(422, "Login name cannot be empty")
        if new_login != current_user.username:
            taken = (
                db.query(models.User)
                .filter(func.lower(models.User.username) == new_login,
                        models.User.id != current_user.id)
                .first()
            )
            if taken:
                raise HTTPException(400, "Username already taken")
            current_user.username = new_login
            db.commit()
            # The JWT 'sub' is the login name — renaming it invalidates the old
            # token, so hand back a fresh one for the client to store.
            result["access_token"] = create_access_token({"sub": new_login})
            return result
    db.commit()
    return result


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
        raise HTTPException(400, "Datei zu groß (max. 5 MB)")

    # Resize to 512x512 square
    img = Image.open(io.BytesIO(data))
    img = img.convert("RGB")
    # Use resize instead of thumbnail to ensure exact dimensions
    # If already cropped (square), this just resizes; otherwise fit to 512x512
    w, h = img.size
    if w != h:
        # Crop to square center
        side = min(w, h)
        left = (w - side) // 2
        top = (h - side) // 2
        img = img.crop((left, top, left + side, top + side))
    img = img.resize((512, 512), Image.LANCZOS)

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
    return FileResponse(
        str(path),
        media_type="image/jpeg",
        headers={"Cache-Control": "no-cache, no-store, must-revalidate"},
    )


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


# ── App passwords (for CalDAV Basic Auth) ────────────────
class AppPasswordCreate(BaseModel):
    label: str = Field(default="CalDAV", max_length=100)


def _app_pw_dict(ap: models.AppPassword) -> dict:
    return {
        "id": ap.id,
        "label": ap.label,
        "created_at": ap.created_at,
        "last_used_at": ap.last_used_at,
    }


@router.get("/app-passwords")
def list_app_passwords(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    rows = (
        db.query(models.AppPassword)
        .filter(models.AppPassword.user_id == current_user.id)
        .order_by(models.AppPassword.id.desc())
        .all()
    )
    return [_app_pw_dict(r) for r in rows]


@router.post("/app-passwords")
def create_app_password(
    data: AppPasswordCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    # Show the plaintext exactly once; only the hash is stored.
    password = secrets.token_urlsafe(18)
    ap = models.AppPassword(
        user_id=current_user.id,
        label=(data.label or "CalDAV")[:100],
        password_hash=get_password_hash(password),
        created_at=datetime.now(timezone.utc).isoformat(),
    )
    db.add(ap)
    db.commit()
    db.refresh(ap)
    out = _app_pw_dict(ap)
    out["password"] = password
    return out


@router.delete("/app-passwords/{ap_id}")
def delete_app_password(
    ap_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    ap = (
        db.query(models.AppPassword)
        .filter(
            models.AppPassword.id == ap_id,
            models.AppPassword.user_id == current_user.id,
        )
        .first()
    )
    if not ap:
        raise HTTPException(404, "App password not found")
    db.delete(ap)
    db.commit()
    return {"ok": True}
