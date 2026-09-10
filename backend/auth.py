from datetime import datetime, timedelta
from typing import Optional
from jose import JWTError, jwt
import bcrypt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
import os

import models
from database import get_db

SECRET_KEY = os.environ.get(
    "SECRET_KEY", "insecure-default-key-change-in-production-use-env-var"
)
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 7 days

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/token")


def verify_password(plain: str, hashed: str) -> bool:
    # bcrypt.checkpw raises ValueError when `hashed` is not a well-formed hash
    # (empty string, a sentinel like "!", a truncated column). Uncaught, that
    # became an HTTP 500 on /api/auth/login and on every CalDAV Basic-Auth
    # attempt in dav_router. A malformed hash simply means "no password".
    try:
        return bcrypt.checkpw(plain.encode("utf-8"), hashed.encode("utf-8"))
    except (ValueError, TypeError):
        return False


def get_password_hash(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + (
        expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    to_encode["exp"] = expire
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def create_user_token(user: "models.User", expires_delta: Optional[timedelta] = None) -> str:
    """Session token for a user.

    ``uid`` is the authoritative subject: the immutable row id. ``sub`` keeps
    the username for readability and for tokens issued before ``uid`` existed,
    but it is not what identifies the account — otherwise renaming a user would
    silently invalidate every session on their other devices, and an identity
    provider that changes a name would break the mapping.
    """
    return create_access_token({"sub": user.username, "uid": user.id}, expires_delta)


def get_current_user(
    token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)
) -> models.User:
    exc = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        # Other short-lived tokens are signed with the same key (e.g. the OIDC
        # flow token); only a real access token may authenticate a request.
        if payload.get("typ") not in (None, "access"):
            raise exc
        uid = payload.get("uid")
        username: str = payload.get("sub")
        if uid is None and not username:
            raise exc
    except JWTError:
        raise exc

    if uid is not None:
        user = db.query(models.User).filter(models.User.id == uid).first()
    else:
        # Legacy token issued before uid existed. "Remember me" runs for 180
        # days, so these stay in circulation for a while.
        user = db.query(models.User).filter(models.User.username == username).first()
    if not user:
        raise exc
    return user


def get_current_admin(
    current_user: models.User = Depends(get_current_user),
) -> models.User:
    if not current_user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")
    return current_user
