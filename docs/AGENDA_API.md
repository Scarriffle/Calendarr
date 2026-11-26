# Agenda API

Read-only access to a user's events for an external application — a morning
briefing, a dashboard, a home-automation flow. Authenticated by an API key, not
by a login session.

Added on `beta` in `d4d5594`. Implemented in `backend/routers/agenda_router.py`,
key management in `backend/routers/profile_router.py`, tests in
`backend/tests/test_agenda_api.py`.

---

## 1. Create a key

Web UI only: **Settings → Profile → API keys**, below the app passwords.
Deliberately not available on iOS or Android.

1. Give it a name (e.g. `Morning briefing`).
2. Either leave **All calendars** ticked, or untick it and pick the calendars
   this key may read.
3. **Create key.** The key is shown **once** — only its SHA-256 digest is
   stored. Lost means create a new one.

A key looks like:

```
calrr_XLxtLa0w8nUMtnrvV3B3ZLfcK3O8fUq4rrcnPqLx0Zk
```

The list afterwards shows the first 14 characters, the calendar scope and when
the key was last used, so a forgotten key can be identified and revoked.

**All calendars** is not a snapshot: a calendar added later is included
automatically. A fixed selection is, so a new calendar will *not* appear in a
briefing until the key is recreated.

---

## 2. `GET /api/agenda`

The only endpoint an integration needs.

### Authentication

Either header works. Both carry the key in clear text, so use HTTPS.

```http
Authorization: Bearer calrr_...
```

```http
X-API-Key: calrr_...
```

A login session token is **not** accepted here. If it were, a browser session
could reach the endpoint and skip the key's calendar scope entirely.

### Parameters

Two mutually exclusive ways to name a range.

**By day** — what a briefing wants:

| Parameter | Default | Meaning |
|---|---|---|
| `tz` | `UTC` | IANA timezone name, e.g. `Europe/Berlin`. Decides where "a day" begins and ends. |
| `date` | today in `tz` | `YYYY-MM-DD`. |
| `days` | `1` | How many days from `date`. 1–31. |

**By explicit range** — `start` and `end` must be given together and override
`date`/`days`:

| Parameter | Meaning |
|---|---|
| `start` | ISO 8601. No offset is read as UTC. |
| `end` | ISO 8601, exclusive. At most 31 days after `start`. |

There is no server-side timezone for a user, which is why `tz` exists: the
caller knows its own. Without it, "today" would silently mean the UTC day.

### Examples

```bash
curl -H "Authorization: Bearer $KEY" \
  "https://cal.example.com/api/agenda?tz=Europe/Berlin"
```

```bash
curl -H "Authorization: Bearer $KEY" \
  "https://cal.example.com/api/agenda?date=2026-11-26&tz=Europe/Berlin&days=3"
```

```bash
curl -H "Authorization: Bearer $KEY" \
  "https://cal.example.com/api/agenda?start=2026-11-26T06:00:00%2B01:00&end=2026-11-26T22:00:00%2B01:00"
```

### Response

```json
{
  "date": "2026-11-26",
  "timezone": "Europe/Berlin",
  "start": "2026-11-26T00:00:00+01:00",
  "end": "2026-11-27T00:00:00+01:00",
  "days": 1,
  "count": 2,
  "errors": [],
  "events": [
    {
      "title": "Feiertag",
      "start": "2026-11-26",
      "end": "2026-11-27",
      "all_day": true,
      "location": "",
      "calendar": "Feiertage",
      "color": "#8e24aa",
      "source": "ical"
    },
    {
      "title": "Zahnarzt",
      "start": "2026-11-26T09:30:00+01:00",
      "end": "2026-11-26T10:15:00+01:00",
      "all_day": false,
      "location": "Praxis Dr. Meier",
      "calendar": "Persönlich",
      "color": "#34a853",
      "source": "local"
    }
  ]
}
```

#### Envelope

