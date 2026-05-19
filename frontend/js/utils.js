export function isToday(d) {
  const now = new Date();
  return d.getFullYear() === now.getFullYear() &&
         d.getMonth()    === now.getMonth()    &&
         d.getDate()     === now.getDate();
}

export function isSameDay(a, b) {
  return a.getFullYear() === b.getFullYear() &&
         a.getMonth()    === b.getMonth()    &&
         a.getDate()     === b.getDate();
}

export function isPast(ev) {
  const end = new Date(ev.end);
  return end < new Date();
}

export function formatDate(d, opts = {}) {
  return d.toLocaleDateString('de', opts);
}

export function dateKey(d) {
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
}

export function toLocalDatetimeInput(d) {
  const Y = d.getFullYear();
  const M = String(d.getMonth()+1).padStart(2,'0');
  const D = String(d.getDate()).padStart(2,'0');
  const h = String(d.getHours()).padStart(2,'0');
  const m = String(d.getMinutes()).padStart(2,'0');
  return `${Y}-${M}-${D}T${h}:${m}`;
}

export function toDateInput(d) {
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
}

// Monday-first: returns 0=Mo, 1=Di, ..., 6=So
export function dayOfWeek(d, weekStartDay = 'monday') {
  if (weekStartDay === 'sunday') {
    return d.getDay(); // 0=So, 1=Mo, ..., 6=Sa
  }
  return (d.getDay() + 6) % 7; // 0=Mo, 1=Di, ..., 6=So
}

// Returns the start-of-week date for d
export function weekStart(d, weekStartDay = 'monday') {
  const m = new Date(d);
  m.setDate(m.getDate() - dayOfWeek(m, weekStartDay));
  m.setHours(0, 0, 0, 0);
  return m;
}

// Returns the ISO week number (Monday-based, ISO 8601)
export function getISOWeekNumber(d) {
  const date = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  // ISO week: weeks start on Monday, week 1 contains the first Thursday
  const day = date.getUTCDay() || 7; // make Sunday = 7
  date.setUTCDate(date.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  return Math.ceil((((date - yearStart) / 86400000) + 1) / 7);
}

const TEXT_CONTRAST = {
  1: { t1: '#606070', t2: '#484858', t3: '#303040' },
  2: { t1: '#9090a8', t2: '#6a6a80', t3: '#484860' },
  3: { t1: '#c8c8d8', t2: '#9090aa', t3: '#55556a' },
  4: { t1: '#ffffff', t2: '#c0c0d8', t3: '#8888a0' },
};
const LINE_CONTRAST = {
  1: { border: '#1e1e2c', light: '#181826' },
  2: { border: '#2a2a3c', light: '#222230' },
  3: { border: '#3a3a52', light: '#2e2e40' },
  4: { border: '#5a5a78', light: '#484860' },
};

// Defaults wenn kein Custom-Override gesetzt ist.
// Bewusst hart "weiss auf schwarz" damit man nie unsichtbar landet.
export const DEFAULT_TEXT_COLOR = '#FFFFFF';
export const DEFAULT_LINE_COLOR = '#3A3A52';
export const DEFAULT_BG_COLOR   = '#000000';

export function applyTheme(settings) {
  const root = document.documentElement;
  root.style.setProperty('--primary',     settings.primary_color || '#4285f4');
  root.style.setProperty('--primary-dim', hexToRgba(settings.primary_color || '#4285f4', 0.15));
  root.style.setProperty('--accent',      settings.accent_color  || '#ea4335');
  root.style.setProperty('--today-color', settings.today_color   || '#4285f4');

  // Effektive Farben bestimmen (Override > Default).
  let textColor = settings.text_color || DEFAULT_TEXT_COLOR;
  let lineColor = settings.line_color || DEFAULT_LINE_COLOR;
  let bgColor   = settings.bg_color   || DEFAULT_BG_COLOR;

  // Sicherheitsbremse: Wenn Schrift- und Hintergrundfarbe nicht genug
  // Kontrast haben (passiert wenn man aus Versehen text=bg eingibt),
  // erzwinge weiss-auf-schwarz, damit man nicht in einer unbedienbaren
  // Seite landet.
  if (contrastRatio(textColor, bgColor) < 2.5) {
    textColor = DEFAULT_TEXT_COLOR;
    bgColor   = DEFAULT_BG_COLOR;
  }

  root.style.setProperty('--text-1', textColor);
  root.style.setProperty('--text-2', shadeHex(textColor, -0.25));
  root.style.setProperty('--text-3', shadeHex(textColor, -0.55));

  root.style.setProperty('--border',       lineColor);
  root.style.setProperty('--border-light', shadeHex(lineColor, -0.25));

  root.style.setProperty('--bg-app',     bgColor);
  root.style.setProperty('--bg-topbar',  shadeHex(bgColor, 0.10));
  root.style.setProperty('--bg-sidebar', shadeHex(bgColor, 0.10));
  root.style.setProperty('--bg-surface', shadeHex(bgColor, 0.18));
  root.style.setProperty('--bg-hover',   shadeHex(bgColor, 0.26));
  root.style.setProperty('--bg-active',  shadeHex(bgColor, 0.40));

  const hh = settings.hour_height || 44;
  root.style.setProperty('--hour-h', hh + 'px');

  root.style.setProperty('--month-divider-color', settings.month_divider_color || '#7090c0');
  root.style.setProperty('--month-label-color',   settings.month_label_color   || '#7090c0');
}

function luminance(hex) {
  const c = (n) => {
    const v = n / 255;
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  };
  const r = c(parseInt(hex.slice(1, 3), 16));
  const g = c(parseInt(hex.slice(3, 5), 16));
  const b = c(parseInt(hex.slice(5, 7), 16));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
function contrastRatio(c1, c2) {
  try {
    const l1 = luminance(c1);
    const l2 = luminance(c2);
    return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
  } catch { return 21; }
}

function hexToRgba(hex, alpha) {
  const r = parseInt(hex.slice(1,3), 16);
  const g = parseInt(hex.slice(3,5), 16);
  const b = parseInt(hex.slice(5,7), 16);
  return `rgba(${r},${g},${b},${alpha})`;
}

// Brighten (positive amount) or darken (negative) a hex colour.
// Used to derive supporting shades (sidebar bg, hover bg, secondary text…)
// from a single user-picked colour so the whole UI stays in the same family.
function shadeHex(hex, amount) {
  let r = parseInt(hex.slice(1,3), 16);
  let g = parseInt(hex.slice(3,5), 16);
  let b = parseInt(hex.slice(5,7), 16);
  if (amount >= 0) {
    r = Math.round(r + (255 - r) * amount);
    g = Math.round(g + (255 - g) * amount);
    b = Math.round(b + (255 - b) * amount);
  } else {
    const a = 1 + amount; // amount is negative: e.g. -0.25 → keep 75%
    r = Math.round(r * a);
    g = Math.round(g * a);
    b = Math.round(b * a);
  }
  const h = n => Math.max(0, Math.min(255, n)).toString(16).padStart(2, '0');
  return '#' + h(r) + h(g) + h(b);
}
