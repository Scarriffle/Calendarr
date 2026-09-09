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
| `PUBLIC_BASE_URL` | *(derived)* | Public origin behind a reverse proxy — **required for SSO** |
| `OIDC_PROVIDERS` | — | Comma-separated provider keys, e.g. `authentik` *(optional)* |

Per provider `<KEY>` listed in `OIDC_PROVIDERS` (variable names are uppercased):

| Variable | Default | Description |
|---|---|---|
| `OIDC_<KEY>_ISSUER` | — | **Required.** Issuer URL, e.g. `https://authentik.example.com/application/o/calendarr/` |
| `OIDC_<KEY>_CLIENT_ID` | — | **Required.** Client ID of the web application |
| `OIDC_<KEY>_CLIENT_SECRET` | — | Leave empty for a public client (PKCE only) |
| `OIDC_<KEY>_NAME` | *(key)* | Label on the login button |
| `OIDC_<KEY>_SCOPES` | `openid profile email` | Requested scopes — **must be quoted**, see below |
| `OIDC_<KEY>_MOBILE_CLIENT_ID` | — | Client ID(s) of the native apps, comma-separated |
| `OIDC_<KEY>_MOBILE_ISSUER` | *(issuer)* | Only if mobile uses a second application |
| `OIDC_<KEY>_ALLOW_SIGNUP` | `false` | Create accounts on first SSO login |
| `OIDC_<KEY>_ALLOWED_DOMAINS` | — | Email-domain allowlist for signup |
| `OIDC_<KEY>_LINK_BY_EMAIL` | `false` | Auto-link to an existing account by email |
| `OIDC_<KEY>_USERNAME_CLAIM` | `preferred_username` | Claim used to derive the username |
| `OIDC_<KEY>_REDIRECT_URI` | *(derived)* | Overrides the derived callback URL |

### Single Sign-On (OpenID Connect / Authentik)

Adds an SSO button to the login screen **alongside** password login. With
`OIDC_PROVIDERS` unset, nothing changes — the feature is invisible.

**In Authentik:** create one OAuth2/OpenID provider, client type **Public**
(the web flow uses PKCE, so a secret buys little), with two redirect URIs:

- Web: `https://calendar.example.com/api/auth/oidc/authentik/callback`
- Mobile: `calendarr://oauth/callback`

Signing key RS256, scope mappings `openid`, `profile`, `email` — and
**`offline_access` for the mobile apps**. Since Authentik 2024.2 that scope has
to be mapped explicitly; without it no refresh token is issued and the apps
appear to log out every week. Restrict access with an Authentik group binding —
that, not `ALLOWED_DOMAINS`, is the real authorization control.

**In `.env`:**

```bash
PUBLIC_BASE_URL=https://calendar.example.com
OIDC_PROVIDERS=authentik
OIDC_AUTHENTIK_NAME=Authentik
OIDC_AUTHENTIK_ISSUER=https://authentik.example.com/application/o/calendarr/
OIDC_AUTHENTIK_CLIENT_ID=...
OIDC_AUTHENTIK_MOBILE_CLIENT_ID=calendarr-mobile
OIDC_AUTHENTIK_SCOPES="openid profile email"
OIDC_AUTHENTIK_ALLOW_SIGNUP=false
```

> **`install.sh` does not overwrite an existing `.env`.** On an existing
> installation append these lines by hand, then `systemctl restart calendarr`.

> **Quote every value containing a space.** `start.sh` does
> `set -a; source .env; set +a`, so an unquoted
> `OIDC_AUTHENTIK_SCOPES=openid profile email` makes the shell try to run
> `profile` and startup fails.

**Account matching.** An identity is matched on the provider's `sub` claim.
A first-time SSO user whose email matches an existing local account is
*refused* by default rather than linked — otherwise anyone who can set that
email at the identity provider inherits the account. Link deliberately instead:
sign in with the password, then link under Settings. `LINK_BY_EMAIL=true`
enables automatic linking and additionally requires `email_verified`.

With `ALLOW_SIGNUP=true`, unknown users get an account on first login. Such
accounts have no usable password; they use **app passwords** for CalDAV, the
same as 2FA users.

**Adding a second provider** is configuration only: append its key to
`OIDC_PROVIDERS`, add the matching `OIDC_<KEY>_*` block, restart. No code change.

**Rollback:** remove `OIDC_PROVIDERS` and restart. Accounts created via SSO
remain and must be removed (or given a password) by an admin.

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