| Field | Type | Notes |
|---|---|---|
| `date` | string \| null | The requested day. `null` when `start`/`end` were used. |
| `timezone` | string \| null | Echo of `tz`. `null` when `start`/`end` were used. |
| `start`, `end` | string | The range actually queried, ISO 8601 with offset. `end` is exclusive. |
| `days` | int \| null | Echo of `days`. `null` when `start`/`end` were used. |
| `count` | int | `events.length`. |
| `errors` | array | Upstream sources that did not answer. See below. |
| `events` | array | Sorted: all-day first, then by start time. |

#### Event

Exactly these eight fields, nothing else.

| Field | Type | Notes |
|---|---|---|
| `title` | string | Never `null`; `""` if the source had none. Carries the server's decoration where there is one: a group event's prefix, a birthday's age. |
| `start` | string \| null | `YYYY-MM-DD` when `all_day`, otherwise ISO 8601 with an offset. |
| `end` | string \| null | Same format as `start`. |
| `all_day` | bool | |
| `location` | string | `""` if none. |
| `calendar` | string | Display name of the calendar the event came from. |
| `color` | string \| null | `#rrggbb`. The event's own colour, else the calendar's. |
| `source` | string | `local`, `caldav`, `google`, `ical` or `homeassistant`. |

`description`, attendees, attachments, reminders and recurrence rules are
**not** served. A key is long-lived, so what it returns is also what a leaked
key exposes.

#### Errors array

A source that failed to sync. The day is still returned, just short — so a
briefing can say "one calendar did not answer" instead of quietly omitting
appointments.

```json
"errors": [{ "source": "caldav", "name": "user@host – Work" }]
```

### Status codes

| Code | When |
|---|---|
| `200` | Fine. `errors` may still be non-empty. |
| `400` | Unknown `tz`; malformed `date`, `start` or `end`; `start` without `end`; `end` not after `start`; range over 31 days. |
| `401` | Missing, unknown or revoked key — or a session token. |
| `422` | `days` outside 1–31. |

---

## 3. Key management (web UI uses these)

Session-authenticated, under `/api/profile`. An integration does not need them.

| Method | Path | Notes |
|---|---|---|
| `GET` | `/api/profile/api-keys` | List. Returns `id`, `label`, `prefix`, `calendars`, `created_at`, `last_used_at`. Never the key. |
| `POST` | `/api/profile/api-keys` | Body `{ "label": "...", "calendars": ["local-3"] \| null }`. Response additionally carries `key` — the only time it exists. |
| `DELETE` | `/api/profile/api-keys/{id}` | Revoke. Takes effect on the next request. |

`calendars` holds the same calendar keys the internal event payload uses:
`"7"` (CalDAV, bare id), `"local-3"`, `"google-5"`, `"ical-2"`,
`"homeassistant-1"`. `null` means every calendar the owner can read.

There is no endpoint to edit a key. Revoke and create a new one; the UI offers
nothing else, and an endpoint nothing calls is dead weight.

---

## Behaviour worth knowing

**Private events are included** — with their real title, time and location.
The briefing is for the calendar's own owner, and `apply_event_privacy`
(`backend/local_events_util.py:90`) returns an event untouched when the owner
is the requester. Other people's private events, reached through a shared or
group calendar, stay redacted by that same rule. Pinned by two tests.

**The scope is a filter, not a grant.** It narrows what the owner may already
read. Naming someone else's calendar key in `calendars` yields nothing.

**One source of truth.** Events come from `caldav_router.get_events`, the same
aggregator the web UI calls. A briefing therefore cannot drift from what the
calendar shows, and a new source added there appears here with no change.

**Hidden calendars.** Whatever the web UI suppresses (`enabled`,
`sidebar_hidden`) is suppressed here too, by construction.

**All-day `end` is exclusive, mostly.** CalDAV, iCal and Google all use an
exclusive end date, so a one-day event ends on the following day — as in the
example above. A local all-day event stores whatever the client wrote, which is
usually the same, but this is not enforced server-side. Treat `end` as
exclusive and tolerate an inclusive value.

**`tzdata` is a dependency.** `zoneinfo` needs a timezone database. Debian and
Ubuntu provide it through the system package; a slim image does not, and every
`tz` would then come back `400`. Pinned in `requirements.txt`, so a deploy must
run `pip install -r requirements.txt`.
