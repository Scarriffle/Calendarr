"""A small in-process scheduler for periodic maintenance jobs.

The server runs as a single uvicorn process (``main.py`` calls ``uvicorn.run``
with no ``workers=``), so an in-process loop runs exactly once — no locking or
leader election needed. If the deployment ever grows to multiple workers this
has to be revisited, because every worker would run every job.

Jobs are plain synchronous callables taking a ``Session``. They run in a worker
thread with their own session: SQLAlchemy is synchronous here, and a job doing
file I/O or an HTTP fetch on the event loop would stall every request.

Failures are caught per job, so a broken iCal feed cannot stop the attachment
sweep and neither can stop the loop.

Environment:
    SCHEDULER_ENABLED           "0" disables the loop entirely (default on)
    ATTACHMENT_SWEEP_HOURS      how often orphaned attachments are cleaned (24)
    ICAL_REFRESH_MINUTES        how often subscriptions are checked (15)
"""

import asyncio
import contextlib
import logging
import os
import time
from contextlib import asynccontextmanager
from typing import Callable

from sqlalchemy.orm import Session

from database import SessionLocal

logger = logging.getLogger(__name__)

ENABLED = os.environ.get("SCHEDULER_ENABLED", "1") != "0"
# How often the loop wakes to see whether anything is due. Jobs have their own,
# much longer intervals; this only bounds how late a job can start.
TICK_SECONDS = 30
# Delay before the first run so a restart is not slowed by maintenance work.
FIRST_RUN_DELAY_SECONDS = 20


class _Job:
    def __init__(self, name: str, interval: float, fn: Callable[[Session], None]):
        self.name = name
        self.interval = interval
        self.fn = fn
        self.next_run = time.monotonic() + FIRST_RUN_DELAY_SECONDS


_jobs: list[_Job] = []


def register(name: str, interval_seconds: float, fn: Callable[[Session], None]) -> None:
    """Add a job. Registering the same name twice replaces the first."""
    _jobs[:] = [j for j in _jobs if j.name != name]
    _jobs.append(_Job(name, interval_seconds, fn))


def _run_job(job: _Job) -> None:
    """Run one job in a worker thread, with its own session."""
    db = SessionLocal()
    try:
        job.fn(db)
    except Exception:
        # Never let one job's failure escape: the loop must survive it, and so
        # must the other jobs.
        logger.exception("Scheduled job %s failed", job.name)
        with contextlib.suppress(Exception):
            db.rollback()
    finally:
        db.close()


async def _runner() -> None:
    logger.info(
        "Scheduler started with %d job(s): %s",
        len(_jobs),
        ", ".join(j.name for j in _jobs),
    )
    while True:
        await asyncio.sleep(TICK_SECONDS)
        now = time.monotonic()
        for job in list(_jobs):
            if now < job.next_run:
                continue
            job.next_run = now + job.interval
            await asyncio.to_thread(_run_job, job)


# ── The jobs ──────────────────────────────────────────────

def sweep_attachments(db: Session) -> None:
    """Remove attachment rows whose event is gone, and files with no row.

    The explicit purge at each delete path is the normal mechanism; this is the
    safety net for what slips past it — an external CalDAV client deleting an
    event, a request that died between writing the file and committing the row,
    or a delete path added later that forgets the helper.
    """
    import attachments_store

    attachments_store.sweep(db)


def refresh_ical_subscriptions(db: Session) -> None:
    """Re-fetch iCal subscriptions that are due.

    ``_refresh_if_needed`` already honours each subscription's own
    ``refresh_minutes`` and swallows network errors — except when a
    subscription has no cached data at all, where it re-raises. So every
    subscription is wrapped separately: one unreachable URL must not stop the
    rest.

    The lazy refresh in the merged read stays as it is. This only adds the case
    nobody was covering: keeping subscriptions current while no one has the app
    open.
    """
    import models
    from routers.ical_router import _refresh_if_needed

    subs = (
        db.query(models.ICalSubscription)
        .filter(models.ICalSubscription.enabled == True)  # noqa: E712
        .all()
    )
    for sub in subs:
        try:
            _refresh_if_needed(sub, db)
        except Exception:
            logger.warning("Scheduled refresh of iCal subscription %s failed", sub.id)
            with contextlib.suppress(Exception):
                db.rollback()


def install_default_jobs() -> None:
    sweep_hours = float(os.environ.get("ATTACHMENT_SWEEP_HOURS", "24"))
    ical_minutes = float(os.environ.get("ICAL_REFRESH_MINUTES", "15"))
    register("attachments.sweep", sweep_hours * 3600, sweep_attachments)
    register("ical.refresh", ical_minutes * 60, refresh_ical_subscriptions)


@asynccontextmanager
async def lifespan(app):
    task = None
    if ENABLED:
        install_default_jobs()
        task = asyncio.create_task(_runner())
    else:
        logger.info("Scheduler disabled via SCHEDULER_ENABLED=0")
    try:
        yield
    finally:
        if task is not None:
            task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await task
