"""On-disk storage and validation for event attachments.

Files live under ``DATA_DIR/attachments``, sharded by the first two characters
of a server-generated name::

    DATA_DIR/attachments/a1/a1b2....pdf           the file
    DATA_DIR/attachments/a1/a1b2....thumb.jpg     thumbnail, images only

Nothing here ever builds a path from user input. That is not caution for its
own sake: for events created through CalDAV even the event UID comes straight
from an external client (``dav_router._handle_put``), so neither the UID nor
the uploaded filename may reach the filesystem. The original name lives only in
``EventAttachment.filename`` and is re-attached on download.

The ORM cascade on ``LocalEvent.attachments`` removes attachment ROWS when an
event goes away, but it can never remove files. ``purge_for_events`` is the
helper every explicit delete path calls; ``sweep`` is the safety net for the
paths where a request died halfway or where someone adds a delete path later
and forgets the helper.
"""

import io
import logging
import secrets
import time
import uuid
from pathlib import Path
from typing import Iterable

from fastapi import HTTPException
from PIL import Image
from sqlalchemy import func
from sqlalchemy.orm import Session

import models
from database import DATA_DIR

logger = logging.getLogger(__name__)

ATTACH_DIR = DATA_DIR / "attachments"
ATTACH_DIR.mkdir(parents=True, exist_ok=True)

MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024  # 10 MB
MAX_ATTACHMENTS_PER_EVENT = 10
THUMB_SIZE = (320, 320)
# Pillow only warns above its own limit, so guard explicitly: a 200-byte PNG
# can declare a 60000x60000 canvas and cost gigabytes to decode.
MAX_IMAGE_PIXELS = 50_000_000

# Pillow format -> (content type, extension). Deliberately NOT a general image
# allowlist: SVG is an XML document that runs script in the app's own origin,
# where the session token lives in localStorage. An uploaded SVG or HTML file
# served back to another user would be account takeover, and the calendar
# sharing feature would deliver it. Do not widen this without re-reading that.
_IMAGE_FORMATS = {
    "PNG": ("image/png", ".png"),
    "JPEG": ("image/jpeg", ".jpg"),
    "WEBP": ("image/webp", ".webp"),
    "GIF": ("image/gif", ".gif"),
}
_IMAGE_CONTENT_TYPES = {ct for ct, _ in _IMAGE_FORMATS.values()}

# Text subtypes are picked from the uploaded name's extension, but only after
# the BYTES were confirmed to be text — the extension alone decides nothing
# about whether the upload is accepted.
_TEXT_TYPES = {
    ".txt": "text/plain",
    ".md": "text/markdown",
    ".markdown": "text/markdown",
    ".csv": "text/csv",
}

# How long a file is left alone before the sweep may call it an orphan. Without
# this the sweep races an upload in progress: the bytes are written before the
# row is committed, and a sweep landing in between would delete a good file.
SWEEP_GRACE_SECONDS = 3600


def sniff(raw: bytes, filename: str) -> tuple[str, str]:
    """Determine ``(content_type, extension)`` from the BYTES.

    The client's Content-Type header is never read — it is trivially forged,
    and unlike the avatar upload there is no Pillow re-encode downstream that
    would neutralise a mislabelled file. Raises 400 for anything off the
    allowlist.
    """
    if raw.startswith(b"%PDF-"):
        return "application/pdf", ".pdf"

    fmt = None
    try:
        probe = Image.open(io.BytesIO(raw))
        w, h = probe.size
        if w * h <= MAX_IMAGE_PIXELS:
            probe.verify()  # verify() consumes the object; reopen to use it
            fmt = probe.format
    except Exception:
        fmt = None
    if fmt in _IMAGE_FORMATS:
        return _IMAGE_FORMATS[fmt]

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = None
    if text is not None and "\x00" not in text:
        # Both halves must agree: the bytes have to BE text, and the name has to
        # claim one of the three text kinds we accept. Without the extension
        # check anything UTF-8 would slip through as text/plain — an .html or
        # .svg upload would be stored (harmlessly, as text/plain) rather than
        # refused, which is not what "TXT, Markdown, CSV" promises the user.
        ext = Path(filename or "").suffix.lower()
        if ext in _TEXT_TYPES:
            return _TEXT_TYPES[ext], ext

    raise HTTPException(400, "Dateityp nicht erlaubt (PDF, Bild oder Textdatei)")


def safe_filename(raw_name: str, ext: str) -> str:
    """Strip any directory part and control characters from an uploaded name.

    Only ever used as a label (download header, ICS FILENAME parameter) — never
    as a path — but a name carrying quotes or newlines would break the headers
    it is spliced into.
    """
    name = Path(raw_name or "").name
    name = "".join(c for c in name if c.isprintable() and c not in '"\\/\r\n')
    name = name.strip()[:120]
    return name or f"anhang{ext}"


def path_for(stored_name: str) -> Path:
    return ATTACH_DIR / stored_name[:2] / stored_name


