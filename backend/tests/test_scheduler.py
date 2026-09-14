"""The in-process job scheduler and its two jobs."""

import time

import models
import scheduler
from conftest import auth, register_admin
from database import SessionLocal


def _run(fn):
    db = SessionLocal()
    try:
        fn(db)
    finally:
        db.close()


def test_default_jobs_are_registered_with_sane_intervals():
    scheduler.install_default_jobs()
    names = {j.name: j for j in scheduler._jobs}
    assert set(names) == {"attachments.sweep", "ical.refresh"}
    assert names["attachments.sweep"].interval == 24 * 3600
    assert names["ical.refresh"].interval == 15 * 60
    # Nothing runs immediately: a restart must not be slowed by maintenance.
    assert all(j.next_run > time.monotonic() for j in scheduler._jobs)


def test_registering_the_same_name_twice_replaces_it():
    scheduler.register("demo", 60, lambda db: None)
    scheduler.register("demo", 120, lambda db: None)
    matching = [j for j in scheduler._jobs if j.name == "demo"]
    assert len(matching) == 1 and matching[0].interval == 120
    scheduler._jobs[:] = [j for j in scheduler._jobs if j.name != "demo"]


def test_a_failing_job_is_contained(caplog):
    """One broken job must not take down the loop or the other jobs."""
    def boom(db):
        raise RuntimeError("kaputt")

    job = scheduler._Job("explodes", 60, boom)
    scheduler._run_job(job)  # must not raise
    assert "explodes" in caplog.text


def test_sweep_job_cleans_an_orphaned_row(client):
    """End-to-end through the job function, not just the store helper."""
    token = register_admin(client)
    r = client.post("/api/local/calendars", headers=auth(token),
                    json={"name": "Privat", "color": "#4285f4"})
    cal_id = r.json()["id"]
    ev = client.post("/api/local/events", headers=auth(token), json={
        "calendar_id": cal_id, "title": "Termin",
        "start": "2026-06-10T10:00:00+00:00", "end": "2026-06-10T11:00:00+00:00",
    }).json()
    client.post(f"/api/local/events/{ev['id']}/attachments", headers=auth(token),
                files={"file": ("x.pdf", b"%PDF-1.4\ntrailer\n", "application/pdf")})

    db = SessionLocal()
    ev_row = db.query(models.LocalEvent).filter(models.LocalEvent.uid == ev["id"]).first()
    db.query(models.LocalEvent).filter(models.LocalEvent.id == ev_row.id).delete()
    db.commit()
    db.close()

    _run(scheduler.sweep_attachments)

    db = SessionLocal()
    assert db.query(models.EventAttachment).count() == 0
    db.close()


def test_ical_job_survives_an_unreachable_subscription(client):
    """A subscription with no cached data makes _refresh_if_needed re-raise —
    the job has to wrap each one separately or a single bad URL stops the rest."""
    token = register_admin(client)
    db = SessionLocal()
    user = db.query(models.User).first()
    db.add(models.ICalSubscription(
        user_id=user.id, name="Kaputt",
        url="http://127.0.0.1:9/nicht-erreichbar.ics",
        color="#ea4335", enabled=True, refresh_minutes=60,
    ))
    db.commit()
    db.close()

    _run(scheduler.refresh_ical_subscriptions)  # must not raise


def test_the_loop_runs_due_jobs_and_stops_with_the_app(monkeypatch):
    """Drive the real lifespan with a fast tick and a probe job."""
    from fastapi.testclient import TestClient

    import main

    monkeypatch.setattr(scheduler, "TICK_SECONDS", 0.02)
    monkeypatch.setattr(scheduler, "FIRST_RUN_DELAY_SECONDS", 0)
    ran = []
    scheduler.register("probe", 3600, lambda db: ran.append(1))
    try:
        with TestClient(main.app):  # entering runs the lifespan
            deadline = time.time() + 3
            while not ran and time.time() < deadline:
                time.sleep(0.02)
        assert ran, "the scheduler loop never ran the registered job"
    finally:
        scheduler._jobs[:] = [j for j in scheduler._jobs if j.name != "probe"]


def test_plain_test_client_starts_no_background_work():
    """conftest builds TestClient without a context manager, so the lifespan —
    and with it the loop — never starts. Keeps the rest of the suite free of
    background jobs touching the same database."""
    from fastapi.testclient import TestClient

    import main

    before = len(scheduler._jobs)
    TestClient(main.app)
    assert len(scheduler._jobs) == before
