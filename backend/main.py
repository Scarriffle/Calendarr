import logging
import os
import sys
from pathlib import Path

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text

sys.path.insert(0, str(Path(__file__).parent))

from database import Base, engine
from routers import auth_router, caldav_router, google_router, ical_router, local_router, profile_router, settings_router, users_router

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

_migrate()

app = FastAPI(title="Calendarr", docs_url=None, redoc_url=None)

app.include_router(auth_router.router, prefix="/api/auth", tags=["auth"])
app.include_router(users_router.router, prefix="/api/users", tags=["users"])
app.include_router(caldav_router.router, prefix="/api/caldav", tags=["caldav"])
app.include_router(settings_router.router, prefix="/api/settings", tags=["settings"])
app.include_router(profile_router.router, prefix="/api/profile", tags=["profile"])
app.include_router(local_router.router, prefix="/api/local", tags=["local"])
app.include_router(ical_router.router, prefix="/api/ical", tags=["ical"])
app.include_router(google_router.router, prefix="/api/google", tags=["google"])

FRONTEND_DIR = Path(__file__).parent.parent / "frontend"
app.mount("/static", StaticFiles(directory=str(FRONTEND_DIR)), name="static")


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
