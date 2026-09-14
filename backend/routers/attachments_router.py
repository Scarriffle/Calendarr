"""Upload, listing, download and deletion of event attachments.

Two routers live here:

``router``        mounted under /api/local, authenticated like the rest of the
                  API. Everything the web and mobile clients use.
``public_router`` mounted at root scope, NOT authenticated. Serves one
                  attachment by its capability token so external CalDAV clients
                  can follow the ATTACH URL in a generated ICS — they cannot
                  send a bearer token. See the README for the tradeoff.
"""

import os
from urllib.parse import quote

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import func
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

import attachments_store
import dav_util
import models
import permissions
from auth import get_current_user
from database import get_db

router = APIRouter()
public_router = APIRouter()

# Deployments that would rather lose attachments in external calendar clients
# than hand out unauthenticated URLs can set this to 0: the capability endpoint
# then 404s and no ATTACH line is emitted into any ICS.
PUBLIC_LINKS_ENABLED = os.environ.get("ATTACHMENT_PUBLIC_LINKS", "1") != "0"


def _to_dict(att: models.EventAttachment) -> dict:
    uploader = None
    if att.uploader is not None:
        uploader = {
            "id": att.uploader.id,
            "display_name": att.uploader.display_name or att.uploader.username,
        }
    return {
        "id": att.id,
        "filename": att.filename,
        "content_type": att.content_type,
        "size_bytes": att.size_bytes,
        "has_thumb": bool(att.has_thumb),
        "created_at": att.created_at.isoformat() if att.created_at else None,
        "uploaded_by": uploader,
        "url": f"/api/local/attachments/{att.id}",
        "thumb_url": f"/api/local/attachments/{att.id}/thumb" if att.has_thumb else None,
    }


def _writable_event(db: Session, user: models.User, uid: str) -> models.LocalEvent:
    """Attaching a file is editing the event, so it needs write on its calendar."""
    ev = db.query(models.LocalEvent).filter(models.LocalEvent.uid == uid).first()
    if not ev:
        raise HTTPException(404, "Event not found")
    permissions.accessible_local_calendar(db, user, ev.calendar_id, require_write=True)
    return ev


def _attachment_for_read(db: Session, user: models.User, att_id: int) -> models.EventAttachment:
    att = (
        db.query(models.EventAttachment)
        .filter(models.EventAttachment.id == att_id)
        .first()
    )
    if not att:
        raise HTTPException(404, "Attachment not found")
    permissions.readable_local_event(db, user, att.event_uid)
    return att


def _attachment_for_write(db: Session, user: models.User, att_id: int) -> models.EventAttachment:
    att = (
        db.query(models.EventAttachment)
        .filter(models.EventAttachment.id == att_id)
        .first()
    )
    if not att:
        raise HTTPException(404, "Attachment not found")
    _writable_event(db, user, att.event_uid)
    return att


def _download_response(att: models.EventAttachment) -> FileResponse:
    path = attachments_store.path_for(att.stored_name)
    if not path.exists():
        # Row without bytes: the sweep will reconcile it on its next run.
        raise HTTPException(404, "Attachment not found")
    # RFC 6266: an ASCII fallback plus the real UTF-8 name, so umlauts survive.
    ascii_name = "".join(
        c for c in att.filename if c.isalnum() or c in " -_."
    ).strip() or "anhang"
    disposition = (
        f'attachment; filename="{ascii_name}"; '
        f"filename*=UTF-8''{quote(att.filename)}"
    )
    return FileResponse(
        str(path),
        media_type=att.content_type,
        headers={
            # Always "attachment", never "inline": these are user-supplied bytes
            # served from the app's own origin, where the session token lives.
            "Content-Disposition": disposition,
            "X-Content-Type-Options": "nosniff",
            "Content-Security-Policy": "default-src 'none'; sandbox",
            "Cache-Control": "private, max-age=0, must-revalidate",
        },
    )


# ── Authenticated API ─────────────────────────────────────

