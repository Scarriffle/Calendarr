from datetime import datetime, timedelta
from typing import Optional

import pyotp
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session

import models
from auth import create_user_token, get_current_user, get_password_hash, verify_password
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


MAX_FAILED_LOGINS = 10
LOCKOUT = timedelta(minutes=15)


def _check_not_locked(user: Optional[models.User]) -> None:
    """429 while an account is locked out. Called before the password check so
    a locked account costs an attacker a bcrypt-free round trip."""
    if user is None or not user.locked_until:
        return
    try:
        until = datetime.fromisoformat(user.locked_until)
    except ValueError:
        return
    if until > datetime.utcnow():
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Zu viele Fehlversuche. Bitte später erneut versuchen.",
        )


def _note_failure(user: Optional[models.User], db: Session) -> None:
    """Count a wrong password or a wrong 2FA code — both gate the same account."""
    if user is None:
        return      # no such user: nothing to count, and nothing to reveal
    user.failed_logins = (user.failed_logins or 0) + 1
    if user.failed_logins >= MAX_FAILED_LOGINS:
        user.locked_until = (datetime.utcnow() + LOCKOUT).isoformat()
        user.failed_logins = 0
    db.commit()


def _note_success(user: models.User, db: Session) -> None:
    if user.failed_logins or user.locked_until:
        user.failed_logins = 0
        user.locked_until = None
        db.commit()


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
    token = create_user_token(user)
    return {"access_token": token, "token_type": "bearer", "user": _user_dict(user)}


@router.post("/token")
def login(
    form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)
):
    user = (
        db.query(models.User).filter(func.lower(models.User.username) == form_data.username.lower()).first()
    )
    _check_not_locked(user)
    if not user or not verify_password(form_data.password, user.password_hash):
        _note_failure(user, db)
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
    _note_success(user, db)
    token = create_user_token(user)
    return {"access_token": token, "token_type": "bearer", "user": _user_dict(user)}


@router.post("/login")
def login_json(req: LoginRequest, db: Session = Depends(get_db)):
    user = (
        db.query(models.User).filter(func.lower(models.User.username) == req.username.lower()).first()
    )
    _check_not_locked(user)
    if not user or not verify_password(req.password, user.password_hash):
        _note_failure(user, db)
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
            # Counts against the same budget: with valid_window=1 three codes
            # are live at once, so the second factor needs the limit too.
            _note_failure(user, db)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Ungültiger 2FA-Code",
            )
    _note_success(user, db)
    expires = REMEMBER_ME_EXPIRY if req.remember_me else None
    token = create_user_token(user, expires_delta=expires)
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
