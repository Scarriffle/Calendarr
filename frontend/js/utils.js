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

export function applyTheme(settings) {
  const root = document.documentElement;
  root.style.setProperty('--primary',     settings.primary_color || '#4285f4');
  root.style.setProperty('--primary-dim', hexToRgba(settings.primary_color || '#4285f4', 0.15));
  root.style.setProperty('--accent',      settings.accent_color  || '#ea4335');
  root.style.setProperty('--today-color', settings.today_color   || '#4285f4');

  const tc = TEXT_CONTRAST[settings.text_contrast || 3];
  root.style.setProperty('--text-1', tc.t1);
  root.style.setProperty('--text-2', tc.t2);
  root.style.setProperty('--text-3', tc.t3);

  const lc = LINE_CONTRAST[settings.line_contrast || 3];
  root.style.setProperty('--border',       lc.border);
  root.style.setProperty('--border-light', lc.light);

  const hh = settings.hour_height || 60;
  root.style.setProperty('--hour-h', hh + 'px');
}

function hexToRgba(hex, alpha) {
  const r = parseInt(hex.slice(1,3), 16);
  const g = parseInt(hex.slice(3,5), 16);
  const b = parseInt(hex.slice(5,7), 16);
  return `rgba(${r},${g},${b},${alpha})`;
}