@router.get("/events/{uid}/attachments")
def list_attachments(
    uid: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    ev = permissions.readable_local_event(db, current_user, uid)
    rows = (
        db.query(models.EventAttachment)
        .filter(models.EventAttachment.event_id == ev.id)
        .order_by(models.EventAttachment.id)
        .all()
    )
    return [_to_dict(a) for a in rows]


@router.post("/events/{uid}/attachments", status_code=201)
async def upload_attachment(
    uid: str,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    # Read one byte past the cap so an oversized upload is refused without ever
    # buffering it whole.
    raw = await file.read(attachments_store.MAX_ATTACHMENT_BYTES + 1)
    if len(raw) > attachments_store.MAX_ATTACHMENT_BYTES:
        raise HTTPException(413, "Datei zu groß (max. 10 MB)")
    if not raw:
        raise HTTPException(400, "Leere Datei")
    content_type, ext = attachments_store.sniff(raw, file.filename or "")

    ev = _writable_event(db, current_user, uid)
    stored_name = attachments_store.new_stored_name(ext)
    att = models.EventAttachment(
        source="local",
        event_uid=ev.uid,
        event_id=ev.id,
        filename=attachments_store.safe_filename(file.filename or "", ext),
        stored_name=stored_name,
        content_type=content_type,
        size_bytes=len(raw),
        has_thumb=False,
        token=attachments_store.new_token(),
        uploaded_by=current_user.id,
    )
    db.add(att)
    # Insert first, then count inside the same transaction. A count-then-insert
    # would be a TOCTOU: two uploads both see 9 and you end up with 11. SQLite
    # takes a write lock on the first INSERT, so this count is serialised and
    # includes our own row.
    db.flush()
    n = (
        db.query(func.count(models.EventAttachment.id))
        .filter(models.EventAttachment.event_id == ev.id)
        .scalar()
    )
    if n > attachments_store.MAX_ATTACHMENTS_PER_EVENT:
        db.rollback()
        raise HTTPException(
            409,
            f"Maximal {attachments_store.MAX_ATTACHMENTS_PER_EVENT} Anhänge pro Termin",
        )

    try:
        attachments_store.write_file(stored_name, raw)
        # Pillow on a 10 MB image is CPU-bound; keep it off the event loop.
        att.has_thumb = await run_in_threadpool(
            attachments_store.make_thumb, raw, content_type, stored_name
        )
        # The generated ICS gains an ATTACH line, so CalDAV clients must be told
        # the event changed or they will never re-fetch it.
        dav_util.bump_dav(ev.calendar, ev)
        db.commit()
    except Exception:
        db.rollback()
        attachments_store.unlink_all([
            attachments_store.path_for(stored_name),
            attachments_store.thumb_path_for(stored_name),
        ])
        raise
    db.refresh(att)
    return _to_dict(att)


@router.get("/attachments/{att_id}")
def download_attachment(
    att_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    return _download_response(_attachment_for_read(db, current_user, att_id))


@router.get("/attachments/{att_id}/thumb")
def attachment_thumbnail(
    att_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    att = _attachment_for_read(db, current_user, att_id)
    path = attachments_store.thumb_path_for(att.stored_name)
    if not att.has_thumb or not path.exists():
        raise HTTPException(404, "No thumbnail")
    return FileResponse(
        str(path),
        media_type="image/jpeg",
        headers={
            "X-Content-Type-Options": "nosniff",
            "Cache-Control": "private, max-age=0, must-revalidate",
        },
    )


@router.delete("/attachments/{att_id}")
def delete_attachment(
    att_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    att = _attachment_for_write(db, current_user, att_id)
    ev = db.query(models.LocalEvent).filter(models.LocalEvent.id == att.event_id).first()
    stale = attachments_store.files_of(att)
    db.delete(att)
    if ev is not None:
        dav_util.bump_dav(ev.calendar, ev)
    db.commit()
    attachments_store.unlink_all(stale)
    return {"ok": True}


# ── Capability URL for external CalDAV clients ────────────

@public_router.get("/api/attach/{token}")
@public_router.get("/api/attach/{token}/{name}")
def public_attachment(token: str, name: str = "", db: Session = Depends(get_db)):
    """Serve one attachment by its unguessable token, without authentication.

    Apple Calendar, Thunderbird and DAVx5 fetch an ICS ATTACH URL with a plain
    GET and no credentials, so this is the only shape that works for them. The
    trailing name is cosmetic — clients show it, the lookup ignores it.

    Never distinguish "wrong token" from "deleted": both are 404.
    """
    if not PUBLIC_LINKS_ENABLED:
        raise HTTPException(404, "Not found")
    att = (
        db.query(models.EventAttachment)
        .filter(models.EventAttachment.token == token)
        .first()
    )
    if not att:
        raise HTTPException(404, "Not found")
    return _download_response(att)