def thumb_path_for(stored_name: str) -> Path:
    stem = stored_name.split(".", 1)[0]
    return ATTACH_DIR / stem[:2] / f"{stem}.thumb.jpg"


def new_token() -> str:
    """Capability token for the unauthenticated ICS ATTACH URL (256 bits)."""
    return secrets.token_urlsafe(32)


def new_stored_name(ext: str) -> str:
    return f"{uuid.uuid4().hex}{ext}"


def write_file(stored_name: str, raw: bytes) -> Path:
    path = path_for(stored_name)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(raw)
    return path


def make_thumb(raw: bytes, content_type: str, stored_name: str) -> bool:
    """Render a small JPEG preview for images. CPU-bound — call off the loop."""
    if content_type not in _IMAGE_CONTENT_TYPES:
        return False
    try:
        img = Image.open(io.BytesIO(raw))
        img.thumbnail(THUMB_SIZE)
        target = thumb_path_for(stored_name)
        target.parent.mkdir(parents=True, exist_ok=True)
        img.convert("RGB").save(str(target), "JPEG", quality=82)
        return True
    except Exception:
        # A thumbnail is a nicety; a broken one must not fail the upload.
        logger.warning("Could not build thumbnail for %s", stored_name)
        return False


def unlink_all(paths: Iterable[Path]) -> None:
    """Best-effort removal. Call this only AFTER the transaction committed."""
    for p in paths:
        try:
            p.unlink()
        except FileNotFoundError:
            pass
        except OSError:
            logger.warning("Could not remove attachment file %s", p)


def files_of(row: "models.EventAttachment") -> list[Path]:
    paths = [path_for(row.stored_name)]
    if row.has_thumb:
        paths.append(thumb_path_for(row.stored_name))
    return paths


def purge_for_events(db: Session, event_ids: Iterable[int]) -> list[Path]:
    """Delete attachment ROWS for these local events; return the files to unlink.

    The caller unlinks only after committing. Removing the bytes first would
    lose data if the surrounding transaction then rolled back — the row would
    come back pointing at a file that no longer exists.
    """
    ids = [i for i in event_ids if i is not None]
    if not ids:
        return []
    rows = (
        db.query(models.EventAttachment)
        .filter(models.EventAttachment.event_id.in_(ids))
        .all()
    )
    paths: list[Path] = []
    for row in rows:
        paths.extend(files_of(row))
        db.delete(row)
    return paths


def purge_for_calendars(db: Session, calendar_ids: Iterable[int]) -> list[Path]:
    """Same, for every event in the given local calendars."""
    ids = [i for i in calendar_ids if i is not None]
    if not ids:
        return []
    event_ids = [
        r[0]
        for r in db.query(models.LocalEvent.id)
        .filter(models.LocalEvent.calendar_id.in_(ids))
        .all()
    ]
    return purge_for_events(db, event_ids)


def counts_for_events(db: Session, event_ids: Iterable[int]) -> dict[int, int]:
    """Attachment count per event id, in ONE query.

    The merged event read loops over every event; a lazy relationship there
    would be one extra query per event across a whole month view.
    """
    ids = [i for i in event_ids if i is not None]
    if not ids:
        return {}
    rows = (
        db.query(models.EventAttachment.event_id, func.count(models.EventAttachment.id))
        .filter(models.EventAttachment.event_id.in_(ids))
        .group_by(models.EventAttachment.event_id)
        .all()
    )
    return {event_id: n for event_id, n in rows}


def sweep(db: Session) -> tuple[int, int]:
    """Drop attachments whose event is gone, and files with no row.

    Returns ``(rows_removed, files_removed)``. Both directions are needed
    because the failure modes differ: an event removed through a cascade that
    skipped the purge helper leaves rows behind, while a crash mid-upload
    leaves a file behind.
    """
    live_ids = {r[0] for r in db.query(models.LocalEvent.id).all()}
    stale_paths: list[Path] = []
    rows_removed = 0
    for row in db.query(models.EventAttachment).filter(
        models.EventAttachment.source == "local"
    ):
        if row.event_id is None or row.event_id not in live_ids:
            stale_paths.extend(files_of(row))
            db.delete(row)
            rows_removed += 1
    if rows_removed:
        db.commit()
        unlink_all(stale_paths)

    known = {
        r[0].split(".", 1)[0]
        for r in db.query(models.EventAttachment.stored_name).all()
    }
    cutoff = time.time() - SWEEP_GRACE_SECONDS
    files_removed = 0
    for path in ATTACH_DIR.rglob("*"):
        if not path.is_file():
            continue
        if path.name.split(".", 1)[0] in known:
            continue
        try:
            if path.stat().st_mtime > cutoff:
                continue  # inside the grace window; an upload may still own it
            path.unlink()
            files_removed += 1
        except OSError:
            logger.warning("Could not remove orphaned attachment file %s", path)

    if rows_removed or files_removed:
        logger.info(
            "Attachment sweep: removed %d orphaned row(s), %d orphaned file(s)",
            rows_removed,
            files_removed,
        )
    return rows_removed, files_removed
