from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from pydantic import BaseModel
from sqlalchemy.orm import Session

import models
from auth import create_access_token, get_current_user, get_password_hash, verify_password
from database import get_db

router = APIRouter()


class SetupRequest(BaseModel):
    username: str
    password: str
    email: Optional[str] = None


def _user_dict(user: models.User) -> dict:
    return {"id": user.id, "username": user.username, "is_admin": user.is_admin}


@router.get("/setup-required")
def setup_required(db: Session = Depends(get_db)):
    return {"required": db.query(models.User).count() == 0}


@router.post("/setup")
def setup(req: SetupRequest, db: Session = Depends(get_db)):
    if db.query(models.User).count() > 0:
        raise HTTPException(400, "Setup already completed")
    user = models.User(
        username=req.username,
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
        db.query(models.User).filter(models.User.username == form_data.username).first()
    )
    if not user or not verify_password(form_data.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    token = create_access_token({"sub": user.username})
    return {"access_token": token, "token_type": "bearer", "user": _user_dict(user)}


@router.get("/me")
def me(current_user: models.User = Depends(get_current_user)):
    return {
        "id": current_user.id,
        "username": current_user.username,
        "email": current_user.email,
        "is_admin": current_user.is_admin,
    }
