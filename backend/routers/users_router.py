from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

import models
from auth import get_current_admin, get_current_user, get_password_hash
from database import get_db

router = APIRouter()


class CreateUserRequest(BaseModel):
    username: str
    password: str
    email: Optional[str] = None
    is_admin: bool = False


class ChangePasswordRequest(BaseModel):
    password: str


def _user_dict(u: models.User) -> dict:
    return {"id": u.id, "username": u.username, "email": u.email, "is_admin": u.is_admin}


@router.get("/")
def list_users(
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_admin),
):
    return [_user_dict(u) for u in db.query(models.User).all()]


@router.post("/")
def create_user(
    req: CreateUserRequest,
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_admin),
):
    if db.query(models.User).filter(models.User.username == req.username).first():
        raise HTTPException(400, "Username already taken")
    user = models.User(
        username=req.username,
        email=req.email,
        password_hash=get_password_hash(req.password),
        is_admin=req.is_admin,
    )
    db.add(user)
    db.flush()
    db.add(models.UserSettings(user_id=user.id))
    db.commit()
    db.refresh(user)
    return _user_dict(user)


@router.delete("/{user_id}")
def delete_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_admin),
):
    if user_id == current_user.id:
        raise HTTPException(400, "Cannot delete yourself")
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")
    db.delete(user)
    db.commit()
    return {"ok": True}


@router.put("/{user_id}/password")
def change_password(
    user_id: int,
    req: ChangePasswordRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if not current_user.is_admin and current_user.id != user_id:
        raise HTTPException(403, "Not authorized")
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")
    user.password_hash = get_password_hash(req.password)
    db.commit()
    return {"ok": True}
