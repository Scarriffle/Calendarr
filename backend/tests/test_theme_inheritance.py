"""Theme colours: a user without an own colour must inherit the admin default.

These five colours used to carry a hardcoded column default, which meant every
user row always held a concrete value — so the admin's instance default could
never apply to them, however it was configured.
"""

import models
from conftest import auth, create_user, register_admin
from database import SessionLocal

INHERITABLE = ["primary_color", "accent_color", "today_color",
               "month_divider_color", "month_label_color"]


def db_session():
    return SessionLocal()


def test_new_user_has_no_own_colours(client):
    """A fresh account inherits — nothing is baked into its row."""
    admin_token = register_admin(client, "admin", "pw")
    uid, token = create_user(client, admin_token, "hugo")

    with db_session() as db:
        s = db.query(models.UserSettings).filter(
            models.UserSettings.user_id == uid).one()
        for col in INHERITABLE:
            assert getattr(s, col) is None, f"{col} should inherit, got {getattr(s, col)!r}"

    body = client.get("/api/settings/", headers=auth(token)).json()
    for col in INHERITABLE:
        assert body[col] is None


def test_setup_admin_also_inherits(client):
    """The first-run admin is created on a different code path."""
    token = register_admin(client, "admin", "pw")
    body = client.get("/api/settings/", headers=auth(token)).json()
    for col in INHERITABLE:
        assert body[col] is None


def test_choosing_a_colour_is_stored(client):
    admin_token = register_admin(client, "admin", "pw")
    _, token = create_user(client, admin_token, "hugo")

    r = client.put("/api/settings/", headers=auth(token),
                   json={"primary_color": "#58B900"})
    assert r.status_code == 200, r.text
    assert client.get("/api/settings/", headers=auth(token)).json()["primary_color"] == "#58B900"


def test_reset_clears_back_to_inheriting(client):
    """The reset button sends null, and null has to persist — otherwise
    "reset" would just freeze today's admin default into the user's row."""
    admin_token = register_admin(client, "admin", "pw")
    _, token = create_user(client, admin_token, "hugo")

    client.put("/api/settings/", headers=auth(token), json={"primary_color": "#58B900"})
    r = client.put("/api/settings/", headers=auth(token), json={"primary_color": None})
    assert r.status_code == 200, r.text
    assert client.get("/api/settings/", headers=auth(token)).json()["primary_color"] is None


def test_unrelated_save_does_not_invent_a_colour(client):
    """Saving some other setting must not write a colour into the row."""
    admin_token = register_admin(client, "admin", "pw")
    _, token = create_user(client, admin_token, "hugo")

    client.put("/api/settings/", headers=auth(token), json={"week_start_day": "sunday"})
    body = client.get("/api/settings/", headers=auth(token)).json()
    assert body["week_start_day"] == "sunday"
    for col in INHERITABLE:
        assert body[col] is None
