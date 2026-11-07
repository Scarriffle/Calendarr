"""Reminder defaults, and the zero that used to vanish.

NULLABLE_OVERRIDES applied `value or None`, so 0 was stored as NULL — "at start
time" and "same day" both silently meant "off". That is the setting birthdays
need most, so it has a test.
"""

import models
from conftest import auth, register_admin
from database import SessionLocal


def _settings(client, token):
    return client.get("/api/settings/", headers=auth(token)).json()


def test_zero_is_stored_not_swallowed(client):
    token = register_admin(client)
    client.put("/api/settings/", json={"default_reminder_minutes": 0}, headers=auth(token))

    assert _settings(client, token)["default_reminder_minutes"] == 0
    db = SessionLocal()
    try:
        assert db.query(models.UserSettings).one().default_reminder_minutes == 0
    finally:
        db.close()


def test_same_day_all_day_reminder_is_stored(client):
    token = register_admin(client)
    client.put("/api/settings/", json={"allday_reminder_days": 0}, headers=auth(token))
    assert _settings(client, token)["allday_reminder_days"] == 0


def test_null_still_means_off(client):
    token = register_admin(client)
    client.put("/api/settings/", json={"allday_reminder_days": 3}, headers=auth(token))
    client.put("/api/settings/", json={"allday_reminder_days": None}, headers=auth(token))
    assert _settings(client, token)["allday_reminder_days"] is None


def test_all_day_time_defaults_to_nine(client):
    token = register_admin(client)
    assert _settings(client, token)["allday_reminder_time"] == "09:00"

    client.put("/api/settings/", json={"allday_reminder_time": "07:30"}, headers=auth(token))
    assert _settings(client, token)["allday_reminder_time"] == "07:30"


def test_both_settings_are_syncable(client):
    token = register_admin(client)
    flags = _settings(client, token)["sync_flags"]
    assert flags["allday_reminder_days"] is True
    assert flags["allday_reminder_time"] is True
