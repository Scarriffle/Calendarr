// Per-setting cross-device sync for the web client.
//
// The server is the sole authority for WHICH settings sync (it returns a fully
// resolved `sync_flags` map). This module owns the browser-local copy of every
// syncable value so that "not synced" works per browser, plus the declarative
// table definition the settings UI renders from. See backend/SETTINGS_SYNC.md.

import { LANGUAGES } from './i18n.js';

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
      // The web delivers no notifications itself; these steer the apps, the
      // same way the per-calendar bell does.
      { key: 'default_reminder_minutes', labelKey: 'settings_default_reminder', type: 'select', opts: [
        { v: null, tk: 'reminder_off' }, { v: 0, tk: 'reminder_at_start' },
        { v: 5, label: '5 min' }, { v: 15, label: '15 min' }, { v: 30, label: '30 min' },
        { v: 60, label: '1 h' }, { v: 1440, tk: 'reminder_one_day' },
        { v: 10080, tk: 'reminder_one_week' },
      ] },
      // All-day events start at midnight, so minutes would put the reminder in
      // the middle of the night. These two say it as days plus a time of day.
      { key: 'allday_reminder_days', labelKey: 'settings_allday_reminder', type: 'select', opts: [
        { v: null, tk: 'reminder_off' }, { v: 0, tk: 'reminder_same_day' },
        { v: 1, tk: 'reminder_one_day' }, { v: 2, label: '2' }, { v: 3, label: '3' },
        { v: 7, tk: 'reminder_one_week' },
      ] },
      { key: 'allday_reminder_time', labelKey: 'settings_allday_time', type: 'time' },
    ],
  },
  {
    titleKey: 'settings_theme_mode_section',
    rows: [
      // Light and dark come from the instance; manual unlocks the colour rows
      // below. System follows the device and switches between the two.
      { key: 'theme_mode', labelKey: 'settings_theme_mode', type: 'select', opts: [
        { v: 'system', tk: 'theme_mode_system' }, { v: 'light', tk: 'theme_mode_light' },
        { v: 'dark', tk: 'theme_mode_dark' }, { v: 'manual', tk: 'theme_mode_manual' },
      ] },
    ],
  },
  {
    titleKey: 'settings_language',
    rows: [
      // Derived from the i18n registry: adding a language there adds it here.
      // Each language is listed under its own endonym, so the labels are never
      // translated — a Finn looks for "Suomi", not "Finnisch".
      { key: 'language', labelKey: 'settings_language', type: 'select',
        opts: LANGUAGES.map(l => ({ v: l.code, label: l.label })) },
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
// Both instance themes, kept so switching mode needs no round trip.
export let INSTANCE_THEMES = { light: {}, dark: {} };
export let THEME_MODE = 'dark';

export function setInstanceDefaults(obj) { INSTANCE_DEFAULTS = obj || {}; }

export function setInstanceThemes(light, dark) {
  INSTANCE_THEMES = { light: light || {}, dark: dark || {} };
  applyModeDefaults();
}

/** Which of the two themes a mode resolves to. `system` asks the OS. */
export function resolvedScheme(mode = THEME_MODE) {
  if (mode === 'light' || mode === 'dark') return mode;
  if (mode === 'system') {
    return (typeof matchMedia === 'function'
      && matchMedia('(prefers-color-scheme: light)').matches) ? 'light' : 'dark';
  }
  return 'dark';   // manual: the user's own colours sit on the dark base
}

export function setThemeMode(mode) {
  THEME_MODE = ['system', 'light', 'dark', 'manual'].includes(mode) ? mode : 'dark';
  applyModeDefaults();
}

function applyModeDefaults() {
  INSTANCE_DEFAULTS = INSTANCE_THEMES[resolvedScheme()] || {};
}

/** True when the per-colour settings apply at all. */
export function colorsEditable() { return THEME_MODE === 'manual'; }
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
