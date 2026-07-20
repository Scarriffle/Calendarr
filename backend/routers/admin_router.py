"""Instance-wide (singleton) settings: an admin-defined default theme plus a
custom logo and favicon. The GET endpoint is public (needed on the login screen,
before auth); all writes require admin. Branding files are stored under
DATA_DIR/branding and served via FileResponse, mirroring the avatar pattern."""

import io
import json
import re
from typing import Optional

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from PIL import Image
from pydantic import BaseModel
from sqlalchemy.orm import Session

import models
from auth import get_current_admin
from database import DATA_DIR, get_db

router = APIRouter()

BRANDING_DIR = DATA_DIR / "branding"
BRANDING_DIR.mkdir(parents=True, exist_ok=True)
MAX_BRANDING_SIZE = 5 * 1024 * 1024  # 5 MB
ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp"}

# Colour keys an admin may set as the instance default theme. Keep in sync with
# the client's DEFAULT_COLORS / DEFAULT_SYNC colour keys (settings-sync.js).
THEME_COLOR_KEYS = {
    "primary_color", "accent_color", "today_color", "text_color", "bg_color",
    "line_color", "surface_color", "month_divider_color", "month_label_color",
    "hover_highlight_color", "icon_inactive_color", "icon_active_color",
    "day_hover_color", "day_selected_color", "day_bg_color", "today_bg_color",
}
HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")


def _get_or_create(db: Session) -> models.InstanceSettings:
    inst = db.query(models.InstanceSettings).filter(models.InstanceSettings.id == 1).first()
    if not inst:
        inst = models.InstanceSettings(id=1)
        db.add(inst)
        db.commit()
        db.refresh(inst)
    return inst


def _mtime(filename: Optional[str]) -> int:
    if not filename:
        return 0
    p = BRANDING_DIR / filename
    try:
        return int(p.stat().st_mtime)
    except OSError:
        return 0


def _public_dict(inst: models.InstanceSettings) -> dict:
    theme = {}
    if inst.default_theme:
        try:
            theme = json.loads(inst.default_theme) or {}
        except (ValueError, TypeError):
            theme = {}
    has_logo = bool(inst.logo_filename) and (BRANDING_DIR / (inst.logo_filename or "")).exists()
    has_favicon = bool(inst.favicon_filename) and (BRANDING_DIR / (inst.favicon_filename or "")).exists()
    return {
        "default_theme": theme,
        "has_logo": has_logo,
        "has_favicon": has_favicon,
        # Cache-busted URLs so a freshly uploaded asset is fetched immediately.
        "logo_url": f"/api/instance/logo?v={_mtime(inst.logo_filename)}" if has_logo else None,
        "favicon_url": f"/api/instance/favicon?v={_mtime(inst.favicon_filename)}" if has_favicon else None,
    }


# ── Public read ───────────────────────────────────────────
@router.get("/")
def get_instance(db: Session = Depends(get_db)):
    return _public_dict(_get_or_create(db))


@router.get("/logo")
def get_logo(db: Session = Depends(get_db)):
    inst = _get_or_create(db)
    if not inst.logo_filename:
        raise HTTPException(404, "No logo")
    path = BRANDING_DIR / inst.logo_filename
    if not path.exists():
        raise HTTPException(404, "No logo")
    return FileResponse(str(path), headers={"Cache-Control": "no-cache"})


@router.get("/favicon")
def get_favicon(db: Session = Depends(get_db)):
    inst = _get_or_create(db)
    if not inst.favicon_filename:
        raise HTTPException(404, "No favicon")
    path = BRANDING_DIR / inst.favicon_filename
    if not path.exists():
        raise HTTPException(404, "No favicon")
    return FileResponse(str(path), headers={"Cache-Control": "no-cache"})


# ── Admin writes ──────────────────────────────────────────
class ThemeUpdate(BaseModel):
    default_theme: dict  # {colorKey: "#RRGGBB"}; empty = reset to built-in


@router.put("/theme")
def set_default_theme(
    data: ThemeUpdate,
    db: Session = Depends(get_db),
    admin: models.User = Depends(get_current_admin),
):
    # Keep only known colour keys with valid hex values.
    clean = {
        k: v.upper()
        for k, v in (data.default_theme or {}).items()
        if k in THEME_COLOR_KEYS and isinstance(v, str) and HEX_RE.match(v)
    }
    inst = _get_or_create(db)
    inst.default_theme = json.dumps(clean) if clean else None
    db.commit()
    return {"ok": True, "default_theme": clean}


async def _save_branding(file: UploadFile, kind: str) -> str:
    """Validate + normalise an uploaded image and store it. Returns the filename."""
    if file.content_type not in ALLOWED_TYPES:
        raise HTTPException(400, "Only JPEG, PNG or WebP allowed")
    raw = await file.read()
    if len(raw) > MAX_BRANDING_SIZE:
        raise HTTPException(400, "File too large (max 5 MB)")
    try:
        img = Image.open(io.BytesIO(raw)).convert("RGBA")
    except Exception:
        raise HTTPException(400, "Invalid image")
    if kind == "favicon":
        img = img.resize((128, 128), Image.LANCZOS)
    else:  # logo: keep aspect ratio, cap the longest edge at 256px
        img.thumbnail((256, 256), Image.LANCZOS)
    filename = f"{kind}.png"
    img.save(str(BRANDING_DIR / filename), "PNG")
    return filename


@router.post("/logo")
async def upload_logo(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    admin: models.User = Depends(get_current_admin),
):
    inst = _get_or_create(db)
    inst.logo_filename = await _save_branding(file, "logo")
    db.commit()
    return {"ok": True}


@router.delete("/logo")
def delete_logo(db: Session = Depends(get_db), admin: models.User = Depends(get_current_admin)):
    inst = _get_or_create(db)
    if inst.logo_filename:
        p = BRANDING_DIR / inst.logo_filename
        if p.exists():
            p.unlink()
        inst.logo_filename = None
        db.commit()
    return {"ok": True}


@router.post("/favicon")
async def upload_favicon(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    admin: models.User = Depends(get_current_admin),
):
    inst = _get_or_create(db)
    inst.favicon_filename = await _save_branding(file, "favicon")
    db.commit()
    return {"ok": True}


@router.delete("/favicon")
def delete_favicon(db: Session = Depends(get_db), admin: models.User = Depends(get_current_admin)):
    inst = _get_or_create(db)
    if inst.favicon_filename:
        p = BRANDING_DIR / inst.favicon_filename
        if p.exists():
            p.unlink()
        inst.favicon_filename = None
        db.commit()
    return {"ok": True}
