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

export function applyTheme(settings) {
  const root = document.documentElement;
  root.style.setProperty('--primary',      settings.primary_color || '#4285f4');
  root.style.setProperty('--primary-dim',  hexToRgba(settings.primary_color || '#4285f4', 0.15));
  root.style.setProperty('--accent',       settings.accent_color  || '#ea4335');
  root.style.setProperty('--today-color',  settings.today_color   || '#4285f4');
}

function hexToRgba(hex, alpha) {
  const r = parseInt(hex.slice(1,3), 16);
  const g = parseInt(hex.slice(3,5), 16);
  const b = parseInt(hex.slice(5,7), 16);
  return `rgba(${r},${g},${b},${alpha})`;
}
