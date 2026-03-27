# Calendarr

**das minimalistische Kalender Frontend**

A clean, self-hosted calendar application with support for CalDAV, Google Calendar, iCal subscriptions, and local calendars — all in one dark-themed, privacy-first UI.

---

## Features

### Calendar Views
- **Month**, **Week**, **Day**, and **Agenda** views
- Configurable week start day (Monday / Sunday)
- Adjustable hour height in week/day view
- Calendar week display in month and week views

### Calendar Sources
- **CalDAV** — connect to any standard CalDAV server (Nextcloud, Baikal, Radicale, etc.)
- **Google Calendar** — OAuth2 integration, individual calendars shown in sidebar
- **iCal Subscriptions** — subscribe to any `.ics` URL with configurable refresh interval
- **Local Calendars** — create and manage calendars directly in Calendarr

### Events
- Create, edit, and delete events with title, description, location, and time
- All-day events
- Per-event color overrides
- iCal event overrides (hide or edit individual events from subscriptions)
- Dim past events option

### User Management
- First-run setup wizard (first user is automatically admin)
- Admin can create additional users
- Per-user settings, avatar, and 2FA

### Authentication
- Username/password login (case-insensitive)
- 7-day JWT sessions
- **Two-Factor Authentication (TOTP)** — works with any authenticator app (Bitwarden, Google Authenticator, etc.)

### Customization (per user)
- Primary, accent, and today-highlight colors
- Text contrast level (4 steps)
- Line/border contrast level (4 steps)
- Hour height in time-grid view
- Default view preference

### Privacy
- Fully self-hosted — your data stays on your server
- All application data stored in Switzerland *(if hosted there)*
- Google data disclaimer shown when Google integration is used

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Vanilla JS (ES modules), HTML5, CSS3 |
| Backend | Python · FastAPI · Uvicorn |
| Database | SQLite (via SQLAlchemy) |
| Auth | JWT (python-jose) · bcrypt · pyotp |
| CalDAV | caldav · icalendar |
| Image | Pillow · CropperJS |

No frontend framework dependencies — the entire UI is plain HTML/CSS/JS.

---

## Installation

### Requirements
- Python 3.9+
- Linux (Debian/Ubuntu recommended)

### Quick Start

```bash
git clone https://git.scarriffle.com/Scarriffle/calendarr
cd calendarr
./install.sh
./start.sh
```

The app will be available at `http://localhost:8080`. On first visit, the setup wizard creates the admin account.

### systemd Service

```bash
sudo cp calendarr.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now calendarr
```

---

## Configuration

Configuration is done via environment variables. The `install.sh` script generates a `.env` file automatically.

| Variable | Default | Description |
|---|---|---|
| `SECRET_KEY` | *(auto-generated)* | JWT signing key — use a strong random value in production |
| `PORT` | `8080` | Server port |
| `HOST` | `0.0.0.0` | Bind address |
| `DATA_DIR` | `./data` | Directory for SQLite database and avatars |
| `GOOGLE_CLIENT_ID` | — | Google OAuth2 Client ID *(optional)* |
| `GOOGLE_CLIENT_SECRET` | — | Google OAuth2 Client Secret *(optional)* |
| `GOOGLE_REDIRECT_URI` | — | e.g. `https://yourdomain.com/api/google/callback` *(optional)* |

### Google Calendar Setup

1. Create a project in [Google Cloud Console](https://console.cloud.google.com/)
2. Enable the **Google Calendar API**
3. Create an **OAuth 2.0 Client ID** (Web application type)
4. Add your redirect URI to the authorized redirect URIs
5. Set `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, and `GOOGLE_REDIRECT_URI` in `.env`

---

## Project Structure

```
calendarr/
├── backend/
│   ├── main.py                 # App entry point, routing, DB migrations
│   ├── models.py               # SQLAlchemy ORM models
│   ├── auth.py                 # JWT, password hashing, user auth
│   ├── caldav_client.py        # CalDAV protocol client
│   └── routers/
│       ├── auth_router.py      # Login, setup, 2FA
│       ├── users_router.py     # Admin user management
│       ├── profile_router.py   # Profile, avatar, password, 2FA settings
│       ├── settings_router.py  # Per-user preferences
│       ├── local_router.py     # Local calendar CRUD
│       ├── caldav_router.py    # CalDAV accounts & calendars
│       ├── google_router.py    # Google OAuth & calendar sync
│       └── ical_router.py      # iCal subscriptions
├── frontend/
│   ├── index.html              # Single-page app shell
│   ├── js/
│   │   ├── app.js              # Bootstrap, login/setup routing
│   │   ├── calendar.js         # Main app logic and UI
│   │   ├── api.js              # HTTP client
│   │   ├── utils.js            # Date helpers, theme application
│   │   ├── color-picker.js     # Gradient color picker component
│   │   └── views/
│   │       ├── month.js        # Month view
│   │       ├── week.js         # Week/day view
│   │       └── agenda.js       # Agenda/list view
│   └── css/
│       └── app.css             # All styles (dark theme, CSS variables)
├── install.sh                  # Installation script
├── start.sh                    # Start script
├── calendarr.service           # systemd unit file
└── requirements.txt            # Python dependencies
```

---

## License

© 2026 Scarriffleservices · All rights reserved
