# Theme parameters (Web)

Calendarr's web client lets you customise the colour theme under
**Settings → Darstellung → Farben**. Every colour has its own sync toggle (share
it across your devices or keep it device-local — see
[backend/SETTINGS_SYNC.md](backend/SETTINGS_SYNC.md)).

You can also **export** the current theme to a `<date>_<time>.theme` file and
**import** one later. A `.theme` file is plain JSON:

```json
{
  "_format": "calendarr-theme",
  "_version": 1,
  "_docs": "https://git.scarriffle.com/Scarriffle/Calendarr/src/branch/beta/THEME.md",
  "exported_at": "2026-07-20T14:33:00.000Z",
  "settings": {
    "primary_color": "#4285F4",
    "hover_highlight_color": "#2A2A38",
    "...": "..."
  }
}
```

A theme may be **partial** — delete any keys you don't want and only the
remaining ones are applied. Importing writes **only the parameters present in
the file** (keys whose sync toggle is on are also pushed to the server; the rest
update this browser only); omitted parameters are left untouched. If the file
contains parameters this version doesn't recognise, you're asked whether to
import the rest anyway.

## Colour parameters

Source of truth for the defaults: `DEFAULT_COLORS` in
[frontend/js/settings-sync.js](frontend/js/settings-sync.js). Each value is a
`#RRGGBB` hex string. Where a default is listed as "derived", leaving the value
untouched reproduces the previous automatic look; setting it overrides that.

| Key | What it colours | Default |
|---|---|---|
| `primary_color` | Primary/brand colour — buttons, links, active states, and the browser favicon/tab colour | `#4285F4` |
| `accent_color` | Accent — danger actions, the "now" line, reminders | `#EA4335` |
| `today_color` | "Today" accent: the day-number circle and today's labels | `#4285F4` |
| `text_color` | Base text colour (secondary/tertiary text is derived from it) | `#FFFFFF` |
| `bg_color` | App background | `#000000` |
| `surface_color` | Sidebar / top bar / card surfaces (derived from `bg_color` when unset) | `#1A1A1A` |
| `line_color` | Borders and grid lines | `#3A3A52` |
| `month_divider_color` | The line marking a month change in the scrolling month view | `#7090C0` |
| `month_label_color` | The month abbreviation shown at a month change | `#7090C0` |
| `hover_highlight_color` | General interactive hover — buttons, menu items, list rows | `#2A2A38` (= derived hover) |
| `icon_inactive_color` | Sidebar action icons (notification bell *off*, hide/eye, delete/trash, "not editable") in their resting / off / not-hovered state | `#9090AA` (= secondary text) |
| `icon_active_color` | The same sidebar action icons when hovered, pressed, or *on* (e.g. notification bell enabled) | `#E8E8F0` (= primary text) |
| `day_hover_color` | Hover background over a calendar day (month / week / quarter / agenda / mini-calendar / date picker) | `#2A2A38` (= derived hover) |
| `day_selected_color` | The selected day — applied as a subtle tint of this colour | `#4285F4` (= primary) |
| `day_bg_color` | Normal (unselected, non-today) day background. Defaults to the app background so days look transparent | `#000000` |
| `today_bg_color` | Today's day-cell background — applied as a subtle tint of this colour | `#4285F4` (= today accent) |

Notes:
- `day_selected_color` and `today_bg_color` are applied as a low-opacity tint of
  the chosen colour (so content stays readable). The colour you pick is the base
  hue; the swatch shows the full colour.
- `day_bg_color` defaults to the app background. If you set a custom
  `bg_color`, also set `day_bg_color` to match if you want fully transparent days.
- The other clients (iOS / Android) currently ignore the fine-grained element
  colours; they are stored and synced by the server but only the web client
  renders them.
