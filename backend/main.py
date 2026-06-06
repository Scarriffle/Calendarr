import logging
import os
import sys
from pathlib import Path

import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text

# How long the browser may keep static assets before revalidating.
STATIC_MAX_AGE_SECONDS = 2 * 60 * 60  # 2 hours
NO_CACHE = "no-cache, no-store, must-revalidate"
STATIC_CACHE = f"public, max-age={STATIC_MAX_AGE_SECONDS}, must-revalidate"

sys.path.insert(0, str(Path(__file__).parent))

from database import Base, engine
from routers import auth_router, caldav_router, google_router, groups_router, homeassistant_router, ical_router, local_router, profile_router, settings_router, users_router

logging.basicConfig(level=logging.INFO)

# Create DB tables on startup
Base.metadata.create_all(bind=engine)

# Run column migrations for new fields (safe: only adds if not exists)
def _migrate():
    with engine.connect() as conn:
        # Add week_start_day to user_settings if not present
        try:
            conn.execute(text(
                "ALTER TABLE user_settings ADD COLUMN week_start_day VARCHAR(10) DEFAULT 'monday'"
            ))
            conn.commit()
            logging.info("Migration: added week_start_day column")
        except Exception:
            pass  # Column already exists
        try:
            conn.execute(text("ALTER TABLE calendars ADD COLUMN sidebar_hidden BOOLEAN DEFAULT 0"))
            conn.commit()
            logging.info("Migration: added sidebar_hidden to calendars")
        except Exception:
            pass
        try:
            conn.execute(text("ALTER TABLE google_calendars ADD COLUMN sidebar_hidden BOOLEAN DEFAULT 0"))
            conn.commit()
            logging.info("Migration: added sidebar_hidden to google_calendars")
        except Exception:
            pass
        try:
            conn.execute(text("ALTER TABLE user_settings ADD COLUMN text_contrast INTEGER DEFAULT 3"))
            conn.commit()
        except Exception:
            pass
        try:
            conn.execute(text("ALTER TABLE user_settings ADD COLUMN line_contrast INTEGER DEFAULT 3"))
            conn.commit()
        except Exception:
            pass
        try:
            conn.execute(text("ALTER TABLE user_settings ADD COLUMN hour_height INTEGER DEFAULT 60"))
            conn.commit()
        except Exception:
            pass
        try:
            conn.execute(text("ALTER TABLE user_settings ADD COLUMN language VARCHAR(5) DEFAULT 'de'"))
            conn.commit()
        except Exception:
            pass
        try:
            conn.execute(text("ALTER TABLE homeassistant_accounts ADD COLUMN auth_method VARCHAR(20) DEFAULT 'token'"))
            conn.commit()
        except Exception:
            pass
        try:
            conn.execute(text("ALTER TABLE homeassistant_accounts ADD COLUMN refresh_token TEXT"))
            conn.commit()
        except Exception:
            pass
        try:
            conn.execute(text("ALTER TABLE homeassistant_accounts ADD COLUMN token_expiry DATETIME"))
            conn.commit()
        except Exception:
            pass
        try:
            conn.execute(text("ALTER TABLE homeassistant_accounts ADD COLUMN client_id VARCHAR(500)"))
            conn.commit()
        except Exception:
            pass
        try:
            conn.execute(text("ALTER TABLE local_events ADD COLUMN rrule TEXT"))
            conn.commit()
            logging.info("Migration: added rrule to local_events")
        except Exception:
            pass

        try:
            conn.execute(text("ALTER TABLE local_events ADD COLUMN exdate TEXT"))
            conn.commit()
            logging.info("Migration: added exdate to local_events")
        except Exception:
            pass

        try:
            conn.execute(text("ALTER TABLE local_events ADD COLUMN reminders TEXT"))
            conn.commit()
            logging.info("Migration: added reminders to local_events")
        except Exception:
            pass

        try:
            conn.execute(text("ALTER TABLE user_settings ADD COLUMN default_reminder_minutes INTEGER"))
            conn.commit()
            logging.info("Migration: added default_reminder_minutes to user_settings")
        except Exception:
            pass

        try:
            conn.execute(text("ALTER TABLE user_settings ADD COLUMN month_divider_color VARCHAR(7) DEFAULT '#7090c0'"))
            conn.commit()
        except Exception:
            pass

        try:
            conn.execute(text("ALTER TABLE user_settings ADD COLUMN month_label_color VARCHAR(7) DEFAULT '#7090c0'"))
            conn.commit()
        except Exception:
            pass

        try:
            conn.execute(text("ALTER TABLE user_settings ADD COLUMN text_color VARCHAR(7)"))
            conn.commit()
        except Exception:
            pass

        try:
            conn.execute(text("ALTER TABLE user_settings ADD COLUMN line_color VARCHAR(7)"))
            conn.commit()
        except Exception:
            pass

        try:
            conn.execute(text("ALTER TABLE user_settings ADD COLUMN bg_color VARCHAR(7)"))
            conn.commit()
        except Exception:
            pass

        # ── Collaboration features (sharing, groups, creator, private) ──
        try:
            conn.execute(text("ALTER TABLE user_settings ADD COLUMN private_event_visibility VARCHAR(10) DEFAULT 'busy'"))
            conn.commit()
            logging.info("Migration: added private_event_visibility to user_settings")
        except Exception:
            pass
        try:
            conn.execute(text("ALTER TABLE local_events ADD COLUMN creator_id INTEGER"))
            conn.commit()
            logging.info("Migration: added creator_id to local_events")
        except Exception:
            pass
        try:
            conn.execute(text("ALTER TABLE local_events ADD COLUMN creator_name_external TEXT"))
            conn.commit()
            logging.info("Migration: added creator_name_external to local_events")
        except Exception:
            pass
        try:
            conn.execute(text("ALTER TABLE local_events ADD COLUMN is_private BOOLEAN DEFAULT 0"))
            conn.commit()
            logging.info("Migration: added is_private to local_events")
        except Exception:
            pass
        try:
            conn.execute(text("ALTER TABLE user_settings ADD COLUMN group_visible_calendar_id INTEGER"))
            conn.commit()
            logging.info("Migration: added group_visible_calendar_id to user_settings")
        except Exception:
            pass
        try:
            conn.execute(text("ALTER TABLE users ADD COLUMN display_name VARCHAR(100)"))
            conn.commit()
            logging.info("Migration: added display_name to users")
        except Exception:
            pass
        # Backfill display_name from username for existing rows (only where empty).
        try:
            conn.execute(text("UPDATE users SET display_name = username WHERE display_name IS NULL OR display_name = ''"))
            conn.commit()
        except Exception:
            pass
        try:
            conn.execute(text("ALTER TABLE groups ADD COLUMN icon VARCHAR(16)"))
            conn.commit()
            logging.info("Migration: added icon to groups")
        except Exception:
            pass
        try:
            conn.execute(text("ALTER TABLE group_members ADD COLUMN color VARCHAR(7)"))
            conn.commit()
            logging.info("Migration: added color to group_members")
        except Exception:
            pass

