# Settings sync contract (Web / iOS / Android)

> For a human-facing description of each theme colour parameter (and the
> `.theme` import/export format), see [../THEME.md](../THEME.md).

Per-setting, cross-device synchronisation of user settings. The **server is the
sole authority** for *which* settings sync; clients must not duplicate that logic.
This document is the shared contract all three clients implement identically.

## Canonical keys & default flags

Source of truth: `DEFAULT_SYNC` in `backend/routers/settings_router.py`. Keys use
the server's snake_case field names.

| Key | Kind | Default sync |
|---|---|---|
| `default_view` | enum | ON |
| `week_start_day` | enum | ON |
| `dim_past_events` | bool | ON |
| `hour_height` | enum(int) | ON |
| `primary_color` `accent_color` `today_color` `text_color` `line_color` `bg_color` `month_divider_color` `month_label_color` | color hex | ON |
| `default_event_duration_minutes` | enum(int) | ON |
| `default_reminder_minutes` | enum(int, null=off) | ON |
| `language` | enum | **OFF** |
| `share_calendar_icon` | icon key | **OFF** |
| `cache_months` | enum(int) | **OFF** |
| `month_view_paged` | bool | **OFF** |

Settings **not** in this list are never synced by this mechanism:
- Account-wide settings (`private_event_visibility`, `group_visible_calendar_id`,
  `directory_hidden`) — one value per account, always identical everywhere; they
  keep their existing dedicated endpoints/UI, not a sync toggle.
- Platform-exclusive device prefs (e.g. iOS `liquid_glass`) — stay device-local.
- Identity/security, calendar/account management, admin.

## API

- `GET /api/settings/` returns every value **plus** `sync_flags`: a fully-resolved
  `{key: bool}` map covering exactly the keys above (stored overrides on top of
  `DEFAULT_SYNC`). Clients read this map verbatim — no client-side defaults.
- `PUT /api/settings/` accepts a partial `sync_flags` map (merged account-wide,
  unknown keys ignored, untouched flags preserved) and partial value fields
  (`exclude_unset`; `text_color`/`line_color`/`bg_color`/… treated as
  nullable-reset per `NULLABLE_OVERRIDES`).

## Client rules

Each client keeps a **local copy** of every syncable value (UserDefaults /
DataStore-SharedPreferences / localStorage) so that "not synced" works per device.

1. **On login / launch / foreground:** `GET /api/settings/` → values + `sync_flags`.
2. **Pull:** for each syncable key, if `sync_flags[key]` is ON, adopt the server
   value into the local copy; if OFF, keep the local value.
3. **Push (debounced, read-modify-write):** start from the current server snapshot,
   overwrite only keys whose flag is ON with the local value, `PUT`. Never push a
   key whose flag is OFF.
4. **Toggle a flag ON:** set the flag true **and** push this device's current local
   value (it becomes the shared value). **OFF:** set false; keep the local value.
5. **Global "share everything":** set all syncable flags true and push all local
   values. Global off: set all false.

The flag map itself is always account-wide and always fetched fresh; it is what a
client consults to decide what to send/receive.
