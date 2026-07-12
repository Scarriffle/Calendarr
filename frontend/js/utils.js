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

// Title to render for an event: the server-decorated one (birthday age, group
// prefix) wins over the raw title, which stays untouched for editing.
export function eventTitle(ev) {
  return ev.display_title || ev.title || '';
}

// Small inline cake icon for birthday events, sized to the surrounding text and
// tinted with the current text colour so it matches every bar it's dropped into.
export function birthdayIconSvg() {
  return '<svg viewBox="0 0 24 24" aria-hidden="true" '
    + 'style="width:0.85em;height:0.85em;vertical-align:-0.1em;margin-right:2px;flex:0 0 auto">'
    + '<path fill="currentColor" d="M12 6c1.11 0 2-.9 2-2 0-.38-.1-.73-.29-1.03L12 0l-1.71 2.97'
    + 'c-.19.3-.29.65-.29 1.03 0 1.1.9 2 2 2zm4.6 9.99l-1.07-1.07-1.08 1.07c-1.3 1.3-3.58 1.31-4.89 0'
    + 'l-1.07-1.07-1.09 1.07C6.75 16.64 5.88 17 4.96 17c-.73 0-1.4-.23-1.96-.61V21c0 .55.45 1 1 1h16'
    + 'c.55 0 1-.45 1-1v-4.61c-.56.38-1.23.61-1.96.61-.92 0-1.79-.36-2.44-1.01zM18 9h-5V7h-2v2H6'
    + 'c-1.66 0-3 1.34-3 3v1.54c0 1.08.88 1.96 1.96 1.96.52 0 1.02-.2 1.38-.57l2.14-2.13 2.13 2.13'
    + 'c.74.74 2.03.74 2.77 0l2.14-2.13 2.13 2.13c.37.37.86.57 1.38.57 1.08 0 1.96-.88 1.96-1.96V12'
    + 'c.01-1.66-1.33-3-2.99-3z"/></svg>';
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

// ── Safe HTML rendering for event descriptions ───────────────────────────
// External calendars (CalDAV, iCal) often store rich-text descriptions as raw
// HTML. We render a small allowlist of formatting tags so links/line breaks
// look right, but strip everything dangerous (scripts, event handlers, inline
// styles) — we never execute code from a description.
const ALLOWED_TAGS = new Set(['A', 'BR', 'P', 'DIV', 'B', 'STRONG', 'I', 'EM', 'U', 'UL', 'OL', 'LI', 'SPAN']);
const URL_RE = /(https?:\/\/[^\s<]+[^\s<.,:;!?)\]}'"])/g;

function makeSafeLink(href, text) {
  const a = document.createElement('a');
  a.href = href;
  a.textContent = text;
  a.target = '_blank';
  a.rel = 'noopener noreferrer';
  return a;
}

// Replace bare URLs inside a text node with clickable <a> elements.
function linkifyTextNode(node, out) {
  const text = node.nodeValue;
  let last = 0;
  let m;
  URL_RE.lastIndex = 0;
  while ((m = URL_RE.exec(text)) !== null) {
    if (m.index > last) out.appendChild(document.createTextNode(text.slice(last, m.index)));
    out.appendChild(makeSafeLink(m[0], m[0]));
    last = m.index + m[0].length;
  }
  if (last < text.length) out.appendChild(document.createTextNode(text.slice(last)));
}

// Recursively copy `src` into `dest`, keeping only allowlisted tags/attributes.
function sanitizeInto(src, dest) {
  src.childNodes.forEach(node => {
    if (node.nodeType === Node.TEXT_NODE) {
      linkifyTextNode(node, dest);
      return;
    }
    if (node.nodeType !== Node.ELEMENT_NODE) return;
    const tag = node.tagName;
    if (!ALLOWED_TAGS.has(tag)) {
      // Drop the tag but keep its (sanitized) contents.
      sanitizeInto(node, dest);
      return;
    }
    let el;
    if (tag === 'A') {
      const href = node.getAttribute('href') || '';
      if (/^(https?:|mailto:)/i.test(href)) {
        el = makeSafeLink(href, '');
      } else {
        // Unsafe/relative href: render as plain text container.
        el = document.createElement('span');
      }
    } else {
      el = document.createElement(tag.toLowerCase());
    }
    sanitizeInto(node, el);
    dest.appendChild(el);
  });
}

// Returns a sanitized HTML string for an event description, safe for innerHTML.
export function renderDescriptionHtml(raw) {
  if (!raw) return '';
  const hasHtml = /<[a-z][\s\S]*>/i.test(raw);
  const doc = new DOMParser().parseFromString(
    hasHtml ? raw : raw.replace(/\n/g, '<br>'), 'text/html');
  const out = document.createElement('div');
  sanitizeInto(doc.body, out);
  return out.innerHTML;
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