_migrate()

app = FastAPI(title="Calendarr", docs_url=None, redoc_url=None)


@app.middleware("http")
async def add_cache_headers(request: Request, call_next):
    """Force ≤ 2h browser cache for static assets and disable cache for the
    entry HTML / SW / version file. API responses are left alone (handlers
    decide their own caching)."""
    response = await call_next(request)
    path = request.url.path

    # Never cache: entry HTML, manifest, service worker, version marker
    if (
        path in ("/", "/index.html", "/manifest.json", "/sw.js")
        or path == "/static/js/version.js"
    ):
        response.headers["Cache-Control"] = NO_CACHE
        response.headers["Pragma"] = "no-cache"
        response.headers["Expires"] = "0"
    # JS/CSS must revalidate on every load so a deploy takes effect on the next
    # reload (returns a cheap 304 when unchanged). Without this, a fresh
    # no-cache index.html could pair with stale 2h-cached scripts.
    elif path.startswith("/static/js/") or path.startswith("/static/css/"):
        response.headers["Cache-Control"] = NO_CACHE
    # 2h cache for the rest of the frontend (icons, fonts, images, …)
    elif path.startswith("/static/") or path.startswith("/icons/"):
        response.headers["Cache-Control"] = STATIC_CACHE
    # SPA fallback (everything else that isn't an API route) returns HTML;
    # don't let the browser cache that either.
    elif not path.startswith("/api/"):
        response.headers["Cache-Control"] = NO_CACHE

    return response


app.include_router(auth_router.router, prefix="/api/auth", tags=["auth"])
app.include_router(users_router.router, prefix="/api/users", tags=["users"])
app.include_router(caldav_router.router, prefix="/api/caldav", tags=["caldav"])
app.include_router(settings_router.router, prefix="/api/settings", tags=["settings"])
app.include_router(profile_router.router, prefix="/api/profile", tags=["profile"])
app.include_router(local_router.router, prefix="/api/local", tags=["local"])
app.include_router(groups_router.router, prefix="/api/groups", tags=["groups"])
app.include_router(ical_router.router, prefix="/api/ical", tags=["ical"])
app.include_router(google_router.router, prefix="/api/google", tags=["google"])
app.include_router(homeassistant_router.router, prefix="/api/homeassistant", tags=["homeassistant"])

FRONTEND_DIR = Path(__file__).parent.parent / "frontend"
app.mount("/static", StaticFiles(directory=str(FRONTEND_DIR)), name="static")


# ── PWA assets that must live at root scope ──────────────
@app.get("/manifest.json")
async def pwa_manifest():
    return FileResponse(str(FRONTEND_DIR / "manifest.json"), media_type="application/manifest+json")


@app.get("/sw.js")
async def pwa_service_worker():
    return FileResponse(
        str(FRONTEND_DIR / "sw.js"),
        media_type="application/javascript",
        headers={"Service-Worker-Allowed": "/", "Cache-Control": "no-cache"},
    )


@app.get("/icons/{icon_name}")
async def pwa_icon(icon_name: str):
    icon_path = FRONTEND_DIR / "icons" / icon_name
    if not icon_path.exists() or not icon_path.is_file():
        raise HTTPException(status_code=404, detail="Icon not found")
    return FileResponse(str(icon_path))


@app.get("/{full_path:path}")
async def spa_fallback(full_path: str):
    if full_path.startswith("api/"):
        raise HTTPException(status_code=404, detail="API endpoint not found")
    index = FRONTEND_DIR / "index.html"
    return FileResponse(str(index))


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    host = os.environ.get("HOST", "0.0.0.0")
    uvicorn.run(app, host=host, port=port)
