// Per-setting cross-device sync for the web client.
//
// The server is the sole authority for WHICH settings sync (it returns a fully
// resolved `sync_flags` map). This module owns the browser-local copy of every
// syncable value so that "not synced" works per browser, plus the declarative
// table definition the settings UI renders from. See backend/SETTINGS_SYNC.md.

// Canonical default colours — the single source for the web. Reset writes these.
export const DEFAULT_COLORS = {
  primary_color:       '#58B900',
  accent_color:        '#45A148',
  today_color:         '#6FB669',
  text_color:          '#FFFFFF',
  bg_color:            '#000000',
  line_color:          '#3B3B3D',
  surface_color:       '#2B2B2B',
  month_divider_color: '#95D25E',
  month_label_color:   '#95D25E',
  // Fine-grained element colours (see THEME.md). day_selected/today_bg are
  // applied as a subtle tint of the chosen colour; the rest are applied solid.
  hover_highlight_color: '#2A2A38',
  icon_inactive_color:   '#90AA91',
  icon_active_color:     '#E8E8F0',
  day_hover_color:       '#2B382A',
  day_selected_color:    '#88EF9A',
  day_bg_color:          '#000000',
  today_bg_color:        '#477650',
};

// The syncable settings the web client exposes, grouped into table sections.
// `type`: 'select' | 'toggle' | 'color' | 'icon'.
// Option labels use i18n keys via `tk`, or a literal `label`.
export const SETTING_GROUPS = [
  {
    titleKey: 'settings_calendar_view',
    rows: [
      { key: 'default_view', labelKey: 'settings_default_view', type: 'select', opts: [
        { v: 'month', tk: 'view_month' }, { v: 'week', tk: 'view_week' },
        { v: 'day', tk: 'view_day' }, { v: 'quarter', tk: 'view_quarter' },
        { v: 'agenda', tk: 'view_agenda' },
      ] },
      { key: 'week_start_day', labelKey: 'settings_week_start', type: 'select', opts: [
        { v: 'monday', tk: 'week_start_monday' }, { v: 'sunday', tk: 'week_start_sunday' },
      ] },
      { key: 'dim_past_events', labelKey: 'settings_dim_past', type: 'toggle' },
      { key: 'month_view_paged', labelKey: 'settings_month_mode', type: 'select', opts: [
        { v: false, tk: 'settings_month_mode_scroll' }, { v: true, tk: 'settings_month_mode_paged' },
      ] },
      { key: 'hour_height', labelKey: 'settings_hour_height', type: 'select', opts: [
        { v: 28, tk: 'hour_compact' }, { v: 44, tk: 'hour_normal' },
        { v: 60, tk: 'hour_comfort' }, { v: 80, tk: 'hour_large' },
      ] },
      { key: 'default_event_duration_minutes', labelKey: 'settings_default_duration', type: 'select', opts: [
        { v: 15, label: '15 min' }, { v: 30, label: '30 min' }, { v: 45, label: '45 min' },
        { v: 60, label: '1 h' }, { v: 90, label: '1,5 h' }, { v: 120, label: '2 h' },
      ] },
    ],
  },
  {
    titleKey: 'settings_language',
    rows: [
      { key: 'language', labelKey: 'settings_language', type: 'select', opts: [
        { v: 'de', label: 'Deutsch' }, { v: 'en', label: 'English' },
      ] },
      { key: 'share_calendar_icon', labelKey: 'settings_share_icon', type: 'icon' },
    ],
  },
  {
    titleKey: 'settings_colors',
    rows: [
      { key: 'primary_color',       labelKey: 'settings_primary_color',       type: 'color' },
      { key: 'accent_color',        labelKey: 'settings_accent_color',        type: 'color' },
      { key: 'today_color',         labelKey: 'settings_today_color',         type: 'color' },
      { key: 'text_color',          labelKey: 'settings_text_color',          type: 'color' },
      { key: 'bg_color',            labelKey: 'settings_bg_color',            type: 'color' },
      { key: 'surface_color',       labelKey: 'settings_surface_color',       type: 'color' },
      { key: 'line_color',          labelKey: 'settings_line_color',          type: 'color' },
      { key: 'month_divider_color', labelKey: 'settings_month_divider_color', type: 'color' },
      { key: 'month_label_color',   labelKey: 'settings_month_label_color',   type: 'color' },
      { key: 'hover_highlight_color', labelKey: 'settings_hover_highlight_color', type: 'color' },
      { key: 'icon_inactive_color',   labelKey: 'settings_icon_inactive_color',   type: 'color' },
      { key: 'icon_active_color',     labelKey: 'settings_icon_active_color',     type: 'color' },
      { key: 'day_hover_color',       labelKey: 'settings_day_hover_color',       type: 'color' },
      { key: 'day_selected_color',    labelKey: 'settings_day_selected_color',    type: 'color' },
      { key: 'day_bg_color',          labelKey: 'settings_day_bg_color',          type: 'color' },
      { key: 'today_bg_color',        labelKey: 'settings_today_bg_color',        type: 'color' },
    ],
  },
];

// Flat list of every syncable key the web manages (table order).
export const SYNCABLE_KEYS = SETTING_GROUPS.flatMap(g => g.rows.map(r => r.key));

// Instance-wide default theme set by an admin (from GET /api/instance/). It is
// the base a user inherits and the target that a per-colour "Reset" returns to.
// A user's own value always overrides it. See backend/routers/admin_router.py.
export let INSTANCE_DEFAULTS = {};
export function setInstanceDefaults(obj) { INSTANCE_DEFAULTS = obj || {}; }
// The effective default for a colour key: admin instance default → built-in.
export function baseColor(key) { return INSTANCE_DEFAULTS[key] || DEFAULT_COLORS[key]; }

const LOCAL_KEY = 'settingsLocal';

export function loadLocal() {
  try { return JSON.parse(localStorage.getItem(LOCAL_KEY) || '{}') || {}; }
  catch (_) { return {}; }
}

export function saveLocal(obj) {
  try { localStorage.setItem(LOCAL_KEY, JSON.stringify(obj)); } catch (_) {}
}

// Effective value of a syncable key: synced → server value; otherwise the
// browser-local value (falling back to the server value if we have none yet).
export function effectiveValue(key, server, flags, local) {
  if (flags[key]) return server[key];
  return (key in local && local[key] != null) ? local[key] : server[key];
}

// Build the effective settings object: a copy of the raw server settings with
// each syncable key resolved to its effective value. As a side effect, mirror
// every effective value into the local copy so that flipping a flag OFF later
// retains the currently-visible value.
export function mergeEffective(server, flags, local) {
  const eff = { ...server };
  for (const key of SYNCABLE_KEYS) {
    const val = effectiveValue(key, server, flags, local);
    eff[key] = val;
    if (val != null) local[key] = val;
  }
  saveLocal(local);
  return eff;
}
