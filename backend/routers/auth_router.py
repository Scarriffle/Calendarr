from datetime import timedelta
from typing import Optional

import pyotp
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session

import models
from auth import create_access_token, get_current_user, get_password_hash, verify_password
from database import get_db

# When "Angemeldet bleiben" is ticked the token lives for half a year.
REMEMBER_ME_EXPIRY = timedelta(days=180)

router = APIRouter()


class SetupRequest(BaseModel):
    username: str
    password: str
    email: Optional[str] = None


class LoginRequest(BaseModel):
    username: str
    password: str
    totp_code: Optional[str] = None
    remember_me: Optional[bool] = False


def _user_dict(user: models.User) -> dict:
    return {
        "id": user.id,
        "username": user.username,
        "display_name": user.display_name or user.username,
        "is_admin": user.is_admin,
    }


@router.get("/setup-required")
def setup_required(db: Session = Depends(get_db)):
    return {"required": db.query(models.User).count() == 0}


@router.post("/setup")
def setup(req: SetupRequest, db: Session = Depends(get_db)):
    if db.query(models.User).count() > 0:
        raise HTTPException(400, "Setup already completed")
    user = models.User(
        username=req.username.lower(),
        display_name=req.username.strip(),  # keep the original casing for display
        email=req.email,
        password_hash=get_password_hash(req.password),
        is_admin=True,
    )
    db.add(user)
    db.flush()
    db.add(models.UserSettings(user_id=user.id))
    db.commit()
    db.refresh(user)
    token = create_access_token({"sub": user.username})
    return {"access_token": token, "token_type": "bearer", "user": _user_dict(user)}


@router.post("/token")
def login(
    form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)
):
    user = (
        db.query(models.User).filter(func.lower(models.User.username) == form_data.username.lower()).first()
    )
    if not user or not verify_password(form_data.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if user.totp_enabled:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="2fa_required",
        )
    token = create_access_token({"sub": user.username})
    return {"access_token": token, "token_type": "bearer", "user": _user_dict(user)}


@router.post("/login")
def login_json(req: LoginRequest, db: Session = Depends(get_db)):
    user = (
        db.query(models.User).filter(func.lower(models.User.username) == req.username.lower()).first()
    )
    if not user or not verify_password(req.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Benutzername oder Passwort falsch",
        )
    if user.totp_enabled:
        if not req.totp_code:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="2fa_required",
            )
        totp = pyotp.TOTP(user.totp_secret)
        if not totp.verify(req.totp_code, valid_window=1):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Ungültiger 2FA-Code",
            )
    expires = REMEMBER_ME_EXPIRY if req.remember_me else None
    token = create_access_token({"sub": user.username}, expires_delta=expires)
    return {"access_token": token, "token_type": "bearer", "user": _user_dict(user)}


@router.get("/me")
def me(current_user: models.User = Depends(get_current_user)):
    return {
        "id": current_user.id,
        "username": current_user.username,
        "display_name": current_user.display_name or current_user.username,
        "email": current_user.email,
        "is_admin": current_user.is_admin,
        "has_avatar": current_user.avatar_filename is not None,
        "totp_enabled": current_user.totp_enabled,
    }
