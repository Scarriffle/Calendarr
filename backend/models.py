from sqlalchemy import Column, Integer, String, Boolean, ForeignKey
from sqlalchemy.orm import relationship
from database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, nullable=False)
    email = Column(String(100), unique=True, nullable=True)
    password_hash = Column(String(255), nullable=False)
    is_admin = Column(Boolean, default=False)
    avatar_filename = Column(String(255), nullable=True)
    totp_secret = Column(String(32), nullable=True)
    totp_enabled = Column(Boolean, default=False)

    caldav_accounts = relationship(
        "CalDAVAccount", back_populates="user", cascade="all, delete-orphan"
    )
    settings = relationship(
        "UserSettings", back_populates="user", uselist=False, cascade="all, delete-orphan"
    )


class CalDAVAccount(Base):
    __tablename__ = "caldav_accounts"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    name = Column(String(100), nullable=False)
    url = Column(String(500), nullable=False)
    username = Column(String(100), nullable=False)
    password = Column(String(255), nullable=False)
    color = Column(String(7), default="#4285f4")
    enabled = Column(Boolean, default=True)

    user = relationship("User", back_populates="caldav_accounts")
    calendars = relationship(
        "Calendar", back_populates="account", cascade="all, delete-orphan"
    )


class Calendar(Base):
    __tablename__ = "calendars"

    id = Column(Integer, primary_key=True, index=True)
    account_id = Column(Integer, ForeignKey("caldav_accounts.id"), nullable=False)
    cal_id = Column(String(500), nullable=False)
    name = Column(String(100), nullable=False)
    color = Column(String(7), nullable=True)
    enabled = Column(Boolean, default=True)

    account = relationship("CalDAVAccount", back_populates="calendars")


class UserSettings(Base):
    __tablename__ = "user_settings"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), unique=True, nullable=False)
    default_view = Column(String(20), default="month")
    primary_color = Column(String(7), default="#4285f4")
    accent_color = Column(String(7), default="#ea4335")
    today_color = Column(String(7), default="#4285f4")
    dim_past_events = Column(Boolean, default=False)

    user = relationship("User", back_populates="settings")
