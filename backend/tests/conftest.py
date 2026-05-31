"""Pytest fixtures: an isolated app + temp SQLite DB, wiped between tests."""

import os
import sys
import tempfile
from pathlib import Path

# Use a throwaway data dir BEFORE importing the app (database.py reads DATA_DIR
# at import time and builds the engine from it).
os.environ.setdefault("DATA_DIR", tempfile.mkdtemp(prefix="calendarr-test-"))
os.environ.setdefault("SECRET_KEY", "test-secret-key")

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

import pytest
from fastapi.testclient import TestClient

import main  # noqa: E402  (creates tables + runs migrations against the temp DB)
import models  # noqa: E402
from database import engine  # noqa: E402


@pytest.fixture
def client():
    return TestClient(main.app)


@pytest.fixture(autouse=True)
def clean_db():
    """Wipe every table before each test for isolation."""
    with engine.begin() as conn:
        for table in reversed(models.Base.metadata.sorted_tables):
            conn.execute(table.delete())
    yield


# ── Helpers ───────────────────────────────────────────────

def register_admin(client, username="admin", password="pw"):
    r = client.post("/api/auth/setup", json={"username": username, "password": password})
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


def create_user(client, admin_token, username, password="pw"):
    r = client.post(
        "/api/users/",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"username": username, "password": password},
    )
    assert r.status_code == 200, r.text
    uid = r.json()["id"]
    # Log in to get the user's own token.
    r2 = client.post("/api/auth/login", json={"username": username, "password": password})
    assert r2.status_code == 200, r2.text
    return uid, r2.json()["access_token"]


def auth(token):
    return {"Authorization": f"Bearer {token}"}
