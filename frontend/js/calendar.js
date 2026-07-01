import { api } from './api.js';
import { applyTheme, isToday, isSameDay, toLocalDatetimeInput, toDateInput, dateKey, dayOfWeek, weekStart, renderDescriptionHtml, DEFAULT_TEXT_COLOR, DEFAULT_LINE_COLOR, DEFAULT_BG_COLOR } from './utils.js';
import { renderMonth }  from './views/month.js';
import { renderWeek }   from './views/week.js';
import { renderAgenda } from './views/agenda.js';
import { renderQuarter } from './views/quarter.js';
import { openColorPicker } from './color-picker.js';
import { openDatePicker, formatDtDisplay } from './date-picker.js';
import { t, setLang, getLang } from './i18n.js';
import { APP_VERSION } from './version.js';

// Version im Impressum/Sidebar sichtbar, nicht im Tab-Titel.
document.title = 'Calendarr';
document.addEventListener('DOMContentLoaded', () => {
  const imp = document.getElementById('impressum-version');
  if (imp) imp.textContent = `Calendarr ${APP_VERSION}`;
  const side = document.getElementById('sidebar-copyright');
  if (side) side.innerHTML = `©&nbsp;2026&nbsp;Scarriffleservices&nbsp;·&nbsp;${APP_VERSION}`;
});

// Fetch avatar image as blob URL (with auth header)
function fetchAvatarBlob() {
  const token = localStorage.getItem('token');
  return fetch(`/api/profile/avatar?t=${Date.now()}`, {
    headers: token ? { 'Authorization': `Bearer ${token}` } : {}
  }).then(res => {
    if (!res.ok) throw new Error('No avatar');
    return res.blob();
  }).then(blob => URL.createObjectURL(blob));
}

// week start day global (loaded from settings)
let weekStartDay = 'monday';

// month names come from i18n: t('months')

let state = {
  currentDate: new Date(),
  // Default to today so the month-view selection is anchored to a fixed date.
  // (If left null the view falls back to currentDate, which then appears to
  // "follow" the cells while navigating/scrolling before any explicit click.)
  selectedDate: new Date(),
  currentView: 'month',
  events: [],
  accounts: [],
  localCalendars: [],
  icalSubscriptions: [],
  googleAccounts: [],
  haAccounts: [],
  settings: {},
  dimPast: false,
  editingEvent: null,      // null = new event
  selectedEventColor: '',  // '' = use calendar color
  groups: [],
  activeGroupId: null,     // when set, the calendar shows the combined group view
  activeGroupDetail: null, // full detail (members + colours) of the active group
  hiddenGroupMembers: new Set(), // member ids / 'gc' hidden in the group overlay
};

// ── URL state ────────────────────────────────────────────
// View + Date werden in der URL als #date=YYYY-MM-DD&view=<view> gespiegelt,
// damit Reload/PWA-restore den letzten Stand wiederherstellen statt auf
// heute zu springen.
const VALID_VIEWS = ['month', 'week', 'day', 'quarter', 'agenda'];

function readUrlState() {
  const hash = window.location.hash.replace(/^#/, '');
  if (!hash) return {};
  const params = new URLSearchParams(hash);
  const out = {};
  const view = params.get('view');
  if (view && VALID_VIEWS.includes(view)) out.view = view;
  const date = params.get('date');
  if (date && /^\d{4}-\d{2}-\d{2}$/.test(date)) {
    const d = new Date(date + 'T00:00:00');
    if (!isNaN(d.getTime())) out.date = d;
  }
  out.settings = params.get('settings') === '1';
  const stab = params.get('stab');
  if (stab && ['profile','general','accounts','users'].includes(stab)) out.stab = stab;
  return out;
}

// Tracks whether the settings modal is open, so a reload returns to settings
// instead of the calendar view.
let uiSettingsOpen = false;

function writeUrlState() {
  const d = state.currentDate;
  const dateStr = `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
  let newHash = `date=${dateStr}&view=${state.currentView}`;
  if (uiSettingsOpen) {
    newHash += '&settings=1';
    const activeTab = document.querySelector('.settings-nav-btn.active');
    if (activeTab) newHash += `&stab=${activeTab.dataset.panel}`;
  }
  if (window.location.hash.replace(/^#/,'') !== newHash) {
    // replaceState statt pushState: prev/next-Klicks sollen nicht jeden
    // einzelnen Tag in den Browser-History-Stack drücken
    window.history.replaceState(null, '', '#' + newHash);
  }
}

// ── Public init ───────────────────────────────────────────
export async function initCalendar() {
  const [settings, accounts, localCalendars, icalSubscriptions, googleAccounts, haAccounts] = await Promise.all([
    api.get('/settings/'),
    api.get('/caldav/accounts'),
    api.get('/local/calendars').catch(() => []),
    api.get('/ical/subscriptions').catch(() => []),
    api.get('/google/accounts').catch(() => []),
    api.get('/homeassistant/accounts').catch(() => []),
  ]);

  state.settings = settings;
  state.accounts = accounts;
  state.localCalendars = localCalendars;
  state.icalSubscriptions = icalSubscriptions;
  state.googleAccounts = googleAccounts;
  state.haAccounts = haAccounts;
  state.currentView = settings.default_view || 'month';
  state.dimPast = settings.dim_past_events;
  weekStartDay = settings.week_start_day || 'monday';

  // URL state takes precedence over defaults (settings + today)
  const urlState = readUrlState();
  if (urlState.date) state.currentDate = urlState.date;
  if (urlState.view) state.currentView = urlState.view;
  // Preserve the settings flag through the first writeUrlState() (fired by the
  // initial fetchAndRender) so a reload reopens settings instead of stripping it.
  uiSettingsOpen = urlState.settings === true;

  setLang(settings.language || 'de');
  applyTheme(settings);
  updateViewButtons();
  renderCalendarList();
  renderMiniCal();
  await fetchAndRender();
  bindTopbar();
  bindSidebar();
  bindEventModal();
  bindAccountModal();
  bindLocalCalModal();
  bindICalSubModal();
  bindHAAccountModal();
  bindSettingsModal();
  bindProfileModal();
  bindGroupUI();
  bindSwipeNavigation();
  handleHAOAuthReturn();
  loadGroups();

  // Reopen the settings modal after a reload if the URL says we were in it.
  if (urlState.settings) openSettingsModal();

  // Browser-Back/Forward: URL-Hash → State synchronisieren
  window.addEventListener('hashchange', () => {
    const u = readUrlState();
    let changed = false;
    if (u.view && u.view !== state.currentView) {
      state.currentView = u.view;
      updateViewButtons();
      changed = true;
    }
    if (u.date && !isSameDay(u.date, state.currentDate)) {
      state.currentDate = u.date;
      changed = true;
    }
    if (changed) fetchAndRender();
  });
}

function handleHAOAuthReturn() {
  const params = new URLSearchParams(window.location.search);
  const errMap = {
    no_code: 'Home Assistant hat keinen Autorisierungscode zurückgegeben',
    state_expired: 'Die Anmeldung ist abgelaufen, bitte erneut versuchen',
    ha_unreachable: 'Home Assistant nicht erreichbar',
    token_exchange_failed: 'Token-Austausch mit Home Assistant fehlgeschlagen',
    calendars_failed: 'Kalender konnten nicht geladen werden',
  };
  if (params.has('ha_connected')) {
    showToast('Home Assistant verbunden');
    window.history.replaceState({}, '', window.location.pathname + window.location.hash);
    fetchAndRender(true);
    api.get('/homeassistant/accounts').then(accs => {
      state.haAccounts = accs || [];
      renderCalendarList();
      renderAllAccounts?.();
    }).catch(() => {});
  } else if (params.has('ha_error')) {
    const code = params.get('ha_error');
    showToast(errMap[code] || `HA-Anmeldung fehlgeschlagen: ${code}`, true);
    window.history.replaceState({}, '', window.location.pathname + window.location.hash);
  }
}

// ── Event cache ───────────────────────────────────────────
const CACHE_BUF      = 300 * 86400000; // initial ±10 months around the view
const PREFETCH_EXT   = 180 * 86400000; // extend by ~6 months when triggered
const PREFETCH_EDGE  =  90 * 86400000; // trigger when within ~3 months of cache edge

const eventCache = {
  start: null, end: null, events: [],
  _fwdPending: false, _bwdPending: false,
};

function invalidateCache() {
  eventCache.start      = null;
  eventCache.end        = null;
  eventCache.events     = [];
  eventCache._fwdPending = false;
  eventCache._bwdPending = false;
}

function _mergeEvents(newEvents) {
  const seen = new Set(eventCache.events.map(e => e.id + '@@' + (e.url || '')));
  for (const e of newEvents) {
    const k = e.id + '@@' + (e.url || '');
    if (!seen.has(k)) { seen.add(k); eventCache.events.push(e); }
  }
}

// Patch calendarColor in-place for all cached events belonging to a calendar,
// then re-render immediately without a network round-trip.
function applyCalendarColor(source, calId, color) {
  const id = String(calId);
  eventCache.events.forEach(ev => {
    if (ev.source !== source) return;
    const cid = String(ev.calendar_id);
    if (cid === id || cid === source + '-' + id || cid.replace(source + '-', '') === id) {
      ev.calendarColor = color;
    }
  });
  state.events = eventCache.events;
  renderCalendarList();
  renderView();
}

// Patch a single event in cache after edit/save, then re-render immediately.
// 'patch' is the new field values to merge into the existing cached event.
function applyEventPatch(eventId, eventUrl, patch) {
  const targetUrl = eventUrl || '';
  eventCache.events.forEach(ev => {
    if (ev.id === eventId && (ev.url || '') === targetUrl) {
      Object.assign(ev, patch);
    }
  });
  state.events = eventCache.events;
  renderView();
}

// Fire-and-forget: extend the cache toward whichever edge the view is approaching
function prefetchIfNeeded(viewStart, viewEnd) {
  if (!eventCache.start || !eventCache.end) return;

  if (!eventCache._fwdPending && (eventCache.end - viewEnd) < PREFETCH_EDGE) {
    eventCache._fwdPending = true;
    const from = new Date(eventCache.end);
    const to   = new Date(eventCache.end.getTime() + PREFETCH_EXT);
    api.get(`/caldav/events?start=${from.toISOString()}&end=${to.toISOString()}`)
      .then(r => { _mergeEvents(r.events || r); eventCache.end = to; })
      .catch(() => {})
      .finally(() => { eventCache._fwdPending = false; });
  }

  if (!eventCache._bwdPending && (viewStart - eventCache.start) < PREFETCH_EDGE) {
    eventCache._bwdPending = true;
    const from = new Date(eventCache.start.getTime() - PREFETCH_EXT);
    const to   = new Date(eventCache.start);
    api.get(`/caldav/events?start=${from.toISOString()}&end=${to.toISOString()}`)
      .then(r => { _mergeEvents(r.events || r); eventCache.start = from; })
      .catch(() => {})
      .finally(() => { eventCache._bwdPending = false; });
  }
}

// ── Data fetching ─────────────────────────────────────────
function firstName(name) {
  if (!name) return '';
  return String(name).trim().split(/\s+/)[0];
}

// Stable per-owner colour so each member's events read as a group in the
// combined view (Google-Family style).
const OWNER_PALETTE = ['#4285f4', '#ea4335', '#34a853', '#fbbc05', '#9c27b0', '#ff7043', '#46bdc6', '#7090c0'];
function ownerColor(ownerId) {
  if (ownerId == null) return null;
  return OWNER_PALETTE[(Number(ownerId) >>> 0) % OWNER_PALETTE.length];
}

// Per-user (per-device) member-colour overrides for the group overlay, so each
// viewer can recolour members just for their own view. Kept in localStorage,
// keyed by group id then member key ("<userId>" or "gc" for the group calendar).
function loadGroupColors() {
  try { return JSON.parse(localStorage.getItem('groupMemberColors') || '{}'); } catch (e) { return {}; }
}
function groupColorOverride(groupId, key) {
  return (loadGroupColors()[groupId] || {})[key] || null;
}
function setGroupColorOverride(groupId, key, hex) {
  const all = loadGroupColors();
  all[groupId] = all[groupId] || {};
  if (hex) all[groupId][key] = hex; else delete all[groupId][key];
  try { localStorage.setItem('groupMemberColors', JSON.stringify(all)); } catch (e) { /* ignore */ }
}

async function fetchAndRender(force = false, silent = false) {
  const { start, end } = getViewRange();

  // ── Combined group view ────────────────────────────────
  // No client cache here; reload the combined events for the visible range.
  if (state.activeGroupId) {
    const fStart = new Date(start.getTime() - CACHE_BUF);
    const fEnd   = new Date(end.getTime()   + CACHE_BUF);
    if (!silent) showLoading();
    try {
      const resp = await api.get(
        `/groups/${state.activeGroupId}/combined?start=${fStart.toISOString()}&end=${fEnd.toISOString()}`);
      const me = JSON.parse(localStorage.getItem('user') || '{}');
      const evs = (resp.events || []).map(ev => {
        const ownerId = ev.owner && ev.owner.id;
        // The server provides the decorated `display_title` (group icon + owner
        // prefix) so web, iOS and Android render identically; fall back to the
        // client-side prefix only for older servers.
        let title = ev.display_title;
        if (!title) {
          const ownerName = ev.owner && ev.owner.display_name;
          const isMine = ownerId != null && me.id != null && ownerId === me.id;
          if (ev.is_group_event) {
            const cName = ev.creator && ev.creator.display_name;
            const cId = ev.creator && ev.creator.id;
            title = (cName && cId !== me.id) ? `👥 ${firstName(cName)}: ${ev.title}` : `👥 ${ev.title}`;
          } else if (ownerName && !isMine) {
            title = `${firstName(ownerName)}: ${ev.title}`;
          } else {
            title = ev.title;
          }
        }
        // Colour: this viewer's local override first, else the server-defined
        // member/group colour, else a palette fallback.
        const ownerKey = ev.is_group_event ? 'gc' : (ownerId != null ? String(ownerId) : null);
        const override = ownerKey ? groupColorOverride(state.activeGroupId, ownerKey) : null;
        const color = override || ev.display_color || ownerColor(ownerId) || ev.color;
        return { ...ev, title, color };
      });
      eventCache.start = null; eventCache.end = null; // invalidate normal cache
      state.events = evs;
    } catch (e) {
      showToast(e.message, true);
      state.events = [];
    }
    renderView();
    updateTitle();
    renderMiniCal();
    return;
  }

  // Cache hit: requested range is fully within what we already have
  if (!force && eventCache.start && eventCache.end &&
      start >= eventCache.start && end <= eventCache.end) {
    state.events = eventCache.events;
    renderView();
    updateTitle();
    renderMiniCal();
    writeUrlState();
    prefetchIfNeeded(start, end); // extend cache in background if approaching an edge
    return;
  }

  // Cache miss: fetch a wider window (±8 weeks) so subsequent navigation is instant
  const fetchStart = new Date(start.getTime() - CACHE_BUF);
  const fetchEnd   = new Date(end.getTime()   + CACHE_BUF);

  if (!silent) showLoading();
  try {
    const resp = await api.get(`/caldav/events?start=${fetchStart.toISOString()}&end=${fetchEnd.toISOString()}`);
    const events = resp.events || resp;
    if (resp.errors && resp.errors.length) {
      for (const err of resp.errors) {
        showToast(`Google (${err.email}): Token abgelaufen – bitte Konto trennen und neu verbinden`, true);
      }
    }
    eventCache.start  = fetchStart;
    eventCache.end    = fetchEnd;
    eventCache.events = events;
    state.events = events;
  } catch (e) {
    showToast(t('error_load_events') + ': ' + e.message, true);
    state.events = [];
  }
  renderView();
  updateTitle();
  renderMiniCal();
  writeUrlState();
}

function getViewRange() {
  const d = state.currentDate;
  let start, end;

  if (state.currentView === 'month') {
    // Rolling view: 5 weeks from the start of currentDate's week
    start = weekStart(d, weekStartDay);
    start.setDate(start.getDate() - 1); // 1-day buffer
    end = new Date(start);
    end.setDate(start.getDate() + 37);  // 5 weeks + buffer
  } else if (state.currentView === 'week') {
    start = weekStart(d, weekStartDay);
    end = new Date(start);
    end.setDate(start.getDate() + 7);
  } else if (state.currentView === 'day') {
    start = new Date(d);
    start.setHours(0, 0, 0, 0);
    end = new Date(start);
    end.setDate(end.getDate() + 1);
  } else if (state.currentView === 'quarter') {
    const q = Math.floor(d.getMonth() / 3);
    start = new Date(d.getFullYear(), q * 3, 1);
    end   = new Date(d.getFullYear(), q * 3 + 3, 1);
  } else { // agenda
    start = new Date(d);
    start.setHours(0, 0, 0, 0);
    end = new Date(start);
    end.setDate(end.getDate() + 60);
  }
  return { start, end };
}

// ── Rendering ─────────────────────────────────────────────
function renderView() {
  const container = document.getElementById('view-container');
  const evs = filterEvents(state.events);

  if (state.currentView === 'month') {
    renderMonth(container, state.currentDate, evs,
      (date, action, mouseEvent) => {
        if (action === 'navigate') {
          state.currentDate = date;
          state.selectedDate = date;
          state.currentView = 'day';
          updateViewButtons();
          fetchAndRender();
        } else if (action === 'context') {
          state.selectedDate = date;
          showDayContextMenu(date, mouseEvent);
          renderView();
        } else {
          // 'select' — only update selectedDate, don't shift the view
          state.selectedDate = date;
          renderView();
        }
      },
      showEventPopup,
      weekStartDay,
      state.selectedDate
    );
  } else if (state.currentView === 'week') {
    renderWeek(container, state.currentDate, evs,
      (date, switchDay) => {
        if (switchDay) { state.currentDate = date; state.currentView = 'day'; updateViewButtons(); fetchAndRender(); }
        else openNewEventModal(date);
      },
      showEventPopup,
      false,
      weekStartDay,
      state.settings.hour_height || 44
    );
  } else if (state.currentView === 'day') {
    renderWeek(container, state.currentDate, evs,
      (date, switchDay) => { if (!switchDay) openNewEventModal(date); },
      showEventPopup,
      true,
      weekStartDay,
      state.settings.hour_height || 44
    );
  } else if (state.currentView === 'quarter') {
    renderQuarter(container, state.currentDate, evs,
      date => { state.currentDate = date; state.currentView = 'day'; updateViewButtons(); fetchAndRender(); },
      showEventPopup,
      weekStartDay
    );
  } else {
    renderAgenda(container, state.currentDate, evs, showEventPopup);
  }
}

function filterEvents(events) {
  // Group overlay: hide individual members' calendars / the group calendar
  // (Outlook-style), filtered client-side by event owner.
  const hidden = state.hiddenGroupMembers;
  if (state.activeGroupId && hidden && hidden.size) {
    return events.filter(ev => {
      if (ev.is_group_event) return !hidden.has('gc');
      const oid = ev.owner && ev.owner.id;
      return oid == null || !hidden.has(oid);
    });
  }
  // If dimPast is enabled, events are still shown but CSS handles opacity via .past class
  return events;
}

function showLoading() {
  document.getElementById('view-container').innerHTML =
    `<div class="loading-view"><div class="spinner"></div></div>`;
}

function updateTitle() {
  const d = state.currentDate;
  let main = '';   // primary label (months / day range)
  let year = '';   // year — separated so mobile can wrap to a 2nd line
  const M = t('months');
  if (state.currentView === 'month') {
    const ws = weekStart(d, weekStartDay);
    const we = new Date(ws); we.setDate(we.getDate() + 34);
    const Ms = t('months_short');
    if (ws.getFullYear() !== we.getFullYear()) {
      // Cross-year: keep both years inline in main, no separate year
      main = `${Ms[ws.getMonth()]} ${ws.getFullYear()} – ${Ms[we.getMonth()]} ${we.getFullYear()}`;
    } else if (ws.getMonth() !== we.getMonth()) {
      main = `${Ms[ws.getMonth()]} – ${Ms[we.getMonth()]}`;
      year = `${we.getFullYear()}`;
    } else {
      main = `${M[ws.getMonth()]}`;
      year = `${ws.getFullYear()}`;
    }
  } else if (state.currentView === 'week') {
    const mon = weekStart(d, weekStartDay);
    const sun = new Date(mon);
    sun.setDate(mon.getDate() + 6);
    const sameMonth = mon.getMonth() === sun.getMonth();
    main = sameMonth
      ? `${mon.getDate()}. – ${sun.getDate()}. ${M[sun.getMonth()]}`
      : `${mon.getDate()}. ${M[mon.getMonth()]} – ${sun.getDate()}. ${M[sun.getMonth()]}`;
    year = `${sun.getFullYear()}`;
  } else if (state.currentView === 'day') {
    main = `${d.getDate()}. ${M[d.getMonth()]}`;
    year = `${d.getFullYear()}`;
  } else if (state.currentView === 'quarter') {
    const q = Math.floor(d.getMonth() / 3) + 1;
    main = `Q${q}`;
    year = `${d.getFullYear()}`;
  } else {
    main = `${d.getDate()}. ${M[d.getMonth()]}`;
    year = `${d.getFullYear()}`;
  }
  const fullText = year ? `${main} ${year}` : main;
  const titleEl = document.getElementById('view-title');
  titleEl.innerHTML =
    `<span class="view-title-main">${main}</span>` +
    (year ? `<span class="view-title-year">${year}</span>` : '');
  document.title = `Calendarr – ${fullText}`;
}

function updateViewButtons() {
  document.querySelectorAll('.view-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.view === state.currentView);
  });
}

// ── Mini Calendar ─────────────────────────────────────────
function renderMiniCal() {
  const d = state.currentDate;
  const miniD = new Date(d.getFullYear(), d.getMonth(), 1);
  document.getElementById('mini-title').textContent =
    `${t('months')[miniD.getMonth()]} ${miniD.getFullYear()}`;

  const firstDay = new Date(miniD.getFullYear(), miniD.getMonth(), 1);
  const gridStart = new Date(firstDay);
  gridStart.setDate(gridStart.getDate() - dayOfWeek(firstDay, weekStartDay));

  // Update mini-cal DOW headers based on weekStartDay
  const miniDowEls = document.querySelectorAll('.mini-cal-grid .mini-dow');
  const DOW_MONDAY = ['Mo','Di','Mi','Do','Fr','Sa','So'];
  const DOW_SUNDAY = ['So','Mo','Di','Mi','Do','Fr','Sa'];
  const DOW_LABELS = weekStartDay === 'sunday' ? DOW_SUNDAY : DOW_MONDAY;
  miniDowEls.forEach((el, i) => { el.textContent = DOW_LABELS[i]; });

  // Build event date set — mark every day an event spans, not just its start
  // day, so multi-day events (Urlaub/Ferien) show a dot across the whole range.
  const eventDates = new Set();
  state.events.forEach(ev => {
    const s = new Date(ev.start);
    let end = new Date(ev.end || ev.start);
    // All-day events store an exclusive end → step back to the last real day.
    if (ev.allDay) { end.setHours(0, 0, 0, 0); if (end > s) end.setDate(end.getDate() - 1); }
    const cur  = new Date(s.getFullYear(),   s.getMonth(),   s.getDate());
    const last = new Date(end.getFullYear(), end.getMonth(), end.getDate());
    let guard = 0;
    while (cur <= last && guard++ < 400) {
      eventDates.add(`${cur.getFullYear()}-${cur.getMonth()}-${cur.getDate()}`);
      cur.setDate(cur.getDate() + 1);
    }
  });

  const days = [];
  const cur = new Date(gridStart);
  for (let i = 0; i < 42; i++) {
    days.push(new Date(cur));
    cur.setDate(cur.getDate() + 1);
  }

  const html = days.map(day => {
    const isOther = day.getMonth() !== miniD.getMonth();
    const isToday_ = isToday(day);
    const isSelected = isSameDay(day, state.currentDate);
    const hasEvs = eventDates.has(`${day.getFullYear()}-${day.getMonth()}-${day.getDate()}`);
    const cls = [
      'mini-day',
      isOther   ? 'other-month' : '',
      isToday_  ? 'today'    : '',
      isSelected && !isToday_ ? 'selected' : '',
      hasEvs    ? 'has-events' : '',
    ].filter(Boolean).join(' ');
    return `<div class="${cls}" data-date="${dateKey(day)}">${day.getDate()}</div>`;
  }).join('');

  document.getElementById('mini-days').innerHTML = html;

  document.querySelectorAll('.mini-day').forEach(el => {
    el.addEventListener('click', () => {
      state.currentDate = new Date(el.dataset.date + 'T00:00:00');
      if (state.currentView === 'agenda' || state.currentView === 'month') {
        // Stay in current view but update date
      }
      fetchAndRender();
    });
  });

  document.getElementById('mini-prev').onclick = () => {
    state.currentDate = new Date(state.currentDate.getFullYear(), state.currentDate.getMonth() - 1, 1);
    renderMiniCal();
    fetchAndRender();
  };
  document.getElementById('mini-next').onclick = () => {
    state.currentDate = new Date(state.currentDate.getFullYear(), state.currentDate.getMonth() + 1, 1);
    renderMiniCal();
    fetchAndRender();
  };
}

// ── Calendar List ─────────────────────────────────────────
const CAL_ORDER_KEY = 'cal_order';
function loadCalOrder() {
  try { return JSON.parse(localStorage.getItem(CAL_ORDER_KEY) || '[]'); }
  catch (e) { return []; }
}
function saveCalOrder(keys) {
  localStorage.setItem(CAL_ORDER_KEY, JSON.stringify(keys));
}

// Drag & drop reordering of the flat calendar list (persisted per device).
// The dragged row is moved live among its siblings during dragover, so the
// list visibly "makes space" and you can see where it will land.
function bindCalDragReorder(container) {
  // Find the row the cursor is currently above (by vertical midpoint), so we
  // know before which sibling to insert the dragged row.
  const rowAfter = (y) => {
    const rows = [...container.querySelectorAll('.cal-item:not(.cal-dragging)')];
    return rows.reduce((closest, row) => {
      const box = row.getBoundingClientRect();
      const offset = y - box.top - box.height / 2;
      if (offset < 0 && offset > closest.offset) return { offset, el: row };
      return closest;
    }, { offset: Number.NEGATIVE_INFINITY, el: null }).el;
  };

  container.querySelectorAll('.cal-item').forEach(item => {
    item.addEventListener('dragstart', e => {
      // Don't start a drag from interactive children (checkbox, color dot, buttons).
      if (e.target.closest('input, button, .cal-item-dot')) { e.preventDefault(); return; }
      e.dataTransfer.effectAllowed = 'move';
      // Defer the class so the drag image is the full opaque row, then dim it.
      requestAnimationFrame(() => item.classList.add('cal-dragging'));
    });
    item.addEventListener('dragend', () => {
      item.classList.remove('cal-dragging');
      // Persist the final DOM order; no full re-render needed.
      saveCalOrder([...container.querySelectorAll('.cal-item')].map(el => el.dataset.key));
    });
  });

  // Live reorder: move the dragged row to the hovered position as the cursor
  // moves. Bound once on the (stable) container to avoid stacking listeners on
  // every re-render.
  if (!container.__dragBound) {
    container.__dragBound = true;
    container.addEventListener('dragover', e => {
      e.preventDefault();
      const dragging = container.querySelector('.cal-dragging');
      if (!dragging) return;
      const after = rowAfter(e.clientY);
      if (after == null) container.appendChild(dragging);
      else if (after !== dragging) container.insertBefore(dragging, after);
    });
  }
}

function renderCalendarList() {
  const container = document.getElementById('cal-list-items');
  // Eye-off (hide external calendar) and trash (delete local/ical) icons.
  const EYE_OFF = `<svg viewBox="0 0 24 24" fill="currentColor" width="14" height="14"><path d="M12 7c2.76 0 5 2.24 5 5 0 .65-.13 1.26-.36 1.83l2.92 2.92c1.51-1.26 2.7-2.89 3.43-4.75-1.73-4.39-6-7.5-11-7.5-1.4 0-2.74.25-3.98.7l2.16 2.16C10.74 7.13 11.35 7 12 7zM2 4.27l2.28 2.28.46.46C3.08 8.3 1.78 10.02 1 12c1.73 4.39 6 7.5 11 7.5 1.55 0 3.03-.3 4.38-.84l.42.42L19.73 22 21 20.73 3.27 3 2 4.27zM7.53 9.8l1.55 1.55c-.05.21-.08.43-.08.65 0 1.66 1.34 3 3 3 .22 0 .44-.03.65-.08l1.55 1.55c-.67.33-1.41.53-2.2.53-2.76 0-5-2.24-5-5 0-.79.2-1.53.53-2.2zm4.31-.78l3.15 3.15.02-.16c0-1.66-1.34-3-3-3l-.17.01z"/></svg>`;
  const TRASH = `<svg viewBox="0 0 24 24" fill="currentColor" width="14" height="14"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>`;
  const BELL = `<svg viewBox="0 0 24 24" fill="currentColor" width="14" height="14"><path d="M12 22c1.1 0 2-.9 2-2h-4c0 1.1.9 2 2 2zm6-6v-5c0-3.07-1.63-5.64-4.5-6.32V4c0-.83-.67-1.5-1.5-1.5s-1.5.67-1.5 1.5v.68C7.64 5.36 6 7.92 6 11v5l-2 2v1h16v-1l-2-2z"/></svg>`;
  const BELL_OFF = `<svg viewBox="0 0 24 24" fill="currentColor" width="14" height="14"><path d="M20 18.69L7.84 6.14 5.27 3.49 4 4.76l2.8 2.8v.01c-.52.99-.8 2.16-.8 3.42v5l-2 2v1h13.73l2 2L21 19.72l-1-1.03zM12 22c1.11 0 2-.89 2-2h-4c0 1.11.89 2 2 2zm6-7.32V11c0-3.08-1.64-5.64-4.5-6.32V4c0-.83-.67-1.5-1.5-1.5s-1.5.67-1.5 1.5v.68c-.15.03-.29.08-.42.12-.1.03-.2.07-.3.11h-.01c-.01 0-.01 0-.02.01-.23.09-.46.2-.68.31L18 14.68z"/></svg>`;
  const SHARE_ICON = `<svg viewBox="0 0 24 24" fill="currentColor" width="13" height="13"><path d="M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7c.05-.23.09-.46.09-.7s-.04-.47-.09-.7l7.05-4.11c.54.5 1.25.81 2.04.81 1.66 0 3-1.34 3-3s-1.34-3-3-3-3 1.34-3 3c0 .24.04.47.09.7L8.04 9.81C7.5 9.31 6.79 9 6 9c-1.66 0-3 1.34-3 3s1.34 3 3 3c.79 0 1.5-.31 2.04-.81l7.12 4.16c-.05.21-.08.43-.08.65 0 1.61 1.31 2.92 2.92 2.92s2.92-1.31 2.92-2.92-1.31-2.92-2.92-2.92z"/></svg>`;

  // Build a single flat list of all calendars. The source/account is shown
  // inline (small, grey) next to the name and section headers are gone, so the
  // whole list can be freely reordered via drag & drop.
  const entries = [];
  state.accounts.forEach(acc => {
    (acc.calendars || []).filter(c => !c.sidebar_hidden).forEach(cal => {
      entries.push({ key: `caldav:${cal.id}`, source: 'caldav', dataId: `data-cal-id="${cal.id}"`,
        name: cal.name, color: cal.color || '#4285f4', enabled: cal.enabled,
        reminders: true, remindersEnabled: cal.reminders_enabled !== false,
        sourceLabel: acc.name, remove: { icon: EYE_OFF, title: t('hide_cal') } });
    });
  });
  const groupVisibleId = state.settings && state.settings.group_visible_calendar_id;
  state.localCalendars.filter(c => c.owned !== false && !c.group).forEach(cal => {
    entries.push({ key: `local:${cal.id}`, source: 'local', dataId: `data-cal-id="${cal.id}"`,
      name: cal.name, color: cal.color, enabled: cal.enabled,
      reminders: true, remindersEnabled: cal.reminders_enabled !== false,
      sourceLabel: t('cal_local'), groupVisible: cal.id === groupVisibleId,
      remove: { icon: TRASH, title: t('remove_cal') } });
  });
  state.localCalendars.filter(c => c.owned === false && !c.group).forEach(cal => {
    entries.push({ key: `local:${cal.id}`, source: 'local', dataId: `data-cal-id="${cal.id}"`,
      name: cal.name, color: cal.color, enabled: cal.enabled,
      sourceLabel: `${t('shared_with_me')} · ${cal.shared_by || ''}`, remove: null });
  });
  // Group calendars (owned by the creator or reached via membership) — shown so
  // they can be toggled/recoloured. Owned group calendars can also be muted
  // (reminders), which the server then syncs; member-reached ones can't (no PUT).
  state.localCalendars.filter(c => c.group).forEach(cal => {
    entries.push({ key: `local:${cal.id}`, source: 'local', dataId: `data-cal-id="${cal.id}"`,
      name: cal.name, color: cal.color, enabled: cal.enabled,
      reminders: cal.owned !== false, remindersEnabled: cal.reminders_enabled !== false,
      sourceLabel: `${t('groups_title')} · ${cal.shared_by || ''}`,
      isGroupCal: true, groupIcon: groupIconForLocalCal(cal.id), remove: null });
  });
  state.icalSubscriptions.forEach(sub => {
    entries.push({ key: `ical:${sub.id}`, source: 'ical', dataId: `data-sub-id="${sub.id}"`,
      name: sub.name, color: sub.color, enabled: sub.enabled,
      reminders: true, remindersEnabled: sub.reminders_enabled !== false,
      sourceLabel: t('cal_ical'), remove: { icon: TRASH, title: t('remove_ical_sub') } });
  });
  state.googleAccounts.forEach(acc => {
    (acc.calendars || []).filter(c => !c.sidebar_hidden).forEach(cal => {
      entries.push({ key: `google:${cal.id}`, source: 'google', dataId: `data-cal-id="${cal.id}"`,
        name: cal.name, color: cal.color || '#4285f4', enabled: cal.enabled,
        reminders: true, remindersEnabled: cal.reminders_enabled !== false,
        sourceLabel: acc.email, remove: { icon: EYE_OFF, title: t('hide_cal') } });
    });
  });
  state.haAccounts.forEach(acc => {
    (acc.calendars || []).filter(c => !c.sidebar_hidden).forEach(cal => {
      entries.push({ key: `homeassistant:${cal.id}`, source: 'homeassistant', dataId: `data-cal-id="${cal.id}"`,
        name: cal.name, color: cal.color || '#03a9f4', enabled: cal.enabled,
        reminders: true, remindersEnabled: cal.reminders_enabled !== false,
        sourceLabel: acc.name, remove: { icon: EYE_OFF, title: t('hide_cal') } });
    });
  });

  // Apply the saved manual order (per device); unknown calendars append at end.
  const order = loadCalOrder();
  entries.sort((a, b) => {
    const ia = order.indexOf(a.key), ib = order.indexOf(b.key);
    if (ia === -1 && ib === -1) return 0;
    if (ia === -1) return 1;
    if (ib === -1) return -1;
    return ia - ib;
  });
  saveCalOrder(entries.map(e => e.key));

  if (!entries.length) {
    container.innerHTML = `<div style="padding:8px 16px;font-size:12px;color:var(--text-3)">${t('error_no_calendars')}</div>`;
    return;
  }

  container.innerHTML = entries.map(e =>
    `<div class="cal-item" draggable="true" data-key="${e.key}" data-source="${e.source}" ${e.dataId} title="${escHtml(e.name)} · ${escHtml(e.sourceLabel)}">
      <span class="cal-drag-handle" title="${t('drag_reorder')}">⠿</span>
      <input type="checkbox" ${e.enabled ? 'checked' : ''} data-source="${e.source}" ${e.dataId} />
      <div class="cal-item-dot" style="background:${e.color}" data-source="${e.source}" ${e.dataId} title="${t('change_color')}"></div>
      ${e.isGroupCal ? `<span class="cal-shared-flag" title="${escHtml(e.sourceLabel)}">${groupIconSvg(e.groupIcon || 'people', 13)}</span>` : ''}
      ${e.groupVisible ? `<span class="cal-shared-flag cal-shared-flag-own" title="${t('group_visible_flag')}">${shareIconSvg(state.settings?.share_calendar_icon || 'share', 13)}</span>` : ''}
      <span class="cal-item-name" data-source="${e.source}">${escHtml(e.name)}</span>
      ${e.reminders ? `<button class="icon-btn mini-btn cal-item-bell ${e.remindersEnabled ? '' : 'off'}" data-source="${e.source}" ${e.dataId} title="${e.remindersEnabled ? t('calendar_reminders_on') : t('calendar_reminders_off')}">${e.remindersEnabled ? BELL : BELL_OFF}</button>` : ''}
      ${e.remove ? `<button class="icon-btn mini-btn cal-item-remove" data-source="${e.source}" ${e.dataId} title="${e.remove.title}">${e.remove.icon}</button>` : ''}
    </div>`
  ).join('');

  bindCalDragReorder(container);

  // ── Checkbox handlers ──────────────────────────────────
  container.querySelectorAll('input[type=checkbox]').forEach(cb => {
    cb.addEventListener('change', async () => {
      const source = cb.dataset.source;
      let cacheCalId = null; // calendar_id value used in cached events

      if (source === 'caldav') {
        const calId = parseInt(cb.dataset.calId);
        await api.put(`/caldav/calendars/${calId}`, { enabled: cb.checked });
        for (const acc of state.accounts) {
          for (const cal of acc.calendars) {
            if (cal.id === calId) cal.enabled = cb.checked;
          }
        }
        cacheCalId = calId; // numeric integer in cached events
      } else if (source === 'local') {
        const calId = parseInt(cb.dataset.calId);
        const cal = state.localCalendars.find(c => c.id === calId);
        // `enabled` is the owner's property — only the owner may PUT it.
        // For shared/group calendars just toggle visibility client-side.
        if (cal && cal.owned !== false) {
          await api.put(`/local/calendars/${calId}`, { enabled: cb.checked });
        }
        if (cal) cal.enabled = cb.checked;
        cacheCalId = `local-${calId}`;
      } else if (source === 'ical') {
        const subId = parseInt(cb.dataset.subId);
        await api.put(`/ical/subscriptions/${subId}`, { enabled: cb.checked });
        const sub = state.icalSubscriptions.find(s => s.id === subId);
        if (sub) sub.enabled = cb.checked;
        cacheCalId = `ical-${subId}`;
      } else if (source === 'google') {
        const calId = parseInt(cb.dataset.calId);
        await api.put(`/google/calendars/${calId}`, { enabled: cb.checked });
        for (const acc of state.googleAccounts) {
          const cal = acc.calendars.find(c => c.id === calId);
          if (cal) cal.enabled = cb.checked;
        }
        cacheCalId = `google-${calId}`;
      } else if (source === 'homeassistant') {
        const calId = parseInt(cb.dataset.calId);
        await api.put(`/homeassistant/calendars/${calId}`, { enabled: cb.checked });
        for (const acc of state.haAccounts) {
          const cal = acc.calendars.find(c => c.id === calId);
          if (cal) cal.enabled = cb.checked;
        }
        cacheCalId = `homeassistant-${calId}`;
      }

      if (!cb.checked && cacheCalId !== null) {
        // Hiding: filter from cache instantly, no network call needed
        eventCache.events = eventCache.events.filter(ev => ev.calendar_id !== cacheCalId);
        state.events = eventCache.events;
        renderView();
        updateTitle();
        renderMiniCal();
      } else {
        // Showing: refetch silently — view stays visible, updates when done
        fetchAndRender(true, true);
      }
    });
  });

  // ── Reminder bell handlers (toggle reminders_enabled per calendar) ──
  container.querySelectorAll('.cal-item-bell').forEach(btn => {
    btn.addEventListener('click', async e => {
      e.stopPropagation();
      const source = btn.dataset.source;
      const id = parseInt(btn.dataset.calId || btn.dataset.subId);
      let cal = null;
      if (source === 'caldav') {
        for (const acc of state.accounts) { const c = acc.calendars.find(c => c.id === id); if (c) cal = c; }
      } else if (source === 'local') {
        cal = state.localCalendars.find(c => c.id === id);
      } else if (source === 'ical') {
        cal = state.icalSubscriptions.find(s => s.id === id);
      } else if (source === 'google') {
        for (const acc of state.googleAccounts) { const c = acc.calendars.find(c => c.id === id); if (c) cal = c; }
      } else if (source === 'homeassistant') {
        for (const acc of state.haAccounts) { const c = acc.calendars.find(c => c.id === id); if (c) cal = c; }
      }
      if (!cal) return;
      const newVal = cal.reminders_enabled === false; // toggle
      const path = source === 'ical'
        ? `/ical/subscriptions/${id}`
        : `/${source}/calendars/${id}`;
      try {
        await api.put(path, { reminders_enabled: newVal });
        cal.reminders_enabled = newVal;
        renderCalendarList();
      } catch (err) { showToast(err.message, true); }
    });
  });

  // ── Color dot handlers ─────────────────────────────────
  container.querySelectorAll('.cal-item-dot').forEach(dot => {
    dot.addEventListener('click', async e => {
      e.stopPropagation();
      const source = dot.dataset.source;
      if (source === 'caldav') {
        openCalColorPicker(dot, parseInt(dot.dataset.calId));
      } else if (source === 'local') {
        const calId = parseInt(dot.dataset.calId);
        const cal = state.localCalendars.find(c => c.id === calId);
        if (cal && cal.owned === false) { showToast(t('only_owner_color'), true); return; }
        const picked = await openColorPicker(dot, cal?.color || '#34a853');
        if (picked) {
          await api.put(`/local/calendars/${calId}`, { color: picked });
          if (cal) cal.color = picked;
          applyCalendarColor('local', calId, picked);
        }
      } else if (source === 'ical') {
        const subId = parseInt(dot.dataset.subId);
        const sub = state.icalSubscriptions.find(s => s.id === subId);
        const picked = await openColorPicker(dot, sub?.color || '#46bdc6');
        if (picked) {
          await api.put(`/ical/subscriptions/${subId}`, { color: picked });
          if (sub) sub.color = picked;
          applyCalendarColor('ical', subId, picked);
        }
      } else if (source === 'google') {
        const calId = parseInt(dot.dataset.calId);
        let gcal = null;
        for (const acc of state.googleAccounts) {
          gcal = acc.calendars.find(c => c.id === calId);
          if (gcal) break;
        }
        const picked = await openColorPicker(dot, gcal?.color || '#4285f4');
        if (picked) {
          await api.put(`/google/calendars/${calId}`, { color: picked });
          if (gcal) gcal.color = picked;
          applyCalendarColor('google', calId, picked);
        }
      } else if (source === 'homeassistant') {
        const calId = parseInt(dot.dataset.calId);
        let hacal = null;
        for (const acc of state.haAccounts) {
          hacal = acc.calendars.find(c => c.id === calId);
          if (hacal) break;
        }
        const picked = await openColorPicker(dot, hacal?.color || '#03a9f4');
        if (picked) {
          await api.put(`/homeassistant/calendars/${calId}`, { color: picked });
          if (hacal) hacal.color = picked;
          applyCalendarColor('homeassistant', calId, picked);
        }
      }
    });
  });

  // ── Rename on double-click ─────────────────────────────
  container.querySelectorAll('.cal-item-name').forEach(nameEl => {
    nameEl.addEventListener('dblclick', e => {
      e.stopPropagation();
      const item = nameEl.closest('.cal-item');
      const source = nameEl.dataset.source;
      const currentName = nameEl.textContent;
      const input = document.createElement('input');
      input.type = 'text';
      input.value = currentName;
      input.className = 'cal-rename-input';
      nameEl.replaceWith(input);
      input.focus();
      input.select();

      const save = async () => {
        const newName = input.value.trim();
        if (newName && newName !== currentName) {
          if (source === 'caldav') {
            const calId = parseInt(item.dataset.calId);
            await api.put(`/caldav/calendars/${calId}`, { name: newName });
            for (const acc of state.accounts) {
              for (const cal of acc.calendars) { if (cal.id === calId) cal.name = newName; }
            }
          } else if (source === 'local') {
            const calId = parseInt(item.dataset.calId);
            await api.put(`/local/calendars/${calId}`, { name: newName });
            const cal = state.localCalendars.find(c => c.id === calId);
            if (cal) cal.name = newName;
          } else if (source === 'ical') {
            const subId = parseInt(item.dataset.subId);
            await api.put(`/ical/subscriptions/${subId}`, { name: newName });
            const sub = state.icalSubscriptions.find(s => s.id === subId);
            if (sub) sub.name = newName;
          } else if (source === 'google') {
            const calId = parseInt(item.dataset.calId);
            await api.put(`/google/calendars/${calId}`, { name: newName });
            for (const acc of state.googleAccounts) {
              const cal = (acc.calendars || []).find(c => c.id === calId);
              if (cal) cal.name = newName;
            }
          } else if (source === 'homeassistant') {
            const calId = parseInt(item.dataset.calId);
            await api.put(`/homeassistant/calendars/${calId}`, { name: newName });
            for (const acc of state.haAccounts) {
              const cal = (acc.calendars || []).find(c => c.id === calId);
              if (cal) cal.name = newName;
            }
          }
        }
        renderCalendarList();
      };

      input.addEventListener('keydown', e => {
        if (e.key === 'Enter') save();
        if (e.key === 'Escape') renderCalendarList();
      });
      input.addEventListener('blur', save);
    });
  });

  // ── Remove handlers ────────────────────────────────────
  container.querySelectorAll('.cal-item-remove').forEach(btn => {
    btn.addEventListener('click', async e => {
      e.stopPropagation();
      const source = btn.dataset.source;
      let cacheCalId = null;
      if (source === 'caldav') {
        const calId = parseInt(btn.dataset.calId);
        await api.put(`/caldav/calendars/${calId}`, { enabled: false, sidebar_hidden: true });
        for (const acc of state.accounts) {
          for (const cal of acc.calendars) {
            if (cal.id === calId) { cal.enabled = false; cal.sidebar_hidden = true; }
          }
        }
        cacheCalId = calId;
      } else if (source === 'local') {
        if (!confirm(t('confirm_delete_local_cal'))) return;
        const calId = parseInt(btn.dataset.calId);
        await api.delete(`/local/calendars/${calId}`);
        state.localCalendars = state.localCalendars.filter(c => c.id !== calId);
        cacheCalId = `local-${calId}`;
      } else if (source === 'ical') {
        if (!confirm(t('confirm_remove_ical'))) return;
        const subId = parseInt(btn.dataset.subId);
        await api.delete(`/ical/subscriptions/${subId}`);
        state.icalSubscriptions = state.icalSubscriptions.filter(s => s.id !== subId);
        cacheCalId = `ical-${subId}`;
      } else if (source === 'google') {
        const calId = parseInt(btn.dataset.calId);
        await api.put(`/google/calendars/${calId}`, { enabled: false, sidebar_hidden: true });
        for (const acc of state.googleAccounts) {
          for (const cal of acc.calendars) {
            if (cal.id === calId) { cal.enabled = false; cal.sidebar_hidden = true; }
          }
        }
        cacheCalId = `google-${calId}`;
      } else if (source === 'homeassistant') {
        const calId = parseInt(btn.dataset.calId);
        await api.put(`/homeassistant/calendars/${calId}`, { enabled: false, sidebar_hidden: true });
        for (const acc of state.haAccounts) {
          for (const cal of acc.calendars) {
            if (cal.id === calId) { cal.enabled = false; cal.sidebar_hidden = true; }
          }
        }
        cacheCalId = `homeassistant-${calId}`;
      }
      if (cacheCalId !== null) {
        eventCache.events = eventCache.events.filter(ev => ev.calendar_id !== cacheCalId);
        state.events = eventCache.events;
      }
      renderCalendarList();
      renderView();
      updateTitle();
      renderMiniCal();
    });
  });
}

// ── Swipe navigation + long-press → context menu (mobile) ──
function bindSwipeNavigation() {
  const container = document.getElementById('view-container');
  if (!container) return;
  let startX = 0, startY = 0, startT = 0, active = false;
  let lpTimer = null, lpTarget = null, lpFired = false;

  container.addEventListener('touchstart', e => {
    if (e.touches.length !== 1) { active = false; return; }
    startX = e.touches[0].clientX;
    startY = e.touches[0].clientY;
    startT = Date.now();
    active = true;
    lpFired = false;

    // Long-press → context menu (only on day cells, not on events)
    lpTarget = e.target.closest('.month-col, .week-day-col');
    if (lpTarget && !e.target.closest('.month-span-event, .week-event')) {
      lpTimer = setTimeout(() => {
        const t = e.touches[0];
        const ev = new MouseEvent('contextmenu', {
          bubbles: true, cancelable: true,
          clientX: t.clientX, clientY: t.clientY,
        });
        lpTarget.dispatchEvent(ev);
        lpFired = true;
      }, 500);
    }
  }, { passive: true });

  container.addEventListener('touchmove', e => {
    if (!active) return;
    const t = e.touches[0];
    if (Math.abs(t.clientX - startX) > 8 || Math.abs(t.clientY - startY) > 8) {
      if (lpTimer) { clearTimeout(lpTimer); lpTimer = null; }
    }
  }, { passive: true });

  container.addEventListener('touchend', e => {
    if (lpTimer) { clearTimeout(lpTimer); lpTimer = null; }
    if (!active) return;
    active = false;

    // Suppress the click that follows a long-press
    if (lpFired) {
      const blocker = ev => { ev.stopPropagation(); ev.preventDefault(); };
      document.addEventListener('click', blocker, { capture: true, once: true });
      lpFired = false;
      return;
    }

    const t = e.changedTouches[0];
    const dx = t.clientX - startX;
    const dy = t.clientY - startY;
    const dt = Date.now() - startT;
    // Horizontal swipe: ≥ 60px, mostly horizontal, faster than 700ms
    if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy) * 1.5 && dt < 700) {
      navigate(dx < 0 ? 1 : -1);
      fetchAndRender();
    }
  }, { passive: true });

  container.addEventListener('touchcancel', () => {
    if (lpTimer) { clearTimeout(lpTimer); lpTimer = null; }
    active = false;
  }, { passive: true });
}

// ── Navigation ────────────────────────────────────────────
function navigate(dir) {
  const d = state.currentDate;
  if (state.currentView === 'month') {
    // Buttons jump 4 weeks (one screenful)
    state.currentDate = new Date(d);
    state.currentDate.setDate(d.getDate() + dir * 28);
  } else if (state.currentView === 'week') {
    state.currentDate = new Date(d);
    state.currentDate.setDate(d.getDate() + dir * 7);
  } else if (state.currentView === 'day') {
    state.currentDate = new Date(d);
    state.currentDate.setDate(d.getDate() + dir);
  } else if (state.currentView === 'quarter') {
    state.currentDate = new Date(d.getFullYear(), d.getMonth() + dir * 3, 1);
  } else {
    state.currentDate = new Date(d);
    state.currentDate.setDate(d.getDate() + dir * 30);
  }
  fetchAndRender();
}

// ── Topbar bindings ───────────────────────────────────────
function bindTopbar() {
  document.getElementById('btn-today').onclick = () => {
    state.currentDate = new Date();
    fetchAndRender();
  };
  document.getElementById('btn-prev').onclick = () => navigate(-1);
  document.getElementById('btn-next').onclick = () => navigate(1);

  document.querySelectorAll('.view-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      state.currentView = btn.dataset.view;
      updateViewButtons();
      fetchAndRender();
    });
  });

  document.getElementById('btn-settings').onclick = openSettingsModal;
  document.getElementById('btn-create-event').onclick = () => openNewEventModal(state.selectedDate || state.currentDate);
  const fab = document.getElementById('btn-create-fab');
  if (fab) fab.onclick = () => openNewEventModal(state.selectedDate || state.currentDate);

  // Mobile view-toggle popup
  const viewMobileBtn = document.getElementById('btn-view-mobile');
  const viewMobileDropdown = document.getElementById('view-mobile-dropdown');
  if (viewMobileBtn && viewMobileDropdown) {
    viewMobileBtn.onclick = e => {
      e.stopPropagation();
      viewMobileDropdown.classList.toggle('hidden');
    };
    document.addEventListener('click', e => {
      if (!viewMobileDropdown.contains(e.target) && !viewMobileBtn.contains(e.target)) {
        viewMobileDropdown.classList.add('hidden');
      }
    });
    viewMobileDropdown.querySelectorAll('[data-mobile-view]').forEach(btn => {
      btn.onclick = () => {
        state.currentView = btn.dataset.mobileView;
        updateViewButtons();
        fetchAndRender();
        viewMobileDropdown.classList.add('hidden');
      };
    });
    const todayMobile = document.getElementById('btn-today-mobile');
    if (todayMobile) todayMobile.onclick = () => {
      state.currentDate = new Date();
      fetchAndRender();
      viewMobileDropdown.classList.add('hidden');
    };
  }

  // Settings entry inside the user dropdown (mobile)
  const settingsFromUser = document.getElementById('btn-settings-from-user');
  if (settingsFromUser) settingsFromUser.onclick = () => {
    document.getElementById('user-dropdown').classList.add('hidden');
    openSettingsModal();
  };

  // Settings nav hamburger (only does something on mobile via CSS)
  const settingsNavToggle = document.getElementById('settings-nav-toggle');
  const settingsCard = document.querySelector('#modal-settings .settings-page-card');
  const settingsNavBackdrop = document.getElementById('settings-nav-backdrop');
  if (settingsNavToggle && settingsCard) {
    settingsNavToggle.onclick = () => settingsCard.classList.toggle('nav-open');
  }
  if (settingsNavBackdrop && settingsCard) {
    settingsNavBackdrop.onclick = () => settingsCard.classList.remove('nav-open');
  }
  // After picking a section in the nav, close the overlay (mobile UX)
  document.querySelectorAll('.settings-nav-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      if (settingsCard) settingsCard.classList.remove('nav-open');
    });
  });

  // Mouse wheel / trackpad scroll navigation – only for month & quarter
  let _wheelLast = 0;
  document.getElementById('view-container').addEventListener('wheel', e => {
    if (state.currentView !== 'month' && state.currentView !== 'quarter') return;
    e.preventDefault();
    const now = Date.now();
    if (now - _wheelLast < 500) return;
    _wheelLast = now;
    const dir = e.deltaY > 0 ? 1 : -1;
    if (state.currentView === 'month') {
      state.currentDate = new Date(state.currentDate);
      state.currentDate.setDate(state.currentDate.getDate() + dir * 7);
      fetchAndRender();
    } else {
      navigate(dir);
    }
  }, { passive: false });
}

// ── Sidebar toggle ────────────────────────────────────────
function bindSidebar() {
  document.getElementById('sidebar-toggle').onclick = () => {
    document.getElementById('sidebar').classList.toggle('collapsed');
    document.body.classList.toggle('sidebar-open'); // mobile slide-in
  };
  const backdrop = document.getElementById('sidebar-backdrop');
  if (backdrop) backdrop.onclick = () => document.body.classList.remove('sidebar-open');

  // Add calendar dropdown
  const addBtn = document.getElementById('btn-add-cal');
  const dropdown = document.getElementById('add-cal-dropdown');

  addBtn.onclick = e => {
    e.stopPropagation();
    dropdown.classList.toggle('hidden');
  };
  document.addEventListener('click', e => {
    if (!dropdown.contains(e.target) && e.target !== addBtn) {
      dropdown.classList.add('hidden');
    }
  });

  dropdown.querySelector('[data-action="caldav"]').onclick = () => {
    dropdown.classList.add('hidden');
    openAccountModal();
  };
  dropdown.querySelector('[data-action="local"]').onclick = () => {
    dropdown.classList.add('hidden');
    openLocalCalModal();
  };
  dropdown.querySelector('[data-action="ical"]').onclick = () => {
    dropdown.classList.add('hidden');
    openICalSubModal();
  };
  dropdown.querySelector('[data-action="homeassistant"]').onclick = () => {
    dropdown.classList.add('hidden');
    openHAAccountModal();
  };
  dropdown.querySelector('[data-action="google"]').onclick = async () => {
    dropdown.classList.add('hidden');
    try {
      const { configured } = await api.get('/google/configured');
      if (!configured) {
        showToast(t('google_not_configured'), true);
        return;
      }
      const { url } = await api.get('/google/auth-url');
      window.location.href = url;
    } catch (e) {
      showToast(t('error_prefix') + e.message, true);
    }
  };
}

// ── Day Context Menu (month view) ────────────────────────
// ── Delete logic ──────────────────────────────────────────
async function deleteEventByScope(ev, scope) {
  if (scope === 'all' || !(ev.rrule || ev.recurring)) {
    // Delete the entire event (or non-recurring)
    if (ev.source === 'google') {
      const accId = ev.calendar_id.replace('google-', '');
      await api.delete(`/google/events/${accId}/${encodeURIComponent(ev.id)}`);
    } else if (ev.source === 'local') {
      await api.delete(`/local/events/${encodeURIComponent(ev.id)}`);
    } else if (ev.source === 'ical') {
      const subId = ev.calendar_id.replace('ical-', '');
      await api.delete(`/ical/events/${subId}/${encodeURIComponent(ev.id)}`);
    } else if (ev.source === 'homeassistant') {
      const haCalId = ev.calendar_id.replace('homeassistant-', '');
      await api.delete(`/homeassistant/events/${haCalId}/${encodeURIComponent(ev.id)}`);
    } else {
      await api.delete(`/caldav/events/${encodeURIComponent(ev.id)}?event_url=${encodeURIComponent(ev.url)}&calendar_id=${ev.calendar_id}`);
    }
  } else {
    // Delete single occurrence: add EXDATE to exclude this date
    const exdate = ev.start.slice(0, 10).replace(/-/g, '');
    if (ev.source === 'local') {
      // For local events: update rrule with EXDATE via a special field
      const currentRrule = ev.rrule || '';
      await api.put(`/local/events/${encodeURIComponent(ev.id)}`, {
        exdate: exdate,
      });
    } else {
      // For CalDAV: pass exdate to update
      await api.put(
        `/caldav/events/${encodeURIComponent(ev.id)}?event_url=${encodeURIComponent(ev.url)}&calendar_id=${ev.calendar_id}`,
        { exdate: exdate }
      );
    }
  }
}

// ── Delete Confirm Dialog ─────────────────────────────────
function showDeleteConfirm(ev) {
  return new Promise(resolve => {
    const modal = document.getElementById('modal-delete-confirm');
    const isRecurring = !!(ev.rrule || ev.recurring);

    document.getElementById('delete-confirm-title').textContent = t('confirm_delete_title');
    document.getElementById('delete-confirm-text').textContent = t('confirm_delete_event', { title: ev.title });
    document.getElementById('delete-series-options').classList.toggle('hidden', !isRecurring);

    // Reset radio
    const radios = modal.querySelectorAll('input[name="delete-scope"]');
    radios[0].checked = true;

    // Labels
    const labels = modal.querySelectorAll('#delete-series-options label');
    if (labels[0]) labels[0].lastChild.textContent = ' ' + t('delete_single');
    if (labels[1]) labels[1].lastChild.textContent = ' ' + t('delete_all_series');

    openModal('modal-delete-confirm');

    const okBtn = document.getElementById('delete-confirm-ok');
    const cleanup = () => {
      okBtn.onclick = null;
      modal.querySelectorAll('[data-modal="modal-delete-confirm"]').forEach(b => b.onclick = null);
    };

    okBtn.onclick = () => {
      const scope = isRecurring
        ? modal.querySelector('input[name="delete-scope"]:checked')?.value || 'single'
        : 'single';
      cleanup();
      closeModal('modal-delete-confirm');
      resolve(scope);
    };

    modal.querySelectorAll('[data-modal="modal-delete-confirm"]').forEach(b => {
      b.onclick = () => { cleanup(); closeModal('modal-delete-confirm'); resolve(null); };
    });
  });
}

function showDayContextMenu(date, mouseEvent) {
  document.querySelectorAll('.cal-context-menu').forEach(m => m.remove());

  const menu = document.createElement('div');
  menu.className = 'cal-context-menu';
  menu.innerHTML = `<div class="ctx-item" data-action="create">${t('ctx_create_event')}</div>`;

  menu.style.left = mouseEvent.clientX + 'px';
  menu.style.top  = mouseEvent.clientY + 'px';
  document.body.appendChild(menu);

  menu.querySelector('[data-action="create"]').onclick = () => {
    menu.remove();
    openNewEventModal(date);
  };

  const close = (e) => {
    if (!menu.contains(e.target)) { menu.remove(); document.removeEventListener('click', close); }
  };
  setTimeout(() => document.addEventListener('click', close), 0);
}

// ── Event Popup ───────────────────────────────────────────
function showEventPopup(ev, anchor) {
  // The event row stops click propagation, so the day context menu's own
  // outside-click closer never fires — remove it explicitly here.
  document.querySelectorAll('.cal-context-menu').forEach(m => m.remove());
  const popup = document.getElementById('popup-event');
  document.getElementById('popup-copy-menu').classList.add('hidden');
  popup.classList.remove('hidden');

  const color = ev.color || ev.calendarColor || '#4285f4';
  document.getElementById('popup-color-dot').style.background = color;
  popup.style.setProperty('--ev-color', color);
  document.getElementById('popup-title').textContent = ev.title;

  // Time
  if (ev.allDay) {
    document.getElementById('popup-time').textContent = t('allday_cap');
  } else {
    const s = new Date(ev.start);
    const e = new Date(ev.end);
    const sameDay = s.getFullYear() === e.getFullYear() &&
                    s.getMonth()    === e.getMonth()    &&
                    s.getDate()     === e.getDate();
    document.getElementById('popup-time').textContent = sameDay
      ? `${fmtDatetime(s)} – ${fmtTime(e)}`
      : `${fmtDatetime(s)} – ${fmtDatetime(e)}`;
  }

  document.getElementById('popup-location').textContent = ev.location || '';
  document.getElementById('popup-row-location').style.display = ev.location ? '' : 'none';
  document.getElementById('popup-description').innerHTML = renderDescriptionHtml(ev.description || '');
  document.getElementById('popup-row-description').style.display = ev.description ? '' : 'none';
  document.getElementById('popup-calendar').textContent = ev.calendar_name || '';
  document.getElementById('popup-row-calendar').style.display = ev.calendar_name ? '' : 'none';

  // Creator — only shown when it isn't the current user.
  const me = JSON.parse(localStorage.getItem('user') || '{}');
  if (ev.creator && ev.creator.display_name && ev.creator.id !== me.id) {
    document.getElementById('popup-creator').textContent = t('created_by', { name: ev.creator.display_name });
    document.getElementById('popup-row-creator').style.display = '';
  } else {
    document.getElementById('popup-row-creator').style.display = 'none';
  }

  // Position near anchor
  const rect = anchor.getBoundingClientRect();
  const pw = 320, ph = 200;
  let left = rect.right + 8;
  let top  = rect.top;
  if (left + pw > window.innerWidth) left = rect.left - pw - 8;
  if (top + ph > window.innerHeight) top = window.innerHeight - ph - 16;
  popup.style.left = Math.max(8, left) + 'px';
  popup.style.top  = Math.max(8, top)  + 'px';

  // Drag-to-move: grab the header and drag the popup anywhere on screen
  const dragHandle = popup.querySelector('.popup-header');
  let dragOffX = 0, dragOffY = 0;
  dragHandle.style.cursor = 'grab';
  const onPointerMove = e => {
    if (!popup.classList.contains('ep-dragging')) return;
    const vw = window.innerWidth, vh = window.innerHeight;
    const x = Math.max(0, Math.min(vw - popup.offsetWidth,  e.clientX - dragOffX));
    const y = Math.max(0, Math.min(vh - popup.offsetHeight, e.clientY - dragOffY));
    popup.style.left = x + 'px';
    popup.style.top  = y + 'px';
  };
  const onPointerUp = () => {
    popup.classList.remove('ep-dragging');
    dragHandle.style.cursor = 'grab';
  };
  dragHandle.onpointerdown = e => {
    if (e.button !== 0) return;
    // Let the toolbar buttons (edit/copy/delete/close) receive their click —
    // only the bare header area starts a drag.
    if (e.target.closest('button, a')) return;
    dragOffX = e.clientX - popup.getBoundingClientRect().left;
    dragOffY = e.clientY - popup.getBoundingClientRect().top;
    dragHandle.setPointerCapture(e.pointerId);
    popup.classList.add('ep-dragging');
    dragHandle.style.cursor = 'grabbing';
  };
  dragHandle.onpointermove = onPointerMove;
  dragHandle.onpointerup = onPointerUp;

  // Hide edit/delete for read-only iCal subscription events
  const isReadOnly = (ev.source === 'ical');
  document.getElementById('popup-edit').style.display = isReadOnly ? 'none' : '';
  document.getElementById('popup-delete').style.display = isReadOnly ? 'none' : '';

  document.getElementById('popup-edit').onclick = () => {
    popup.classList.add('hidden');
    openEditEventModal(ev);
  };

  // Copy to calendar
  document.getElementById('popup-copy').onclick = e => {
    e.stopPropagation();
    const menu = document.getElementById('popup-copy-menu');
    if (!menu.classList.contains('hidden')) { menu.classList.add('hidden'); return; }
    const targets = buildWritableCalendars(ev);
    if (!targets.length) { showToast('Keine Zielkalender verfügbar', true); return; }
    menu.innerHTML =
      `<div class="popup-copy-label">${t('copy_to_calendar')}</div>` +
      `<label class="popup-copy-edit-toggle">
         <input type="checkbox" id="popup-copy-edit-cb" />
         <span>${t('edit_before_copy')}</span>
       </label>` +
      targets.map(c =>
        `<div class="popup-copy-item" data-cal-idx="${c._idx}">
          <span class="popup-copy-dot" style="background:${c.color}"></span>
          <span>${escHtml(c.name)}</span>
        </div>`
      ).join('');
    menu.classList.remove('hidden');

    // Stop clicks on the checkbox label from closing the menu
    menu.querySelector('.popup-copy-edit-toggle').addEventListener('click', e2 => e2.stopPropagation());

    menu.querySelectorAll('.popup-copy-item').forEach(el => {
      el.addEventListener('click', async ev2 => {
        ev2.stopPropagation();
        const editFirst = document.getElementById('popup-copy-edit-cb').checked;
        menu.classList.add('hidden');
        popup.classList.add('hidden');
        const cal = targets[parseInt(el.dataset.calIdx)];
        if (editFirst) {
          openCopyEditModal(ev, cal);
        } else {
          await copyEventToCalendar(ev, cal);
        }
      });
    });
  };

  document.getElementById('popup-delete').onclick = async () => {
    popup.classList.add('hidden');
    const scope = await showDeleteConfirm(ev);
    if (!scope) return;
    try {
      await deleteEventByScope(ev, scope);
      showToast(t('event_deleted'));
      fetchAndRender(true);
    } catch (e) { showToast(e.message, true); }
  };
  document.getElementById('popup-close').onclick = () => popup.classList.add('hidden');
}

// Close popup on outside click
document.addEventListener('click', e => {
  const popup = document.getElementById('popup-event');
  if (!popup.classList.contains('hidden') && !popup.contains(e.target)) {
    popup.classList.add('hidden');
  }
});

// ── Event Modal ───────────────────────────────────────────
function populateCalendarSelect(selectedId) {
  closeCalSelectMenu();
  const sel = document.getElementById('ev-calendar');
  sel.innerHTML = '';
  // CalDAV calendars (show all that aren't removed from sidebar, even if unchecked)
  state.accounts.forEach(acc => {
    acc.calendars.filter(c => !c.sidebar_hidden).forEach(cal => {
      const opt = document.createElement('option');
      opt.value = cal.id;
      opt.textContent = `${acc.name} / ${cal.name}`;
      if (cal.id === selectedId) opt.selected = true;
      sel.appendChild(opt);
    });
  });
  // Local calendars. Group calendars are collected under a "Groups" optgroup
  // (no emoji — a native <select> can't render the group icon SVG).
  const localCals = state.localCalendars.filter(c => !c.sidebar_hidden);
  const makeLocalOpt = cal => {
    const opt = document.createElement('option');
    opt.value = `local-${cal.id}`;
    opt.textContent = cal.name;
    if (`local-${cal.id}` === selectedId) opt.selected = true;
    return opt;
  };
  localCals.filter(c => !c.group).forEach(cal => sel.appendChild(makeLocalOpt(cal)));
  const groupCals = localCals.filter(c => c.group);
  if (groupCals.length) {
    const og = document.createElement('optgroup');
    og.label = t('groups_title');
    groupCals.forEach(cal => og.appendChild(makeLocalOpt(cal)));
    sel.appendChild(og);
  }
  // iCal subscriptions are read-only, not shown here
  // Google calendars (read/write)
  state.googleAccounts.forEach(acc => {
    acc.calendars.filter(c => !c.sidebar_hidden).forEach(cal => {
      const opt = document.createElement('option');
      opt.value = `google-${cal.id}`;
      opt.textContent = `${acc.email} / ${cal.name}`;
      if (`google-${cal.id}` === selectedId) opt.selected = true;
      sel.appendChild(opt);
    });
  });
  // Home Assistant calendars
  state.haAccounts.forEach(acc => {
    acc.calendars.filter(c => !c.sidebar_hidden).forEach(cal => {
      const opt = document.createElement('option');
      opt.value = `homeassistant-${cal.id}`;
      opt.textContent = `${acc.name} / ${cal.name}`;
      if (`homeassistant-${cal.id}` === selectedId) opt.selected = true;
      sel.appendChild(opt);
    });
  });
  renderCalSelectTrigger();
}

// ── Custom calendar dropdown (colour dot + group icon) ────
// The hidden <select id="ev-calendar"> above stays the value holder; this
// renders a styled list from the same state so group icons can show.

function groupIconForLocalCal(calId) {
  const g = (state.groups || []).find(x => x.group_calendar_id === calId);
  return (g && g.icon) ? g.icon : 'people';
}

function calSelectData() {
  const sections = [];
  const byValue = {};
  const push = (sec, value, name, color, isGroup, iconKey) => {
    sec.items.push({ value, name, color, isGroup, iconKey });
    byValue[value] = { name, color, isGroup, iconKey };
  };
  state.accounts.forEach(acc => {
    const cals = (acc.calendars || []).filter(c => !c.sidebar_hidden);
    if (!cals.length) return;
    const sec = { label: acc.name, items: [] };
    cals.forEach(cal => push(sec, String(cal.id), cal.name, cal.color || acc.color || '#4285f4', false, null));
    sections.push(sec);
  });
  const locals = state.localCalendars.filter(c => !c.sidebar_hidden && !c.group);
  if (locals.length) {
    const sec = { label: t('cal_local'), items: [] };
    locals.forEach(cal => push(sec, `local-${cal.id}`, cal.name, cal.color, false, null));
    sections.push(sec);
  }
  const groups = state.localCalendars.filter(c => !c.sidebar_hidden && c.group);
  if (groups.length) {
    const sec = { label: t('groups_title'), items: [] };
    groups.forEach(cal => push(sec, `local-${cal.id}`, cal.name, cal.color, true, groupIconForLocalCal(cal.id)));
    sections.push(sec);
  }
  state.googleAccounts.forEach(acc => {
    const cals = (acc.calendars || []).filter(c => !c.sidebar_hidden);
    if (!cals.length) return;
    const sec = { label: acc.email, items: [] };
    cals.forEach(cal => push(sec, `google-${cal.id}`, cal.name, cal.color || '#4285f4', false, null));
    sections.push(sec);
  });
  state.haAccounts.forEach(acc => {
    const cals = (acc.calendars || []).filter(c => !c.sidebar_hidden);
    if (!cals.length) return;
    const sec = { label: acc.name, items: [] };
    cals.forEach(cal => push(sec, `homeassistant-${cal.id}`, cal.name, cal.color || '#03a9f4', false, null));
    sections.push(sec);
  });
  return { sections, byValue };
}

function calOptionInner(info) {
  const dot = `<span class="cal-select-dot" style="background:${info.color || '#4285f4'}"></span>`;
  const icon = info.isGroup ? `<span class="cal-select-gicon">${groupIconSvg(info.iconKey || 'people', 16)}</span>` : '';
  return `${dot}${icon}<span class="cal-select-name">${escHtml(info.name)}</span>`;
}

function renderCalSelectTrigger() {
  const cur = document.getElementById('ev-cal-current');
  if (!cur) return;
  const val = document.getElementById('ev-calendar').value;
  const { byValue } = calSelectData();
  const info = byValue[val];
  cur.innerHTML = info ? calOptionInner(info) : `<span class="cal-select-name">—</span>`;
}

function renderCalSelectMenu() {
  const menu = document.getElementById('ev-cal-menu');
  const val = document.getElementById('ev-calendar').value;
  const { sections } = calSelectData();
  menu.innerHTML = sections.map(sec =>
    `<div class="cal-select-section">${escHtml(sec.label)}</div>` +
    sec.items.map(it =>
      `<div class="cal-select-option ${it.value === val ? 'selected' : ''}" role="option" data-value="${it.value}">${calOptionInner(it)}</div>`
    ).join('')
  ).join('');
  menu.querySelectorAll('.cal-select-option').forEach(el => {
    el.addEventListener('click', () => {
      const sel = document.getElementById('ev-calendar');
      sel.value = el.dataset.value;
      sel.dispatchEvent(new Event('change'));
      renderCalSelectTrigger();
      closeCalSelectMenu();
    });
  });
}

function openCalSelectMenu() {
  renderCalSelectMenu();
  document.getElementById('ev-cal-menu').classList.remove('hidden');
  document.getElementById('ev-cal-select').dataset.open = '1';
  document.getElementById('ev-cal-trigger').setAttribute('aria-expanded', 'true');
  setTimeout(() => document.addEventListener('click', calSelectOutside), 0);
}

function closeCalSelectMenu() {
  const menu = document.getElementById('ev-cal-menu');
  if (menu) menu.classList.add('hidden');
  const wrap = document.getElementById('ev-cal-select');
  if (wrap) delete wrap.dataset.open;
  const trig = document.getElementById('ev-cal-trigger');
  if (trig) trig.setAttribute('aria-expanded', 'false');
  document.removeEventListener('click', calSelectOutside);
}

function calSelectOutside(e) {
  if (!e.target.closest('#ev-cal-select')) closeCalSelectMenu();
}

// ── Date field helpers ────────────────────────────────────

// All-day events use exclusive end-dates (iCal RFC 5545 convention):
// DTEND points to the day AFTER the last visible day. The user picker
// uses inclusive end-dates ("ends on 18.08" means 18.08 is the last
// day). These helpers convert between the two.
function shiftDate(isoDate, deltaDays) {
  if (!isoDate) return isoDate;
  const [y, m, d] = isoDate.slice(0, 10).split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() + deltaDays);
  return dt.toISOString().slice(0, 10);
}
const allDayEndToInclusive = iso => shiftDate(iso, -1); // storage → picker
const allDayEndToExclusive = iso => shiftDate(iso, +1); // picker → storage

function setDtValue(id, isoStr, mode) {
  const input = document.getElementById(id);
  if (input) input.value = isoStr || '';
  const display = document.getElementById(id + '-display');
  if (display) {
    display.querySelector('.dt-display-text').textContent =
      formatDtDisplay(isoStr, mode, getLang());
  }
}

function openNewEventModal(date) {
  state.editingEvent = null;
  state.selectedEventColor = '';

  document.getElementById('modal-event-title-label').textContent = 'Termin erstellen';
  document.getElementById('ev-title').value = '';
  document.getElementById('ev-location').value = '';
  document.getElementById('ev-description').value = '';
  document.getElementById('ev-allday').checked = false;

  const start = new Date(date);
  const durMin = (state.settings && state.settings.default_event_duration_minutes) || 60;
  const end   = new Date(start.getTime() + durMin * 60000);
  setDtValue('ev-start',      toLocalDatetimeInput(start), 'datetime');
  setDtValue('ev-end',        toLocalDatetimeInput(end),   'datetime');
  setDtValue('ev-start-date', toDateInput(start),          'date');
  setDtValue('ev-end-date',   toDateInput(start),          'date');

  toggleAlldayFields(false);
  populateCalendarSelect(null);
  updatePrivateRow(false);
  // New local event: prefill with the global default reminder if one is set.
  const defMin = state.settings && state.settings.default_reminder_minutes;
  setEventReminders(defMin != null ? [defMin] : []);
  updateRemindersRow();
  resetColorPicker('');
  resetRecurrenceUI();
  document.getElementById('ev-delete').classList.add('hidden');
  openModal('modal-event');
}

// Open the create-event modal pre-filled with an existing event's data, so
// the user can edit before copying it into the target calendar.
function openCopyEditModal(ev, targetCal) {
  state.editingEvent = null;
  state.selectedEventColor = ev.color || '';

  document.getElementById('modal-event-title-label').textContent = 'Termin erstellen';
  document.getElementById('ev-title').value       = ev.title || '';
  document.getElementById('ev-location').value    = ev.location || '';
  document.getElementById('ev-description').value = ev.description || '';
  document.getElementById('ev-allday').checked    = !!ev.allDay;

  if (ev.allDay) {
    setDtValue('ev-start-date', (ev.start || '').slice(0, 10), 'date');
    setDtValue('ev-end-date',   allDayEndToInclusive((ev.end || '').slice(0, 10)), 'date');
  } else {
    const s = new Date(ev.start);
    const e = new Date(ev.end);
    setDtValue('ev-start', toLocalDatetimeInput(s), 'datetime');
    setDtValue('ev-end',   toLocalDatetimeInput(e), 'datetime');
  }

  toggleAlldayFields(!!ev.allDay);

  // Map target calendar to the dropdown's option value
  let selectedId;
  if (targetCal.type === 'caldav') selectedId = targetCal.id;
  else                              selectedId = `${targetCal.type}-${targetCal.id}`;
  populateCalendarSelect(selectedId);
  updatePrivateRow(ev.private);
  setEventReminders(ev.reminders || []);
  updateRemindersRow();

  resetColorPicker(ev.color || '');
  resetRecurrenceUI();
  if (ev.rrule) parseRruleIntoUI(ev.rrule);
  document.getElementById('ev-delete').classList.add('hidden');
  openModal('modal-event');
}

function openEditEventModal(ev) {
  if (ev.source === 'ical') { showToast(t('event_readonly'), true); return; }
  state.editingEvent = ev;
  state.selectedEventColor = ev.color || '';

  document.getElementById('modal-event-title-label').textContent = 'Termin bearbeiten';
  document.getElementById('ev-title').value       = ev.title;
  document.getElementById('ev-location').value    = ev.location || '';
  document.getElementById('ev-description').value = ev.description || '';
  document.getElementById('ev-allday').checked    = ev.allDay;

  if (ev.allDay) {
    setDtValue('ev-start-date', ev.start.slice(0, 10), 'date');
    setDtValue('ev-end-date',   allDayEndToInclusive(ev.end.slice(0, 10)), 'date');
    toggleAlldayFields(true);
  } else {
    const s = new Date(ev.start);
    const e = new Date(ev.end);
    setDtValue('ev-start', toLocalDatetimeInput(s), 'datetime');
    setDtValue('ev-end',   toLocalDatetimeInput(e), 'datetime');
    toggleAlldayFields(false);
  }

  populateCalendarSelect(ev.calendar_id);
  updatePrivateRow(ev.private);
  setEventReminders(ev.reminders || []);
  updateRemindersRow();
  resetColorPicker(ev.color || '');

  // Recurrence
  const rrule = ev.rrule || '';
  const recSel = document.getElementById('ev-recurrence');
  const customPanel = document.getElementById('ev-recurrence-custom');
  if (!rrule) {
    recSel.value = '';
    customPanel.classList.add('hidden');
  } else if (['FREQ=DAILY', 'FREQ=WEEKLY', 'FREQ=MONTHLY', 'FREQ=YEARLY'].includes(rrule)) {
    recSel.value = rrule;
    customPanel.classList.add('hidden');
  } else {
    recSel.value = 'custom';
    customPanel.classList.remove('hidden');
    parseRruleIntoUI(rrule);
  }

  document.getElementById('ev-delete').classList.remove('hidden');
  openModal('modal-event');
}

function toggleAlldayFields(allDay) {
  document.getElementById('ev-time-row').style.display = allDay ? 'none' : '';
  document.getElementById('ev-date-row').style.display = allDay ? '' : 'none';
}

// The "Privat" toggle only applies to local calendars; hide it otherwise.
function updatePrivateRow(isPrivate) {
  const calVal = document.getElementById('ev-calendar').value || '';
  const isLocal = calVal.startsWith('local-');
  const row = document.getElementById('ev-private-row');
  row.style.display = isLocal ? '' : 'none';
  if (isPrivate !== undefined) {
    document.getElementById('ev-private').checked = !!isPrivate;
  }
  if (!isLocal) document.getElementById('ev-private').checked = false;
}

function resetColorPicker(color) {
  state.selectedEventColor = color;
  const hex = document.getElementById('ev-color-hex');
  const preview = document.getElementById('ev-color-preview');
  hex.value = color ? color.toUpperCase() : '';
  preview.style.background = color || 'var(--primary)';
}

// ── Reminders (local events only) ─────────────────────────
// A few quick presets; anything else is entered via the "custom" mode
// (number + unit). Reminders are stored as minutes-before-start integers.
const REMINDER_PRESETS = [0, 30, 1440]; // at start, 30 min, 1 day
const REMINDER_UNITS = [
  { unit: 'minutes', mult: 1 },
  { unit: 'hours',   mult: 60 },
  { unit: 'days',    mult: 1440 },
  { unit: 'weeks',   mult: 10080 },
];

function reminderLabel(min) {
  if (min <= 0) return t('reminder_at_start');
  if (min < 60)    return t('reminder_minutes', { n: min });
  if (min < 1440)  { const h = min / 60;    return h === 1 ? t('reminder_hour_one') : t('reminder_hours', { n: h }); }
  if (min < 10080) { const d = min / 1440;  return d === 1 ? t('reminder_day_one')  : t('reminder_days',  { n: d }); }
  const w = min / 10080;                    return w === 1 ? t('reminder_week_one') : t('reminder_weeks', { n: w });
}

// Split a minutes value into the largest exact {value, unit} for the custom picker.
function splitReminder(min) {
  for (let i = REMINDER_UNITS.length - 1; i >= 0; i--) {
    const u = REMINDER_UNITS[i];
    if (min > 0 && min % u.mult === 0) return { value: min / u.mult, unit: u.unit };
  }
  return { value: Math.max(1, min), unit: 'minutes' };
}

function setEventReminders(arr) {
  state.eventReminders = Array.isArray(arr)
    ? arr.map(Number).filter(n => !isNaN(n)) : [];
  renderReminderRows();
}

function renderReminderRows() {
  const list = document.getElementById('ev-reminders-list');
  if (!list) return;
  list.innerHTML = '';
  state.eventReminders.forEach((min, idx) => {
    const row = document.createElement('div');
    row.className = 'ev-reminder-row';

    const isPreset = REMINDER_PRESETS.includes(min);
    const sel = document.createElement('select');
    REMINDER_PRESETS.forEach(v => {
      const o = document.createElement('option');
      o.value = String(v);
      o.textContent = reminderLabel(v);
      if (isPreset && v === min) o.selected = true;
      sel.appendChild(o);
    });
    const customOpt = document.createElement('option');
    customOpt.value = 'custom';
    customOpt.textContent = t('reminder_custom');
    if (!isPreset) customOpt.selected = true;
    sel.appendChild(customOpt);

    // Custom (number + unit) inputs, shown only in custom mode.
    const customWrap = document.createElement('span');
    customWrap.className = 'ev-reminder-custom';
    customWrap.style.display = isPreset ? 'none' : '';
    const numInput = document.createElement('input');
    numInput.type = 'number';
    numInput.min = '1';
    const unitSel = document.createElement('select');
    REMINDER_UNITS.forEach(u => {
      const o = document.createElement('option');
      o.value = u.unit;
      o.textContent = t('reminder_unit_' + u.unit);
      unitSel.appendChild(o);
    });
    const beforeLbl = document.createElement('span');
    beforeLbl.className = 'ev-reminder-before';
    beforeLbl.textContent = t('reminder_before');
    const sp = splitReminder(isPreset ? 30 : min);
    numInput.value = String(sp.value);
    unitSel.value = sp.unit;
    customWrap.appendChild(numInput);
    customWrap.appendChild(unitSel);
    customWrap.appendChild(beforeLbl);

    function commitCustom() {
      const n = Math.max(1, parseInt(numInput.value, 10) || 1);
      const mult = REMINDER_UNITS.find(u => u.unit === unitSel.value).mult;
      state.eventReminders[idx] = n * mult;
    }
    sel.addEventListener('change', () => {
      if (sel.value === 'custom') {
        customWrap.style.display = '';
        commitCustom();
      } else {
        customWrap.style.display = 'none';
        state.eventReminders[idx] = parseInt(sel.value, 10);
      }
    });
    numInput.addEventListener('input', commitCustom);
    unitSel.addEventListener('change', commitCustom);

    const rm = document.createElement('button');
    rm.type = 'button';
    rm.className = 'icon-btn ev-reminder-remove';
    rm.innerHTML = '&times;';
    rm.addEventListener('click', () => {
      state.eventReminders.splice(idx, 1);
      renderReminderRows();
    });
    row.appendChild(sel);
    row.appendChild(customWrap);
    row.appendChild(rm);
    list.appendChild(row);
  });
}

function addReminderRow() {
  const def = (state.settings && state.settings.default_reminder_minutes != null)
    ? state.settings.default_reminder_minutes : 30;
  state.eventReminders.push(def >= 0 ? def : 30);
  renderReminderRows();
}

// Reminders apply to local events only (the server stores them on local events).
// When the selected calendar has its reminders disabled, we keep any existing
// reminders intact (never delete them) but grey out the controls and explain
// that they won't fire — matching the apps' behaviour.
function updateRemindersRow() {
  const calVal = document.getElementById('ev-calendar').value || '';
  const isLocal = calVal.startsWith('local-');
  const group = document.getElementById('ev-reminders-group');
  group.style.display = isLocal ? '' : 'none';
  if (!isLocal) return;

  const calId = parseInt(calVal.slice('local-'.length), 10);
  const cal = (state.localCalendars || []).find(c => c.id === calId);
  const disabled = !!(cal && cal.reminders_enabled === false);

  const hint = document.getElementById('ev-reminders-hint');
  if (hint) hint.style.display = disabled ? '' : 'none';
  group.classList.toggle('reminders-disabled', disabled);
  group.querySelectorAll('select, input, button').forEach(el => { el.disabled = disabled; });
}

function buildRruleFromUI() {
  const sel = document.getElementById('ev-recurrence').value;
  if (!sel) return null;
  if (sel !== 'custom') return sel;

  const interval = parseInt(document.getElementById('ev-rec-interval').value) || 1;
  const freq = document.getElementById('ev-rec-freq').value;
  let rule = `FREQ=${freq}`;
  if (interval > 1) rule += `;INTERVAL=${interval}`;

  if (freq === 'WEEKLY') {
    const days = [...document.querySelectorAll('.rec-day-btn.active')].map(b => b.dataset.day);
    if (days.length) rule += `;BYDAY=${days.join(',')}`;
  }

  const endType = document.getElementById('ev-rec-end-type').value;
  if (endType === 'count') {
    rule += `;COUNT=${parseInt(document.getElementById('ev-rec-count').value) || 10}`;
  } else if (endType === 'until') {
    const until = document.getElementById('ev-rec-until').value;
    if (until) rule += `;UNTIL=${until.replace(/-/g, '')}T235959Z`;
  }
  return rule;
}

function parseRruleIntoUI(rruleStr) {
  const parts = {};
  rruleStr.split(';').forEach(p => {
    const [k, v] = p.split('=', 2);
    if (k && v) parts[k] = v;
  });

  document.getElementById('ev-rec-interval').value = parts.INTERVAL || '1';
  document.getElementById('ev-rec-freq').value = parts.FREQ || 'DAILY';
  document.getElementById('ev-rec-weekdays').classList.toggle('hidden', parts.FREQ !== 'WEEKLY');

  // Reset all weekday buttons
  document.querySelectorAll('.rec-day-btn').forEach(btn => btn.classList.remove('active'));
  if (parts.BYDAY) {
    parts.BYDAY.split(',').forEach(day => {
      const btn = document.querySelector(`.rec-day-btn[data-day="${day.trim()}"]`);
      if (btn) btn.classList.add('active');
    });
  }

  if (parts.COUNT) {
    document.getElementById('ev-rec-end-type').value = 'count';
    document.getElementById('ev-rec-count').value = parts.COUNT;
    document.getElementById('ev-rec-end-count').classList.remove('hidden');
    document.getElementById('ev-rec-end-until').classList.add('hidden');
  } else if (parts.UNTIL) {
    document.getElementById('ev-rec-end-type').value = 'until';
    // Parse UNTIL: 20260501T235959Z → 2026-05-01
    const u = parts.UNTIL.replace('Z', '');
    const formatted = u.length >= 8 ? `${u.slice(0,4)}-${u.slice(4,6)}-${u.slice(6,8)}` : '';
    if (formatted) setDtValue('ev-rec-until', formatted, 'date');
    document.getElementById('ev-rec-end-count').classList.add('hidden');
    document.getElementById('ev-rec-end-until').classList.remove('hidden');
  } else {
    document.getElementById('ev-rec-end-type').value = 'never';
    document.getElementById('ev-rec-end-count').classList.add('hidden');
    document.getElementById('ev-rec-end-until').classList.add('hidden');
  }
}

function resetRecurrenceUI() {
  document.getElementById('ev-recurrence').value = '';
  document.getElementById('ev-recurrence-custom').classList.add('hidden');
  document.getElementById('ev-rec-interval').value = '1';
  document.getElementById('ev-rec-freq').value = 'DAILY';
  document.getElementById('ev-rec-weekdays').classList.add('hidden');
  document.querySelectorAll('.rec-day-btn').forEach(btn => btn.classList.remove('active'));
  document.getElementById('ev-rec-end-type').value = 'never';
  document.getElementById('ev-rec-end-count').classList.add('hidden');
  document.getElementById('ev-rec-end-until').classList.add('hidden');
}

function bindEventModal() {
  document.getElementById('ev-allday').addEventListener('change', e => {
    toggleAlldayFields(e.target.checked);
  });

  // The "Privat" toggle and reminders are only relevant for local calendars.
  document.getElementById('ev-calendar').addEventListener('change', () => {
    updatePrivateRow();
    updateRemindersRow();
  });

  document.getElementById('ev-reminder-add').addEventListener('click', addReminderRow);

  // Custom calendar dropdown toggle
  document.getElementById('ev-cal-trigger').addEventListener('click', e => {
    e.stopPropagation();
    const menu = document.getElementById('ev-cal-menu');
    if (menu.classList.contains('hidden')) openCalSelectMenu(); else closeCalSelectMenu();
  });
  document.getElementById('ev-cal-select').addEventListener('keydown', e => {
    if (e.key === 'Escape') closeCalSelectMenu();
  });

  // Date/time pickers with auto-adjustment logic
  [
    { displayId: 'ev-start-display',      inputId: 'ev-start',      mode: 'datetime', role: 'start' },
    { displayId: 'ev-end-display',        inputId: 'ev-end',        mode: 'datetime', role: 'end'   },
    { displayId: 'ev-start-date-display', inputId: 'ev-start-date', mode: 'date',     role: 'start' },
    { displayId: 'ev-end-date-display',   inputId: 'ev-end-date',   mode: 'date',     role: 'end'   },
  ].forEach(({ displayId, inputId, mode, role }) => {
    const disp = document.getElementById(displayId);
    if (!disp) return;
    const open = async () => {
      const current = document.getElementById(inputId)?.value || '';
      const oldStart = mode === 'datetime'
        ? document.getElementById('ev-start').value
        : document.getElementById('ev-start-date').value;
      const oldEnd = mode === 'datetime'
        ? document.getElementById('ev-end').value
        : document.getElementById('ev-end-date').value;

      const result = await openDatePicker(disp, current, mode);
      if (result === null) return;
      setDtValue(inputId, result, mode);

      if (role === 'start') {
        // Adjust end to maintain duration
        if (mode === 'datetime') {
          const os = oldStart ? new Date(oldStart) : null;
          const oe = oldEnd ? new Date(oldEnd) : null;
          const ns = new Date(result);
          const duration = (os && oe && oe > os) ? (oe - os) : 3600000;
          const ne = new Date(ns.getTime() + duration);
          setDtValue('ev-end', toLocalDatetimeInput(ne), 'datetime');
        } else {
          const endVal = document.getElementById('ev-end-date').value;
          if (!endVal || endVal < result) {
            setDtValue('ev-end-date', result, 'date');
          }
        }
      } else {
        // End moved before start → move the start back instead of erroring
        // (mirror of the start handler, which moves the end).
        if (mode === 'datetime') {
          const startVal = document.getElementById('ev-start').value;
          if (startVal && new Date(result) < new Date(startVal)) {
            const os = oldStart ? new Date(oldStart) : null;
            const oe = oldEnd ? new Date(oldEnd) : null;
            const duration = (os && oe && oe > os) ? (oe - os) : 3600000;
            const ns = new Date(new Date(result).getTime() - duration);
            setDtValue('ev-start', toLocalDatetimeInput(ns), 'datetime');
          }
        } else {
          const startVal = document.getElementById('ev-start-date').value;
          if (startVal && result < startVal) {
            setDtValue('ev-start-date', result, 'date');
          }
        }
      }
    };
    disp.addEventListener('click', open);
    disp.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') open(); });
  });

  // Color picker: click preview to open gradient picker
  const evColorPreview = document.getElementById('ev-color-preview');
  const evColorHex = document.getElementById('ev-color-hex');

  evColorPreview.addEventListener('click', async () => {
    const current = state.selectedEventColor || '#4285f4';
    const picked = await openColorPicker(evColorPreview, current);
    if (picked) resetColorPicker(picked);
  });

  evColorHex.addEventListener('change', () => {
    let val = evColorHex.value.trim();
    if (!val.startsWith('#')) val = '#' + val;
    if (/^#[0-9a-fA-F]{6}$/.test(val)) {
      resetColorPicker(val);
    }
  });

  // ── Recurrence UI ──────────────────────────────────────
  const recSel = document.getElementById('ev-recurrence');
  const customPanel = document.getElementById('ev-recurrence-custom');
  const recFreq = document.getElementById('ev-rec-freq');
  const weekdaysDiv = document.getElementById('ev-rec-weekdays');
  const endTypeSel = document.getElementById('ev-rec-end-type');

  recSel.addEventListener('change', () => {
    customPanel.classList.toggle('hidden', recSel.value !== 'custom');
  });

  recFreq.addEventListener('change', () => {
    weekdaysDiv.classList.toggle('hidden', recFreq.value !== 'WEEKLY');
  });

  document.querySelectorAll('.rec-day-btn').forEach(btn => {
    btn.addEventListener('click', () => btn.classList.toggle('active'));
  });

  endTypeSel.addEventListener('change', () => {
    document.getElementById('ev-rec-end-count').classList.toggle('hidden', endTypeSel.value !== 'count');
    document.getElementById('ev-rec-end-until').classList.toggle('hidden', endTypeSel.value !== 'until');
  });

  const untilDisp = document.getElementById('ev-rec-until-display');
  if (untilDisp) {
    const openUntil = async () => {
      const current = document.getElementById('ev-rec-until').value || '';
      const result = await openDatePicker(untilDisp, current, 'date');
      if (result !== null) setDtValue('ev-rec-until', result, 'date');
    };
    untilDisp.addEventListener('click', openUntil);
    untilDisp.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') openUntil(); });
  }

  document.getElementById('ev-save').onclick = async () => {
    const title = document.getElementById('ev-title').value.trim();
    if (!title) { showToast(t('error_enter_title'), true); return; }

    const allDay  = document.getElementById('ev-allday').checked;
    const calVal  = document.getElementById('ev-calendar').value;
    const isLocal = calVal.startsWith('local-');
    const isGoogle = calVal.startsWith('google-');
    const isHA = calVal.startsWith('homeassistant-');
    const loc     = document.getElementById('ev-location').value.trim();
    const desc    = document.getElementById('ev-description').value.trim();
    const color   = state.selectedEventColor;
    const rrule   = buildRruleFromUI();
    const isPrivate = isLocal && document.getElementById('ev-private').checked;

    let start, end;
    if (allDay) {
      start = document.getElementById('ev-start-date').value;
      end   = document.getElementById('ev-end-date').value;
      if (!start) { showToast(t('error_enter_date'), true); return; }
      if (!end || end < start) end = start;
      // User picker uses inclusive end; storage uses exclusive (iCal convention)
      end = allDayEndToExclusive(end);
    } else {
      const sv = document.getElementById('ev-start').value;
      const ev2 = document.getElementById('ev-end').value;
      if (!sv) { showToast(t('error_enter_start'), true); return; }
      start = new Date(sv).toISOString();
      end   = ev2 ? new Date(ev2).toISOString() : new Date(new Date(sv).getTime() + 3600000).toISOString();
    }

    try {
      if (state.editingEvent) {
        const ev = state.editingEvent;
        if (ev.source === 'google') {
          const accId = ev.calendar_id.replace('google-', '');
          await api.put(`/google/events/${accId}/${encodeURIComponent(ev.id)}`,
            { title, start, end, allDay, location: loc, description: desc }
          );
        } else if (ev.source === 'local') {
          await api.put(`/local/events/${encodeURIComponent(ev.id)}`,
            { title, start, end, allDay, location: loc, description: desc, color: color || null, rrule: rrule || '', private: isPrivate, reminders: state.eventReminders }
          );
        } else if (ev.source === 'ical') {
          showToast(t('event_readonly'), true);
          return;
        } else if (ev.source === 'homeassistant') {
          const haCalId = ev.calendar_id.replace('homeassistant-', '');
          await api.put(`/homeassistant/events/${haCalId}/${encodeURIComponent(ev.id)}`,
            { title, start, end, allDay, location: loc, description: desc }
          );
        } else {
          await api.put(
            `/caldav/events/${encodeURIComponent(ev.id)}?event_url=${encodeURIComponent(ev.url)}&calendar_id=${ev.calendar_id}`,
            { title, start, end, allDay, location: loc, description: desc, color: color || null, rrule: rrule || '' }
          );
        }
        // Patch the cached event in-place so the UI reflects changes immediately
        applyEventPatch(ev.id, ev.url, {
          title, start, end, allDay,
          location: loc, description: desc,
          color: color || null,
          rrule: rrule || null,
          private: ev.source === 'local' ? isPrivate : ev.private,
          reminders: ev.source === 'local' ? state.eventReminders.slice() : ev.reminders,
        });
        showToast(t('event_updated'));
      } else if (isGoogle) {
        const calDbId = parseInt(calVal.replace('google-', ''));
        await api.post('/google/events', {
          calendar_db_id: calDbId, title, start, end, allDay,
          location: loc, description: desc,
        });
        showToast(t('event_created'));
      } else if (isLocal) {
        const calId = parseInt(calVal.replace('local-', ''));
        await api.post('/local/events', {
          calendar_id: calId, title, start, end, allDay,
          location: loc, description: desc, color: color || null,
          rrule: rrule || null, private: isPrivate, reminders: state.eventReminders,
        });
        showToast(t('event_created'));
      } else if (isHA) {
        const haCalId = parseInt(calVal.replace('homeassistant-', ''));
        await api.post('/homeassistant/events', {
          calendar_id: haCalId, title, start, end, allDay,
          location: loc, description: desc,
        });
        showToast(t('event_created'));
      } else {
        const calId = parseInt(calVal);
        await api.post('/caldav/events', {
          calendar_id: calId, title, start, end, allDay,
          location: loc, description: desc, color: color || null,
          rrule: rrule || null,
        });
        showToast(t('event_created'));
      }
      closeModal('modal-event');
      fetchAndRender(true);
    } catch (e) {
      showToast(e.message, true);
    }
  };

  document.getElementById('ev-delete').onclick = async () => {
    const ev = state.editingEvent;
    if (!ev) return;
    const scope = await showDeleteConfirm(ev);
    if (!scope) return;
    try {
      await deleteEventByScope(ev, scope);
      showToast(t('event_deleted'));
      closeModal('modal-event');
      fetchAndRender(true);
    } catch (e) { showToast(e.message, true); }
  };
}

// ── Account Modal ─────────────────────────────────────────
function openAccountModal() {
  document.getElementById('acc-name').value = '';
  document.getElementById('acc-url').value = '';
  document.getElementById('acc-username').value = '';
  document.getElementById('acc-password').value = '';
  document.getElementById('acc-color-hex').value = '#4285f4';
  document.getElementById('acc-color-preview').style.background = '#4285f4';
  document.getElementById('acc-error').classList.add('hidden');
  openModal('modal-account');
}

function bindAccountModal() {
  const accPreview = document.getElementById('acc-color-preview');
  const accHex = document.getElementById('acc-color-hex');
  accPreview.addEventListener('click', async () => {
    const picked = await openColorPicker(accPreview, accHex.value || '#4285f4');
    if (picked) { accHex.value = picked.toUpperCase(); accPreview.style.background = picked; }
  });
  accHex.addEventListener('change', () => {
    let val = accHex.value.trim();
    if (!val.startsWith('#')) val = '#' + val;
    if (/^#[0-9a-fA-F]{6}$/.test(val)) { accHex.value = val.toUpperCase(); accPreview.style.background = val; }
  });

  document.getElementById('acc-save').onclick = async () => {
    const name     = document.getElementById('acc-name').value.trim();
    const url      = document.getElementById('acc-url').value.trim();
    const username = document.getElementById('acc-username').value.trim();
    const password = document.getElementById('acc-password').value;
    const color    = document.getElementById('acc-color-hex').value;
    const errEl    = document.getElementById('acc-error');

    if (!name || !url || !username || !password) {
      errEl.textContent = 'Bitte alle Felder ausfüllen';
      errEl.classList.remove('hidden');
      return;
    }
    errEl.classList.add('hidden');
    document.getElementById('acc-save').disabled = true;
    document.getElementById('acc-save').textContent = 'Verbinde…';

    try {
      const acc = await api.post('/caldav/accounts', { name, url, username, password, color });
      state.accounts.push(acc);
      renderCalendarList();
      closeModal('modal-account');
      showToast(t("account_added", {name}));
      fetchAndRender(true);
    } catch (e) {
      errEl.textContent = e.message;
      errEl.classList.remove('hidden');
    } finally {
      document.getElementById('acc-save').disabled = false;
      document.getElementById('acc-save').textContent = 'Verbinden';
    }
  };
}

// ── Local Calendar Modal ──────────────────────────────────
function openLocalCalModal() {
  document.getElementById('local-cal-name').value = '';
  document.getElementById('local-cal-color-hex').value = '#34a853';
  document.getElementById('local-cal-color-preview').style.background = '#34a853';
  openModal('modal-local-cal');
}

function bindLocalCalModal() {
  const preview = document.getElementById('local-cal-color-preview');
  const hex = document.getElementById('local-cal-color-hex');
  preview.addEventListener('click', async () => {
    const picked = await openColorPicker(preview, hex.value || '#34a853');
    if (picked) { hex.value = picked.toUpperCase(); preview.style.background = picked; }
  });
  hex.addEventListener('change', () => {
    let val = hex.value.trim();
    if (!val.startsWith('#')) val = '#' + val;
    if (/^#[0-9a-fA-F]{6}$/.test(val)) { hex.value = val.toUpperCase(); preview.style.background = val; }
  });

  document.getElementById('local-cal-save').onclick = async () => {
    const name = document.getElementById('local-cal-name').value.trim();
    if (!name) { showToast(t('error_enter_name'), true); return; }
    const color = hex.value;
    try {
      const cal = await api.post('/local/calendars', { name, color });
      state.localCalendars.push(cal);
      renderCalendarList();
      closeModal('modal-local-cal');
      showToast(t("calendar_created", {name}));
    } catch (e) { showToast(e.message, true); }
  };
}

// ── Home Assistant Account Modal ─────────────────────────
function openHAAccountModal() {
  document.getElementById('ha-account-name').value = '';
  document.getElementById('ha-account-url').value = '';
  document.getElementById('ha-account-token').value = '';
  document.getElementById('ha-account-error').classList.add('hidden');
  // Reset to OAuth method
  document.getElementById('ha-auth-oauth').checked = true;
  document.getElementById('ha-oauth-info').classList.remove('hidden');
  document.getElementById('ha-token-group').classList.add('hidden');
  document.getElementById('ha-account-save').textContent = 'Mit Home Assistant anmelden';
  openModal('modal-ha-account');
}

function bindHAAccountModal() {
  // Toggle auth method fields + save button label
  document.querySelectorAll('[name="ha-auth-method"]').forEach(r => {
    r.addEventListener('change', () => {
      const isOAuth = document.getElementById('ha-auth-oauth').checked;
      document.getElementById('ha-oauth-info').classList.toggle('hidden', !isOAuth);
      document.getElementById('ha-token-group').classList.toggle('hidden', isOAuth);
      document.getElementById('ha-account-save').textContent = isOAuth
        ? 'Mit Home Assistant anmelden'
        : 'Verbinden';
    });
  });

  document.getElementById('ha-account-save').onclick = async () => {
    const name = document.getElementById('ha-account-name').value.trim();
    const url = document.getElementById('ha-account-url').value.trim();
    const isOAuth = document.getElementById('ha-auth-oauth').checked;
    const errEl = document.getElementById('ha-account-error');

    if (!name || !url) {
      errEl.textContent = 'Bitte Name und URL ausfüllen';
      errEl.classList.remove('hidden');
      return;
    }
    errEl.classList.add('hidden');

    const saveBtn = document.getElementById('ha-account-save');
    saveBtn.disabled = true;

    if (isOAuth) {
      saveBtn.textContent = 'Weiterleiten…';
      try {
        const base = window.location.origin;
        const resp = await api.post('/homeassistant/auth-url', {
          name,
          url,
          client_id: base + '/',
          redirect_uri: base + '/api/homeassistant/callback',
        });
        if (!resp) return;
        window.location.href = resp.url;
      } catch (e) {
        errEl.textContent = e.message || 'Fehler beim Starten der Anmeldung';
        errEl.classList.remove('hidden');
        saveBtn.disabled = false;
        saveBtn.textContent = 'Mit Home Assistant anmelden';
      }
      return;
    }

    // Long-Lived Token flow
    const token = document.getElementById('ha-account-token').value.trim();
    if (!token) {
      errEl.textContent = 'Bitte Access Token ausfüllen';
      errEl.classList.remove('hidden');
      saveBtn.disabled = false;
      return;
    }
    saveBtn.textContent = 'Verbinde…';
    try {
      const account = await api.post('/homeassistant/accounts', { name, url, token });
      if (!account) return;
      state.haAccounts.push(account);
      renderCalendarList();
      closeModal('modal-ha-account');
      showToast(`Home Assistant "${name}" verbunden`);
      fetchAndRender(true);
    } catch (e) {
      errEl.textContent = e.message || 'Home Assistant nicht erreichbar';
      errEl.classList.remove('hidden');
    } finally {
      saveBtn.disabled = false;
      saveBtn.textContent = 'Verbinden';
    }
  };
}

// ── iCal Subscription Modal ──────────────────────────────
function openICalSubModal() {
  document.getElementById('ical-sub-name').value = '';
  document.getElementById('ical-sub-url').value = '';
  document.getElementById('ical-sub-color-hex').value = '#46bdc6';
  document.getElementById('ical-sub-color-preview').style.background = '#46bdc6';
  document.getElementById('ical-sub-refresh').value = '60';
  document.getElementById('ical-sub-error').classList.add('hidden');
  openModal('modal-ical-sub');
}

function bindICalSubModal() {
  const preview = document.getElementById('ical-sub-color-preview');
  const hex = document.getElementById('ical-sub-color-hex');
  preview.addEventListener('click', async () => {
    const picked = await openColorPicker(preview, hex.value || '#46bdc6');
    if (picked) { hex.value = picked.toUpperCase(); preview.style.background = picked; }
  });
  hex.addEventListener('change', () => {
    let val = hex.value.trim();
    if (!val.startsWith('#')) val = '#' + val;
    if (/^#[0-9a-fA-F]{6}$/.test(val)) { hex.value = val.toUpperCase(); preview.style.background = val; }
  });

  document.getElementById('ical-sub-save').onclick = async () => {
    const name = document.getElementById('ical-sub-name').value.trim();
    const url = document.getElementById('ical-sub-url').value.trim();
    const errEl = document.getElementById('ical-sub-error');
    if (!name || !url) { errEl.textContent = 'Bitte Name und URL eingeben'; errEl.classList.remove('hidden'); return; }
    errEl.classList.add('hidden');

    const color = hex.value;
    const refresh_minutes = parseInt(document.getElementById('ical-sub-refresh').value);

    document.getElementById('ical-sub-save').disabled = true;
    document.getElementById('ical-sub-save').textContent = 'Lade…';
    try {
      const sub = await api.post('/ical/subscriptions', { name, url, color, refresh_minutes });
      state.icalSubscriptions.push(sub);
      renderCalendarList();
      closeModal('modal-ical-sub');
      showToast(t("ical_subscribed", {name}));
      fetchAndRender(true);
    } catch (e) {
      errEl.textContent = e.message;
      errEl.classList.remove('hidden');
    } finally {
      document.getElementById('ical-sub-save').disabled = false;
      document.getElementById('ical-sub-save').textContent = 'Abonnieren';
    }
  };
}

// ── iCal Import ───────────────────────────────────────────
// Open a file picker and import the chosen .ics into the given local calendar.
function triggerIcsImport(calendarId) {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = '.ics,text/calendar';
  input.style.display = 'none';
  document.body.appendChild(input);
  input.addEventListener('change', async () => {
    const file = input.files && input.files[0];
    input.remove();
    if (!file) return;
    const form = new FormData();
    form.append('file', file);
    try {
      showToast(t('importing'));
      const res = await api.upload(`/local/calendars/${calendarId}/import`, form);
      showToast(t('import_result', { imported: res.imported, skipped: res.skipped }));
      fetchAndRender(true);
    } catch (e) { showToast(e.message, true); }
  });
  input.click();
}

// ── Sharing ───────────────────────────────────────────────
async function openShareModal(calendarId) {
  const modal = document.getElementById('modal-share');
  modal.dataset.calId = String(calendarId);
  const search = document.getElementById('share-user-search');
  search.value = '';
  search.oninput = renderShareUserPicker;
  document.getElementById('share-permission').value = 'read';
  openModal('modal-share');
  await refreshShareModal(calendarId);
}

async function refreshShareModal(calendarId) {
  // Load current shares + the user directory (for the picker).
  let shares = [], users = [];
  try { shares = await api.get(`/local/calendars/${calendarId}/shares`); } catch (e) { showToast(e.message, true); }
  try { users = await api.get('/users/directory'); } catch (e) { /* ignore */ }

  const sharedIds = new Set(shares.map(s => s.user_id));
  const listEl = document.getElementById('share-current-list');
  listEl.innerHTML = shares.length
    ? shares.map(s =>
        `<div class="accounts-row">
          <span class="accounts-row-name">${escHtml(s.display_name || '')}</span>
          <div class="accounts-row-actions">
            <span class="cal-badge">${s.permission === 'read_write' ? t('perm_read_write') : t('perm_read')}</span>
            <button class="btn btn-ghost btn-sm" data-share-remove="${s.user_id}">${t('remove')}</button>
          </div>
        </div>`
      ).join('')
    : `<span class="accounts-section-empty">${t('share_none')}</span>`;

  listEl.querySelectorAll('[data-share-remove]').forEach(btn => {
    btn.addEventListener('click', async () => {
      try {
        await api.delete(`/local/calendars/${calendarId}/shares/${btn.dataset.shareRemove}`);
        await refreshShareModal(calendarId);
      } catch (e) { showToast(e.message, true); }
    });
  });

  // Store the directory (minus already-shared users) for the picker.
  document.getElementById('modal-share').__users = users.filter(u => !sharedIds.has(u.id));
  renderShareUserPicker();
}

function renderShareUserPicker() {
  const modal = document.getElementById('modal-share');
  const users = modal.__users || [];
  const q = (document.getElementById('share-user-search').value || '').toLowerCase();
  const filtered = users.filter(u => (u.display_name || '').toLowerCase().includes(q));
  const picker = document.getElementById('share-user-picker');
  picker.innerHTML = filtered.length
    ? filtered.map(u =>
        `<div class="share-user-item" data-user-id="${u.id}">${escHtml(u.display_name || '')}</div>`
      ).join('')
    : `<span class="accounts-section-empty">${t('share_no_users')}</span>`;
  picker.querySelectorAll('.share-user-item').forEach(el => {
    el.addEventListener('click', async () => {
      const calId = parseInt(modal.dataset.calId);
      const permission = document.getElementById('share-permission').value;
      try {
        await api.post(`/local/calendars/${calId}/shares`,
                       { user_id: parseInt(el.dataset.userId), permission });
        await refreshShareModal(calId);
      } catch (e) { showToast(e.message, true); }
    });
  });
}

// ── Groups ────────────────────────────────────────────────
async function loadGroups() {
  try {
    state.groups = await api.get('/groups/') || [];
  } catch (e) { state.groups = []; }
  renderGroupList();
}

function renderGroupList() {
  const el = document.getElementById('group-list-items');
  if (!el) return;
  if (!state.groups.length) {
    el.innerHTML = `<div class="cal-list-empty">${t('groups_none')}</div>`;
    return;
  }
  el.innerHTML = state.groups.map(g =>
    `<div class="cal-item group-item ${g.id === state.activeGroupId ? 'group-item-active' : ''}" data-group-id="${g.id}">
      <span class="group-emoji" data-group-open="${g.id}">${groupIconHtml(g.icon)}</span>
      <span class="cal-item-name" data-group-open="${g.id}">${escHtml(g.name)}</span>
      <button class="icon-btn mini-btn" data-group-edit="${g.id}" title="${t('group_manage')}">
        <svg viewBox="0 0 24 24" fill="currentColor" width="16" height="16"><path d="M12 8c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm0 2c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0 6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"/></svg>
      </button>
    </div>`
  ).join('');
  el.querySelectorAll('[data-group-open]').forEach(s => {
    s.addEventListener('click', () => enterGroupView(parseInt(s.dataset.groupOpen)));
  });
  el.querySelectorAll('[data-group-edit]').forEach(b => {
    b.addEventListener('click', e => { e.stopPropagation(); openGroupModal(parseInt(b.dataset.groupEdit)); });
  });
}

// Open the new-event editor preselected to the active group's shared calendar.
function openGroupEventModal() {
  const g = state.groups.find(x => x.id === state.activeGroupId);
  if (!g || !g.group_calendar_id) { showToast(t('groups_none'), true); return; }
  openNewEventModal(state.selectedDate || state.currentDate);
  const sel = document.getElementById('ev-calendar');
  sel.value = `local-${g.group_calendar_id}`;
  updatePrivateRow(false);
}

async function enterGroupView(groupId) {
  state.activeGroupId = groupId;
  state.hiddenGroupMembers = new Set();
  state.activeGroupDetail = null;
  const g = state.groups.find(x => x.id === groupId);
  document.getElementById('group-view-banner').classList.remove('hidden');
  document.getElementById('group-view-label').textContent =
    t('group_view_label', { name: g ? g.name : '' });
  renderGroupList();
  // Load the member list (with server colours) for the per-member filter.
  try { state.activeGroupDetail = await api.get(`/groups/${groupId}`); } catch (e) { /* ignore */ }
  renderGroupMemberFilter();
  fetchAndRender(true);
}

function exitGroupView() {
  state.activeGroupId = null;
  state.activeGroupDetail = null;
  state.hiddenGroupMembers = new Set();
  document.getElementById('group-view-banner').classList.add('hidden');
  renderGroupMemberFilter();
  renderGroupList();
  fetchAndRender(true);
}

// Group members live in the sidebar (like the calendar list): each row has a
// colour dot (tap to recolour that member just for your view) and a checkbox to
// hide/show them in the combined overlay. The personal calendar list is hidden
// while a group is active.
function renderGroupMemberFilter() {
  const section = document.getElementById('group-members');
  const items = document.getElementById('group-members-items');
  const calList = document.getElementById('cal-list');
  const active = !!(state.activeGroupId && state.activeGroupDetail);
  if (section) section.classList.toggle('hidden', !active);
  if (calList) calList.classList.toggle('hidden', !!state.activeGroupId);
  if (!active || !items) return;

  const g = state.activeGroupDetail;
  const gid = state.activeGroupId;
  const row = (numKey, colorKey, name, baseColor) => {
    const hidden = state.hiddenGroupMembers.has(numKey);
    const color = groupColorOverride(gid, colorKey) || baseColor || '#4285f4';
    return `<div class="cal-item gm-row">
      <input type="checkbox" class="gm-vis" ${hidden ? '' : 'checked'} data-k="${colorKey}" />
      <div class="cal-item-dot gm-dot" style="background:${color}" data-k="${colorKey}" data-color="${color}" title="${t('change_color')}"></div>
      <span class="cal-item-name">${escHtml(name)}</span>
    </div>`;
  };
  const parts = (g.members || []).map(m => row(m.id, String(m.id), m.display_name || '—', m.color));
  parts.push(row('gc', 'gc', t('group_calendar'), g.group_calendar_color));
  items.innerHTML = parts.join('');

  items.querySelectorAll('.gm-vis').forEach(cb => {
    cb.addEventListener('change', () => {
      const ck = cb.dataset.k;
      const key = ck === 'gc' ? 'gc' : parseInt(ck);
      if (cb.checked) state.hiddenGroupMembers.delete(key);
      else state.hiddenGroupMembers.add(key);
      renderView();
    });
  });
  items.querySelectorAll('.gm-dot').forEach(dot => {
    dot.addEventListener('click', async () => {
      const picked = await openColorPicker(dot, dot.dataset.color || '#4285f4');
      if (picked) {
        setGroupColorOverride(gid, dot.dataset.k, picked);
        renderGroupMemberFilter();
        fetchAndRender(true);
      }
    });
  });
}

// Open the group modal in create mode (no id) or manage mode (existing group).
async function openGroupModal(groupId) {
  const modal = document.getElementById('modal-group');
  modal.dataset.groupId = groupId ? String(groupId) : '';
  const isEdit = !!groupId;
  document.getElementById('group-modal-title').textContent =
    isEdit ? t('group_manage') : t('group_create');
  document.getElementById('group-delete').classList.toggle('hidden', !isEdit);

  let detail = null, directory = [];
  try { directory = await api.get('/users/directory') || []; } catch (e) { /* ignore */ }
  if (isEdit) {
    try { detail = await api.get(`/groups/${groupId}`); } catch (e) { showToast(e.message, true); }
  }
  const me = JSON.parse(localStorage.getItem('user') || '{}');
  const existingMemberIds = new Set((detail ? detail.members : []).map(m => m.id));

  document.getElementById('group-name').value = detail ? detail.name : '';
  document.getElementById('group-name').disabled = false;  // rename supported via PUT

  // Icon picker
  modal.__icon = (detail && GROUP_ICON_KEYS.includes(detail.icon)) ? detail.icon : 'people';
  renderGroupIconPicker();

  // Member picker: current members are checked; the owner (me) is excluded.
  modal.__directory = directory;
  modal.__memberIds = new Set([...existingMemberIds].filter(id => id !== me.id));
  renderGroupMemberPicker();

  // Member colours (edit mode only): owner can recolour any member.
  const colorsGroup = document.getElementById('group-colors-group');
  if (isEdit && detail) {
    colorsGroup.style.display = '';
    renderGroupMemberColors(groupId, detail.members || []);
  } else {
    colorsGroup.style.display = 'none';
  }

  openModal('modal-group');
}

function renderGroupMemberColors(groupId, members) {
  const el = document.getElementById('group-member-colors');
  if (!el) return;
  el.innerHTML = members.map(m =>
    `<div class="pick-row" style="cursor:default">
      <span class="cal-item-dot group-color-dot" data-uid="${m.id}" data-color="${m.color || '#4285f4'}"
            style="background:${m.color || '#4285f4'};cursor:pointer" title="${t('change_color')}"></span>
      <span class="pick-name">${escHtml(m.display_name || '')}</span>
    </div>`
  ).join('');
  el.querySelectorAll('.group-color-dot').forEach(dot => {
    dot.addEventListener('click', async () => {
      const picked = await openColorPicker(dot, dot.dataset.color);
      if (!picked) return;
      try {
        await api.put(`/groups/${groupId}/members/${dot.dataset.uid}/color`, { color: picked });
        dot.style.background = picked;
        dot.dataset.color = picked;
      } catch (e) { showToast(e.message, true); }
    });
  });
}

// Cross-platform group icons: semantic keys stored server-side, rendered as
// inline SVG here (SF Symbols on iOS, Material on Android) so they look the same
// everywhere instead of relying on OS-specific emoji.
const GROUP_ICON_KEYS = ['people', 'home', 'heart', 'work', 'school', 'sports',
                         'party', 'pet', 'travel', 'music', 'food', 'star'];
const GROUP_ICON_PATHS = {
  people: 'M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z',
  home: 'M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z',
  heart: 'M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z',
  work: 'M20 6h-4V4c0-1.11-.89-2-2-2h-4c-1.11 0-2 .89-2 2v2H4c-1.11 0-1.99.89-1.99 2L2 19c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V8c0-1.11-.89-2-2-2zm-6 0h-4V4h4v2z',
  school: 'M5 13.18v4L12 21l7-3.82v-4L12 17l-7-3.82zM12 3L1 9l11 6 9-4.91V17h2V9L12 3z',
  sports: 'M19 5h-2V3H7v2H5c-1.1 0-2 .9-2 2v1c0 2.55 1.92 4.63 4.39 4.94.63 1.5 1.98 2.63 3.61 2.96V19H7v2h10v-2h-4v-3.1c1.63-.33 2.98-1.46 3.61-2.96C19.08 12.63 21 10.55 21 8V7c0-1.1-.9-2-2-2zM5 8V7h2v3.82C5.84 10.4 5 9.3 5 8zm14 0c0 1.3-.84 2.4-2 2.82V7h2v1z',
  party: 'M19 9l1.25-2.75L23 5l-2.75-1.25L19 1l-1.25 2.75L15 5l2.75 1.25L19 9zm-7.5.5L9 4 6.5 9.5 1 12l5.5 2.5L9 20l2.5-5.5L17 12l-5.5-2.5zM19 15l-1.25 2.75L15 19l2.75 1.25L19 23l1.25-2.75L23 19l-2.75-1.25L19 15z',
  pet: 'M12 14c-2.5 0-4.5 1.8-4.5 4 0 .6.4 1 1 1h7c.6 0 1-.4 1-1 0-2.2-2-4-4.5-4zM6 9.5a1.5 2 0 1 0 0 4 1.5 2 0 0 0 0-4zm12 0a1.5 2 0 1 0 0 4 1.5 2 0 0 0 0-4zM9 6a1.5 2 0 1 0 0 4 1.5 2 0 0 0 0-4zm6 0a1.5 2 0 1 0 0 4 1.5 2 0 0 0 0-4z',
  travel: 'M21 16v-2l-8-5V3.5c0-.83-.67-1.5-1.5-1.5S10 2.67 10 3.5V9l-8 5v2l8-2.5V19l-2 1.5V22l3.5-1 3.5 1v-1.5L13 19v-5.5l8 2.5z',
  music: 'M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z',
  food: 'M11 9H9V2H7v7H5V2H3v7c0 2.12 1.66 3.84 3.75 3.97V22h2.5v-9.03C11.34 12.84 13 11.12 13 9V2h-2v7zm5-3v8h2.5v8H21V2c-2.76 0-5 2.24-5 4z',
  star: 'M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z',
};
function groupIconSvg(key, size = 18) {
  const p = GROUP_ICON_PATHS[key] || GROUP_ICON_PATHS.people;
  return `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="currentColor" aria-hidden="true"><path d="${p}"/></svg>`;
}
// Render a group's stored icon: SVG for known keys, legacy emoji as-is.
function groupIconHtml(icon, size = 18) {
  if (GROUP_ICON_KEYS.includes(icon)) return groupIconSvg(icon, size);
  if (icon) return escHtml(icon);
  return groupIconSvg('people', size);
}

// Icons specifically for the "this calendar is shared with a group" indicator.
const SHARE_ICON_KEYS = ['share', 'link', 'send', 'eye', 'upload', 'wifi', 'person_add', 'ios_share'];
const SHARE_ICON_PATHS = {
  share:      'M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7c.05-.23.09-.46.09-.7s-.04-.47-.09-.7l7.05-4.11c.54.5 1.25.81 2.04.81 1.66 0 3-1.34 3-3s-1.34-3-3-3-3 1.34-3 3c0 .24.04.47.09.7L8.04 9.81C7.5 9.31 6.79 9 6 9c-1.66 0-3 1.34-3 3s1.34 3 3 3c.79 0 1.5-.31 2.04-.81l7.12 4.16c-.05.21-.08.43-.08.65 0 1.61 1.31 2.92 2.92 2.92s2.92-1.31 2.92-2.92-1.31-2.92-2.92-2.92z',
  link:       'M3.9 12c0-1.71 1.39-3.1 3.1-3.1h4V7H7c-2.76 0-5 2.24-5 5s2.24 5 5 5h4v-1.9H7c-1.71 0-3.1-1.39-3.1-3.1zM8 13h8v-2H8v2zm9-6h-4v1.9h4c1.71 0 3.1 1.39 3.1 3.1s-1.39 3.1-3.1 3.1h-4V17h4c2.76 0 5-2.24 5-5s-2.24-5-5-5z',
  send:       'M2.01 21L23 12 2.01 3 2 10l15 2-15 2z',
  eye:        'M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zM12 17c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5zm0-8c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3z',
  upload:     'M9 16h6v-6h4l-7-7-7 7h4v6zm-4 2h14v2H5v-2z',
  wifi:       'M1 9l2 2c4.97-4.97 13.03-4.97 18 0l2-2C16.93 2.93 7.08 2.93 1 9zm8 8l3 3 3-3c-1.65-1.66-4.34-1.66-6 0zm-4-4l2 2c2.76-2.76 7.24-2.76 10 0l2-2C15.14 9.14 8.87 9.14 5 13z',
  person_add: 'M15 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm-9-2V7H4v3H1v2h3v3h2v-3h3v-2H6zm9 4c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z',
  ios_share:  'M16 5l-1.42 1.42-1.59-1.59V16h-1.98V4.83L9.42 6.42 8 5l4-4 4 4zm4 5v11c0 1.1-.9 2-2 2H6c-1.11 0-2-.9-2-2V10c0-1.11.89-2 2-2h3v2H6v11h12V10h-3V8h3c1.1 0 2 .89 2 2z',
};
function shareIconSvg(key, size = 18) {
  const p = SHARE_ICON_PATHS[key] || SHARE_ICON_PATHS.share;
  return `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="currentColor" aria-hidden="true"><path d="${p}"/></svg>`;
}
function renderGroupIconPicker() {
  const modal = document.getElementById('modal-group');
  const sel = modal.__icon || 'people';
  const picker = document.getElementById('group-icon-picker');
  if (!picker) return;
  picker.innerHTML = GROUP_ICON_KEYS.map(ic =>
    `<button type="button" class="group-icon-opt ${ic === sel ? 'on' : ''}" data-icon="${ic}">${groupIconSvg(ic, 22)}</button>`
  ).join('');
  picker.querySelectorAll('.group-icon-opt').forEach(b => {
    b.addEventListener('click', () => {
      modal.__icon = b.dataset.icon;
      renderGroupIconPicker();
    });
  });
}

function renderGroupMemberPicker() {
  const modal = document.getElementById('modal-group');
  const dir = modal.__directory || [];
  const picked = modal.__memberIds || new Set();
  const picker = document.getElementById('group-member-picker');
  picker.innerHTML = dir.length
    ? dir.map(u => {
        const on = picked.has(u.id);
        return `<div class="pick-row ${on ? 'pick-row-sel' : ''}" data-member-id="${u.id}" role="checkbox" aria-checked="${on}">
          <span class="pick-mark pick-check ${on ? 'on' : ''}">${on ? '✓' : ''}</span>
          <span class="pick-name">${escHtml(u.display_name || '')}</span>
        </div>`;
      }).join('')
    : `<span class="accounts-section-empty">${t('share_no_users')}</span>`;
  picker.querySelectorAll('.pick-row').forEach(rowEl => {
    rowEl.addEventListener('click', () => {
      const id = parseInt(rowEl.dataset.memberId);
      if (picked.has(id)) picked.delete(id); else picked.add(id);
      renderGroupMemberPicker();
    });
  });
}

function bindGroupUI() {
  const addBtn = document.getElementById('btn-add-group');
  if (addBtn) addBtn.onclick = () => openGroupModal(null);
  const exitBtn = document.getElementById('group-view-exit');
  if (exitBtn) exitBtn.onclick = exitGroupView;
  const newEvtBtn = document.getElementById('group-view-new-event');
  if (newEvtBtn) newEvtBtn.onclick = openGroupEventModal;

  document.getElementById('group-save').onclick = async () => {
    const modal = document.getElementById('modal-group');
    const groupId = modal.dataset.groupId;
    const memberIds = [...(modal.__memberIds || new Set())];
    try {
      const name = document.getElementById('group-name').value.trim();
      const icon = modal.__icon || 'people';
      if (!name) { showToast(t('error_enter_title'), true); return; }
      if (groupId) {
        // Manage mode: update name/icon, then sync member additions/removals.
        await api.put(`/groups/${groupId}`, { name, icon });
        const detail = await api.get(`/groups/${groupId}`);
        const me = JSON.parse(localStorage.getItem('user') || '{}');
        const current = new Set(detail.members.map(m => m.id).filter(id => id !== me.id));
        for (const id of memberIds) if (!current.has(id)) await api.post(`/groups/${groupId}/members`, { user_id: id });
        for (const id of current) if (!memberIds.includes(id)) await api.delete(`/groups/${groupId}/members/${id}`);
        showToast(t('group_saved'));
      } else {
        await api.post('/groups/', { name, member_ids: memberIds, icon });
        showToast(t('group_created'));
      }
      closeModal('modal-group');
      await loadGroups();
      // Refresh local calendars too (a new group creates a group calendar).
      try { state.localCalendars = await api.get('/local/calendars') || state.localCalendars; } catch (e) {}
      renderCalendarList();
    } catch (e) { showToast(e.message, true); }
  };

  document.getElementById('group-delete').onclick = async () => {
    const modal = document.getElementById('modal-group');
    const groupId = modal.dataset.groupId;
    if (!groupId) return;
    if (!confirm(t('group_delete_confirm'))) return;
    try {
      await api.delete(`/groups/${groupId}`);
      if (state.activeGroupId === parseInt(groupId)) exitGroupView();
      closeModal('modal-group');
      await loadGroups();
      showToast(t('group_deleted'));
    } catch (e) { showToast(e.message, true); }
  };
}

// Radio list of the user's OWN local calendars to pick the one visible to
// group members (plus a "none" option). Selection is read on settings save.
function renderGroupVisibleList(selectedId) {
  const el = document.getElementById('cfg-group-visible-list');
  if (!el) return;
  el.dataset.selected = (selectedId == null) ? '' : String(selectedId);
  const own = state.localCalendars.filter(c => c.owned !== false && !c.group);
  const selVal = el.dataset.selected;
  const row = (id, name, color) => {
    const val = (id == null) ? '' : String(id);
    const sel = val === selVal;
    const dot = color
      ? `<span class="pick-dot" style="background:${color}"></span>`
      : `<span class="pick-dot pick-dot-empty"></span>`;
    return `<div class="pick-row ${sel ? 'pick-row-sel' : ''}" data-pick="${val}" role="radio" aria-checked="${sel}">
      <span class="pick-mark pick-radio ${sel ? 'on' : ''}"></span>
      ${dot}
      <span class="pick-name">${escHtml(name)}</span>
    </div>`;
  };
  el.innerHTML =
    row(null, t('group_visible_none'), null) +
    own.map(c => row(c.id, c.name, c.color)).join('');
  el.querySelectorAll('.pick-row').forEach(r => {
    r.addEventListener('click', () => {
      el.dataset.selected = r.dataset.pick;
      renderGroupVisibleList(r.dataset.pick === '' ? null : parseInt(r.dataset.pick));
    });
  });
}

// ── Settings Modal ────────────────────────────────────────
function openSettingsModal() {
  uiSettingsOpen = true;
  writeUrlState();
  const s = state.settings;
  document.getElementById('cfg-default-view').value  = s.default_view   || 'month';
  document.getElementById('cfg-week-start').value    = s.week_start_day || 'monday';
  const colors = [
    { id: 'cfg-primary',        val: s.primary_color        || '#4285f4' },
    { id: 'cfg-accent',         val: s.accent_color         || '#ea4335' },
    { id: 'cfg-today',          val: s.today_color          || '#4285f4' },
    { id: 'cfg-month-divider',  val: s.month_divider_color  || '#7090c0' },
    { id: 'cfg-month-label',    val: s.month_label_color    || '#7090c0' },
  ];
  colors.forEach(({ id, val }) => {
    document.getElementById(id + '-hex').value = val.toUpperCase();
    document.getElementById(id + '-preview').style.background = val;
  });

  // Override-Farben — leeres Hex-Input bedeutet "Default verwenden",
  // aber die Preview zeigt trotzdem die aktuell wirksame Farbe.
  [
    { id: 'cfg-text-color', val: s.text_color, fallback: DEFAULT_TEXT_COLOR },
    { id: 'cfg-line-color', val: s.line_color, fallback: DEFAULT_LINE_COLOR },
    { id: 'cfg-bg-color',   val: s.bg_color,   fallback: DEFAULT_BG_COLOR },
  ].forEach(({ id, val, fallback }) => {
    const hex = document.getElementById(id + '-hex');
    const prev = document.getElementById(id + '-preview');
    if (!hex || !prev) return;
    hex.value = val ? String(val).toUpperCase() : '';
    prev.style.background = val || fallback;
  });
  document.getElementById('cfg-dim-past').checked = !!s.dim_past_events;
  document.getElementById('cfg-language').value = getLang();
  document.getElementById('cfg-private-visibility').value = s.private_event_visibility || 'busy';
  renderGroupVisibleList(s.group_visible_calendar_id);

  // Share-Icon-Picker in Darstellung
  const shareIconPicker = document.getElementById('cfg-share-icon');
  if (shareIconPicker) {
    const cur = s.share_calendar_icon || 'share';
    shareIconPicker.innerHTML = SHARE_ICON_KEYS.map(k =>
      `<button type="button" class="group-icon-opt ${cur === k ? 'on' : ''}" data-share-icon="${k}" title="${k}">${shareIconSvg(k, 20)}</button>`
    ).join('');
    shareIconPicker.querySelectorAll('.group-icon-opt').forEach(btn => {
      btn.addEventListener('click', () => {
        shareIconPicker.querySelectorAll('.group-icon-opt').forEach(b => b.classList.remove('on'));
        btn.classList.add('on');
      });
    });
  }

  // Profile chapter: name (from cached user) + email (fresh from /profile).
  const pu = JSON.parse(localStorage.getItem('user') || '{}');
  document.getElementById('cfg-display-name').value = pu.display_name || pu.username || '';
  document.getElementById('cfg-login-name').value = pu.username || '';
  api.get('/profile/').then(p => {
    document.getElementById('cfg-email').value = p.email || '';
  }).catch(() => {});

  // Set active contrast/hour-height/duration buttons
  [
    { id: 'cfg-text-contrast',  val: s.text_contrast || 3 },
    { id: 'cfg-line-contrast',  val: s.line_contrast || 3 },
    { id: 'cfg-hour-height',    val: s.hour_height   || 60 },
    { id: 'cfg-event-duration', val: s.default_event_duration_minutes || 60 },
  ].forEach(({ id, val }) => {
    const sel = document.getElementById(id);
    if (!sel) return;
    sel.querySelectorAll('.contrast-btn').forEach(btn => {
      btn.classList.toggle('active', String(btn.dataset.val) === String(val));
    });
  });

  // Show users nav button only for admins
  const user = JSON.parse(localStorage.getItem('user') || '{}');
  const usersNavBtn = document.getElementById('settings-nav-users');
  if (usersNavBtn) usersNavBtn.classList.toggle('hidden', !user.is_admin);
  if (user.is_admin) loadUsers();

  // Activate panel from URL or fall back to first visible
  const urlTab = readUrlState().stab;
  const tabBtn = urlTab && document.querySelector(`.settings-nav-btn[data-panel="${urlTab}"]:not(.hidden)`);
  const firstBtn = tabBtn || document.querySelector('.settings-nav-btn:not(.hidden)');
  if (firstBtn) activateSettingsPanel(firstBtn.dataset.panel);

  // Render unified calendar table
  renderAllAccounts();

  openModal('modal-settings');
}

function activateSettingsPanel(panel) {
  document.querySelectorAll('.settings-nav-btn').forEach(b => b.classList.toggle('active', b.dataset.panel === panel));
  document.querySelectorAll('.settings-panel').forEach(p => p.classList.toggle('active', p.id === 'settings-panel-' + panel));
  writeUrlState();
}

function renderGoogleAccounts() {
  const list = document.getElementById('google-accounts-list');
  if (!list) return;
  if (!state.googleAccounts.length) {
    list.innerHTML = `<span style="font-size:13px;color:var(--text-3)">${t('settings_no_google')}</span>`;
    return;
  }
  list.innerHTML = state.googleAccounts.map(acc =>
    `<div style="display:flex;align-items:center;justify-content:space-between;padding:4px 0">
      <span style="font-size:13px">${escHtml(acc.email)}</span>
      <div style="display:flex;gap:6px">
        <button class="btn btn-secondary btn-sm" data-sync-acc="${acc.id}">${t('sync')}</button>
        <button class="btn btn-ghost btn-sm" data-disconnect-acc="${acc.id}">${t('disconnect')}</button>
      </div>
    </div>`
  ).join('');
  list.querySelectorAll('[data-sync-acc]').forEach(btn => {
    btn.addEventListener('click', async () => {
      btn.disabled = true;
      btn.textContent = '…';
      try {
        const updated = await api.post(`/google/accounts/${btn.dataset.syncAcc}/sync`);
        const idx = state.googleAccounts.findIndex(a => a.id === updated.id);
        if (idx !== -1) state.googleAccounts[idx] = updated;
        renderGoogleAccounts();
        renderCalendarList();
        fetchAndRender(true);
        showToast(t('google_synced'));
      } catch (e) { showToast(e.message, true); }
    });
  });
  list.querySelectorAll('[data-disconnect-acc]').forEach(btn => {
    btn.addEventListener('click', async () => {
      if (!confirm(t('confirm_google_disconnect'))) return;
      try {
        await api.delete(`/google/accounts/${btn.dataset.disconnectAcc}`);
        state.googleAccounts = state.googleAccounts.filter(a => a.id !== parseInt(btn.dataset.disconnectAcc));
        renderGoogleAccounts();
        renderCalendarList();
        fetchAndRender(true);
        showToast(t('google_disconnected'));
      } catch (e) { showToast(e.message, true); }
    });
  });
}

function renderAllAccounts() {
  // CalDAV section
  const caldavList = document.getElementById('accounts-caldav-list');
  if (caldavList) {
    if (!state.accounts.length) {
      caldavList.innerHTML = `<span class="accounts-section-empty">${t('settings_no_caldav_accounts')}</span>`;
    } else {
      caldavList.innerHTML = state.accounts.map(acc =>
        `<div class="accounts-row">
          <div class="accounts-row-info">
            <span class="accounts-row-name">${escHtml(acc.name)}</span>
            <span class="accounts-row-sub">${escHtml(acc.url || '')}</span>
          </div>
          <div class="accounts-row-actions">
            <button class="btn btn-secondary btn-sm" data-caldav-sync="${acc.id}">${t('sync')}</button>
            <button class="btn btn-ghost btn-sm" data-caldav-disconnect="${acc.id}">${t('disconnect')}</button>
          </div>
        </div>`
      ).join('');
      caldavList.querySelectorAll('[data-caldav-sync]').forEach(btn => {
        btn.addEventListener('click', async () => {
          btn.disabled = true; btn.textContent = '…';
          try {
            await api.post(`/caldav/accounts/${btn.dataset.caldavSync}/sync`);
            renderCalendarList(); fetchAndRender(true);
            showToast(t('google_synced'));
          } catch (e) { showToast(e.message, true); }
          finally { btn.disabled = false; btn.textContent = t('sync'); }
        });
      });
      caldavList.querySelectorAll('[data-caldav-disconnect]').forEach(btn => {
        btn.addEventListener('click', async () => {
          if (!confirm(t('confirm_caldav_disconnect'))) return;
          try {
            await api.delete(`/caldav/accounts/${btn.dataset.caldavDisconnect}`);
            state.accounts = state.accounts.filter(a => a.id !== parseInt(btn.dataset.caldavDisconnect));
            renderAllAccounts(); renderCalendarList(); fetchAndRender(true);
            showToast(t('caldav_disconnected'));
          } catch (e) { showToast(e.message, true); }
        });
      });
    }
  }

  // Local calendars section
  const localList = document.getElementById('accounts-local-list');
  if (localList) {
    if (!state.localCalendars.length) {
      localList.innerHTML = `<span class="accounts-section-empty">${t('settings_no_local_cals')}</span>`;
    } else {
      localList.innerHTML = state.localCalendars.map(cal => {
        const owned = cal.owned !== false;
        const sharedBadge = !owned
          ? `<span class="cal-badge cal-badge-shared">${t('shared_by', { name: cal.shared_by || '' })}</span>`
          : '';
        const canWrite = owned || cal.permission === 'read_write';
        const actions = [];
        if (owned) actions.push(`<button class="btn btn-ghost btn-sm" data-local-share="${cal.id}">${t('share')}</button>`);
        if (canWrite) actions.push(`<button class="btn btn-ghost btn-sm" data-local-import="${cal.id}">${t('import')}</button>`);
        actions.push(`<button class="btn btn-ghost btn-sm" data-local-export="${cal.id}" data-local-name="${escHtml(cal.name)}">${t('export')}</button>`);
        return `<div class="accounts-row">
          <div style="display:flex;align-items:center;gap:8px;min-width:0">
            <span class="accounts-local-dot" style="background:${cal.color || '#34a853'}"></span>
            <span class="accounts-row-name">${escHtml(cal.name)}</span>
            ${sharedBadge}
          </div>
          <div class="accounts-row-actions">${actions.join('')}</div>
        </div>`;
      }).join('');

      localList.querySelectorAll('[data-local-export]').forEach(btn => {
        btn.addEventListener('click', async () => {
          try {
            await api.download(`/local/calendars/${btn.dataset.localExport}/export`,
                               `${btn.dataset.localName || 'calendar'}.ics`);
          } catch (e) { showToast(e.message, true); }
        });
      });
      localList.querySelectorAll('[data-local-import]').forEach(btn => {
        btn.addEventListener('click', () => triggerIcsImport(parseInt(btn.dataset.localImport)));
      });
      localList.querySelectorAll('[data-local-share]').forEach(btn => {
        btn.addEventListener('click', () => openShareModal(parseInt(btn.dataset.localShare)));
      });
    }
  }

  // iCal subscriptions section
  const icalList = document.getElementById('accounts-ical-list');
  if (icalList) {
    if (!state.icalSubscriptions.length) {
      icalList.innerHTML = `<span class="accounts-section-empty">${t('settings_no_ical_subs')}</span>`;
    } else {
      icalList.innerHTML = state.icalSubscriptions.map(sub =>
        `<div class="accounts-row">
          <div class="accounts-row-info">
            <span class="accounts-row-name">${escHtml(sub.name)}</span>
            <span class="accounts-row-sub">${escHtml(sub.url || '')}</span>
          </div>
          <div class="accounts-row-actions">
            <button class="btn btn-ghost btn-sm" data-ical-delete="${sub.id}">${t('delete')}</button>
          </div>
        </div>`
      ).join('');
      icalList.querySelectorAll('[data-ical-delete]').forEach(btn => {
        btn.addEventListener('click', async () => {
          if (!confirm(t('confirm_remove_ical'))) return;
          try {
            await api.delete(`/ical/subscriptions/${btn.dataset.icalDelete}`);
            state.icalSubscriptions = state.icalSubscriptions.filter(s => s.id !== parseInt(btn.dataset.icalDelete));
            renderAllAccounts(); renderCalendarList(); fetchAndRender(true);
          } catch (e) { showToast(e.message, true); }
        });
      });
    }
  }

  // Home Assistant accounts section
  const haList = document.getElementById('accounts-ha-list');
  if (haList) {
    if (!state.haAccounts.length) {
      haList.innerHTML = '<span class="accounts-section-empty">Keine HA-Konten</span>';
    } else {
      haList.innerHTML = state.haAccounts.map(acc =>
        `<div class="accounts-row">
          <div class="accounts-row-info">
            <span class="accounts-row-name">${escHtml(acc.name)}</span>
            <span class="accounts-row-sub">${escHtml(acc.url || '')}</span>
          </div>
          <div class="accounts-row-actions">
            <button class="btn btn-secondary btn-sm" data-ha-sync="${acc.id}">${t('sync')}</button>
            <button class="btn btn-ghost btn-sm" data-ha-disconnect="${acc.id}">${t('disconnect')}</button>
          </div>
        </div>`
      ).join('');
      haList.querySelectorAll('[data-ha-sync]').forEach(btn => {
        btn.addEventListener('click', async () => {
          btn.disabled = true; btn.textContent = '…';
          try {
            const updated = await api.post(`/homeassistant/accounts/${btn.dataset.haSync}/sync`);
            const idx = state.haAccounts.findIndex(a => a.id === parseInt(btn.dataset.haSync));
            if (idx !== -1) state.haAccounts[idx] = updated;
            renderAllAccounts(); renderCalendarList(); fetchAndRender(true);
            showToast('Home Assistant synchronisiert');
          } catch (e) { showToast(e.message, true); }
          finally { btn.disabled = false; btn.textContent = t('sync'); }
        });
      });
      haList.querySelectorAll('[data-ha-disconnect]').forEach(btn => {
        btn.addEventListener('click', async () => {
          if (!confirm('Home Assistant Konto wirklich trennen?')) return;
          try {
            await api.delete(`/homeassistant/accounts/${btn.dataset.haDisconnect}`);
            state.haAccounts = state.haAccounts.filter(a => a.id !== parseInt(btn.dataset.haDisconnect));
            renderAllAccounts(); renderCalendarList(); fetchAndRender(true);
            showToast('Home Assistant getrennt');
          } catch (e) { showToast(e.message, true); }
        });
      });
    }
  }

  renderCalendarTable();
}

function renderHiddenCalendars() {
  const list = document.getElementById('hidden-cals-list');
  if (!list) return;
  const hidden = [];
  for (const acc of state.accounts) {
    for (const cal of acc.calendars) {
      if (cal.sidebar_hidden) hidden.push({ id: cal.id, name: cal.name, acc: acc.name, source: 'caldav' });
    }
  }
  for (const acc of state.googleAccounts) {
    for (const cal of acc.calendars) {
      if (cal.sidebar_hidden) hidden.push({ id: cal.id, name: cal.name, acc: acc.email, source: 'google' });
    }
  }
  for (const acc of state.haAccounts) {
    for (const cal of acc.calendars) {
      if (cal.sidebar_hidden) hidden.push({ id: cal.id, name: cal.name, acc: acc.name, source: 'homeassistant' });
    }
  }
  if (!hidden.length) {
    list.innerHTML = `<span style="font-size:13px;color:var(--text-3)">${t('settings_no_hidden_cals')}</span>`;
    return;
  }
  list.innerHTML = hidden.map(c =>
    `<div style="display:flex;align-items:center;justify-content:space-between;padding:8px 0;border-bottom:1px solid var(--border-light)">
      <span style="font-size:13px">${escHtml(c.acc)} / ${escHtml(c.name)}</span>
      <button class="btn btn-secondary btn-sm" data-restore-cal="${c.id}" data-restore-source="${c.source}">${t('show_cal')}</button>
    </div>`
  ).join('');
  list.querySelectorAll('[data-restore-cal]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const calId = parseInt(btn.dataset.restoreCal);
      const source = btn.dataset.restoreSource;
      if (source === 'google') {
        await api.put(`/google/calendars/${calId}`, { enabled: true, sidebar_hidden: false });
        for (const acc of state.googleAccounts) {
          for (const cal of acc.calendars) {
            if (cal.id === calId) { cal.enabled = true; cal.sidebar_hidden = false; }
          }
        }
      } else if (source === 'homeassistant') {
        await api.put(`/homeassistant/calendars/${calId}`, { enabled: true, sidebar_hidden: false });
        for (const acc of state.haAccounts) {
          for (const cal of acc.calendars) {
            if (cal.id === calId) { cal.enabled = true; cal.sidebar_hidden = false; }
          }
        }
      } else {
        await api.put(`/caldav/calendars/${calId}`, { enabled: true, sidebar_hidden: false });
        for (const acc of state.accounts) {
          for (const cal of acc.calendars) {
            if (cal.id === calId) { cal.enabled = true; cal.sidebar_hidden = false; }
          }
        }
      }
      renderHiddenCalendars();
      renderCalendarList();
      fetchAndRender();
    });
  });
}

function renderCalendarTable() {
  const container = document.getElementById('cal-settings-table');
  if (!container) return;

  const TRASH   = `<svg viewBox="0 0 24 24" fill="currentColor" width="14" height="14"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>`;
  const EYE_ON   = `<svg viewBox="0 0 24 24" fill="currentColor" width="16" height="16"><path d="M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zM12 17c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5zm0-8c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3z"/></svg>`;
  const EYE_OFF  = `<svg viewBox="0 0 24 24" fill="currentColor" width="16" height="16"><path d="M12 7c2.76 0 5 2.24 5 5 0 .65-.13 1.26-.36 1.83l2.92 2.92c1.51-1.26 2.7-2.89 3.43-4.75-1.73-4.39-6-7.5-11-7.5-1.4 0-2.74.25-3.98.7l2.16 2.16C10.74 7.13 11.35 7 12 7zM2 4.27l2.28 2.28.46.46C3.08 8.3 1.78 10.02 1 12c1.73 4.39 6 7.5 11 7.5 1.55 0 3.03-.3 4.38-.84l.42.42L19.73 22 21 20.73 3.27 3 2 4.27zM7.53 9.8l1.55 1.55c-.05.21-.08.43-.08.65 0 1.66 1.34 3 3 3 .22 0 .44-.03.65-.08l1.55 1.55c-.67.33-1.41.53-2.2.53-2.76 0-5-2.24-5-5 0-.79.2-1.53.53-2.2zm4.31-.78l3.15 3.15.02-.16c0-1.66-1.34-3-3-3l-.17.01z"/></svg>`;
  const BELL_ON  = `<svg viewBox="0 0 24 24" fill="currentColor" width="16" height="16"><path d="M12 22c1.1 0 2-.9 2-2h-4c0 1.1.9 2 2 2zm6-6v-5c0-3.07-1.63-5.64-4.5-6.32V4c0-.83-.67-1.5-1.5-1.5s-1.5.67-1.5 1.5v.68C7.64 5.36 6 7.92 6 11v5l-2 2v1h16v-1l-2-2z"/></svg>`;
  const BELL_OFF = `<svg viewBox="0 0 24 24" fill="currentColor" width="16" height="16"><path d="M20 18.69L7.84 6.14 5.27 3.49 4 4.76l2.8 2.8v.01c-.52.99-.8 2.16-.8 3.42v5l-2 2v1h13.73l2 2L21 19.72l-1-1.03zM12 22c1.11 0 2-.89 2-2h-4c0 1.11.89 2 2 2zm6-7.32V11c0-3.08-1.64-5.64-4.5-6.32V4c0-.83-.67-1.5-1.5-1.5s-1.5.67-1.5 1.5v.68c-.15.03-.29.08-.42.12-.1.03-.2.07-.3.11h-.01c-.01 0-.01 0-.02.01-.23.09-.46.2-.68.31L18 14.68z"/></svg>`;
  let rowCount = 0;

  const hid  = (src, id, isVisible) =>
    `<button class="icon-btn mini-btn ct-eye" data-ct-hid="${src}" data-ct-id="${id}" data-ct-visible="${isVisible ? '1' : '0'}" title="${isVisible ? 'Ausblenden' : 'Anzeigen'}">${isVisible ? EYE_ON : EYE_OFF}</button>`;
  const rem  = (src, id, on) =>
    `<button class="icon-btn mini-btn ct-bell" data-ct-rem="${src}" data-ct-id="${id}" data-ct-on="${on ? '1' : '0'}" title="${on ? 'Benachrichtigungen aus' : 'Benachrichtigungen an'}">${on ? BELL_ON : BELL_OFF}</button>`;
  const dot  = (color, fb) =>
    `<span class="ct-dot" style="background:${color || fb}"></span>`;

  let rows = '';

  // Local calendars
  for (const cal of state.localCalendars) {
    if (cal.group) continue;
    const owned = cal.owned !== false;
    const canWrite = owned || cal.permission === 'read_write';
    const pub = !!cal.caldav_published;
    rows += `<tr>
      <td>${dot(cal.color, '#34a853')}${escHtml(cal.name)}</td>
      <td class="ct-src">Lokal</td>
      <td>—</td>
      <td>${owned ? rem('local', cal.id, cal.reminders_enabled !== false) : '—'}</td>
      <td>
        <button class="btn btn-ghost btn-sm" data-ct-export="local" data-ct-id="${cal.id}" data-ct-name="${escHtml(cal.name)}">Export</button>
        ${canWrite ? `<button class="btn btn-ghost btn-sm" data-ct-import="local" data-ct-id="${cal.id}">Import</button>` : ''}
        ${owned ? `<button class="btn btn-ghost btn-sm ct-dav-toggle${pub ? ' on' : ''}" data-ct-dav-id="${cal.id}" data-ct-dav-on="${pub ? '1' : '0'}">${pub ? t('caldav_unpublish') : t('caldav_publish')}</button>` : ''}
      </td>
      <td>—</td>
      <td>${owned ? `<button class="icon-btn mini-btn" data-ct-del="local" data-ct-id="${cal.id}">${TRASH}</button>` : ''}</td>
    </tr>`;
    rowCount++;
    if (owned && pub) {
      rows += `<tr class="ct-dav-row"><td colspan="7">
        <div class="ct-dav-box">
          <span class="ct-dav-label">${t('caldav_published_url')}</span>
          <input class="ct-dav-url" type="text" readonly value="${escHtml(cal.caldav_url || '')}">
          <button class="btn btn-ghost btn-sm ct-dav-copy">${t('copy')}</button>
          <button class="btn btn-ghost btn-sm ct-dav-rotate" data-ct-dav-id="${cal.id}">${t('caldav_token_rotate')}</button>
        </div>
        <div class="ct-dav-hint">${t('caldav_hint')}</div>
      </td></tr>`;
    }
  }

  // iCal subscriptions
  for (const sub of state.icalSubscriptions) {
    rows += `<tr>
      <td>${dot(sub.color, '#aa66cc')}${escHtml(sub.name)}</td>
      <td class="ct-src">iCal</td>
      <td>${hid('ical', sub.id, !sub.sidebar_hidden)}</td>
      <td>${rem('ical', sub.id, sub.reminders_enabled !== false)}</td>
      <td>—</td>
      <td>—</td>
      <td><button class="icon-btn mini-btn" data-ct-del="ical" data-ct-id="${sub.id}">${TRASH}</button></td>
    </tr>`;
    rowCount++;
  }

  // CalDAV accounts + their calendars
  for (const acc of state.accounts) {
    rows += `<tr class="ct-acc-row">
      <td colspan="2"><strong>${escHtml(acc.name)}</strong><span class="ct-badge">CalDAV</span></td>
      <td>—</td><td>—</td><td>—</td>
      <td><button class="btn btn-secondary btn-sm" data-ct-sync="caldav" data-ct-id="${acc.id}">${t('sync')}</button></td>
      <td><button class="btn btn-ghost btn-sm" data-ct-disc="caldav" data-ct-id="${acc.id}">${t('disconnect')}</button></td>
    </tr>`;
    rowCount++;
    for (const cal of (acc.calendars || [])) {
      rows += `<tr class="ct-cal-row">
        <td class="ct-indent">${dot(cal.color, '#4285f4')}${escHtml(cal.name)}</td>
        <td class="ct-src">${escHtml(acc.name)}</td>
        <td>${hid('caldav', cal.id, !cal.sidebar_hidden)}</td>
        <td>${rem('caldav', cal.id, cal.reminders_enabled !== false)}</td>
        <td>—</td><td>—</td><td>—</td>
      </tr>`;
      rowCount++;
    }
  }

  // Google accounts + their calendars
  for (const acc of state.googleAccounts) {
    rows += `<tr class="ct-acc-row">
      <td colspan="2"><strong>${escHtml(acc.email)}</strong><span class="ct-badge ct-badge-g">Google</span></td>
      <td>—</td><td>—</td><td>—</td>
      <td><button class="btn btn-secondary btn-sm" data-ct-sync="google" data-ct-id="${acc.id}">${t('sync')}</button></td>
      <td><button class="btn btn-ghost btn-sm" data-ct-disc="google" data-ct-id="${acc.id}">${t('disconnect')}</button></td>
    </tr>`;
    rowCount++;
    for (const cal of (acc.calendars || [])) {
      rows += `<tr class="ct-cal-row">
        <td class="ct-indent">${dot(cal.color, '#4285f4')}${escHtml(cal.name)}</td>
        <td class="ct-src">${escHtml(acc.email)}</td>
        <td>${hid('google', cal.id, !cal.sidebar_hidden)}</td>
        <td>${rem('google', cal.id, cal.reminders_enabled !== false)}</td>
        <td>—</td><td>—</td><td>—</td>
      </tr>`;
      rowCount++;
    }
  }

  // Home Assistant accounts + their calendars
  for (const acc of state.haAccounts) {
    rows += `<tr class="ct-acc-row">
      <td colspan="2"><strong>${escHtml(acc.name)}</strong><span class="ct-badge ct-badge-ha">Home Assistant</span></td>
      <td>—</td><td>—</td><td>—</td>
      <td><button class="btn btn-secondary btn-sm" data-ct-sync="ha" data-ct-id="${acc.id}">${t('sync')}</button></td>
      <td><button class="btn btn-ghost btn-sm" data-ct-disc="ha" data-ct-id="${acc.id}">${t('disconnect')}</button></td>
    </tr>`;
    rowCount++;
    for (const cal of (acc.calendars || [])) {
      rows += `<tr class="ct-cal-row">
        <td class="ct-indent">${dot(cal.color, '#03a9f4')}${escHtml(cal.name)}</td>
        <td class="ct-src">${escHtml(acc.name)}</td>
        <td>${hid('ha', cal.id, !cal.sidebar_hidden)}</td>
        <td>${rem('ha', cal.id, cal.reminders_enabled !== false)}</td>
        <td>—</td><td>—</td><td>—</td>
      </tr>`;
      rowCount++;
    }
  }

  if (!rowCount) {
    rows = `<tr><td colspan="7" class="ct-empty">Keine Kalender vorhanden</td></tr>`;
  }

  container.innerHTML = `<table class="cal-manage-table">
    <thead><tr>
      <th>Name</th><th>Herkunft</th><th>Sichtbar</th><th>Benachrichtigungen</th><th>Export / Import</th><th>Sync</th><th></th>
    </tr></thead>
    <tbody>${rows}</tbody>
  </table>`;

  // Visibility eye toggle
  container.querySelectorAll('.ct-eye[data-ct-hid]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const src = btn.dataset.ctHid, id = parseInt(btn.dataset.ctId);
      const hidden = btn.dataset.ctVisible === '1'; // currently visible → we're hiding it
      try {
        if (src === 'ical') {
          await api.put(`/ical/subscriptions/${id}`, { sidebar_hidden: hidden });
          const s = state.icalSubscriptions.find(s => s.id === id);
          if (s) s.sidebar_hidden = hidden;
        } else if (src === 'caldav') {
          await api.put(`/caldav/calendars/${id}`, { enabled: !hidden, sidebar_hidden: hidden });
          for (const acc of state.accounts) { const c = acc.calendars.find(c => c.id === id); if (c) { c.sidebar_hidden = hidden; c.enabled = !hidden; } }
        } else if (src === 'google') {
          await api.put(`/google/calendars/${id}`, { enabled: !hidden, sidebar_hidden: hidden });
          for (const acc of state.googleAccounts) { const c = acc.calendars.find(c => c.id === id); if (c) { c.sidebar_hidden = hidden; c.enabled = !hidden; } }
        } else if (src === 'ha') {
          await api.put(`/homeassistant/calendars/${id}`, { enabled: !hidden, sidebar_hidden: hidden });
          for (const acc of state.haAccounts) { const c = acc.calendars.find(c => c.id === id); if (c) { c.sidebar_hidden = hidden; c.enabled = !hidden; } }
        }
        renderCalendarTable();
        renderCalendarList();
      } catch (e) { showToast(e.message, true); }
    });
  });

  // Reminders bell toggle
  container.querySelectorAll('.ct-bell[data-ct-rem]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const src = btn.dataset.ctRem, id = parseInt(btn.dataset.ctId);
      const enabled = btn.dataset.ctOn !== '1'; // currently on → turn off, currently off → turn on
      const path = src === 'ical' ? `/ical/subscriptions/${id}` : `/${src === 'ha' ? 'homeassistant' : src}/calendars/${id}`;
      try {
        await api.put(path, { reminders_enabled: enabled });
        if (src === 'local')       { const c = state.localCalendars.find(c => c.id === id); if (c) c.reminders_enabled = enabled; }
        else if (src === 'ical')   { const s = state.icalSubscriptions.find(s => s.id === id); if (s) s.reminders_enabled = enabled; }
        else if (src === 'caldav') { for (const acc of state.accounts) { const c = acc.calendars.find(c => c.id === id); if (c) c.reminders_enabled = enabled; } }
        else if (src === 'google') { for (const acc of state.googleAccounts) { const c = acc.calendars.find(c => c.id === id); if (c) c.reminders_enabled = enabled; } }
        else if (src === 'ha')     { for (const acc of state.haAccounts) { const c = acc.calendars.find(c => c.id === id); if (c) c.reminders_enabled = enabled; } }
        renderCalendarTable();
        renderCalendarList();
      } catch (e) { showToast(e.message, true); }
    });
  });

  // Sync buttons
  container.querySelectorAll('[data-ct-sync]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const src = btn.dataset.ctSync, id = parseInt(btn.dataset.ctId);
      const label = btn.textContent;
      btn.disabled = true; btn.textContent = '…';
      try {
        if (src === 'caldav') {
          await api.post(`/caldav/accounts/${id}/sync`);
        } else if (src === 'google') {
          const updated = await api.post(`/google/accounts/${id}/sync`);
          const idx = state.googleAccounts.findIndex(a => a.id === updated.id);
          if (idx !== -1) state.googleAccounts[idx] = updated;
        } else if (src === 'ha') {
          const updated = await api.post(`/homeassistant/accounts/${id}/sync`);
          const idx = state.haAccounts.findIndex(a => a.id === updated.id);
          if (idx !== -1) state.haAccounts[idx] = updated;
        }
        renderCalendarTable(); renderCalendarList(); fetchAndRender(true);
        showToast(t('google_synced'));
      } catch (e) { showToast(e.message, true); }
      finally { btn.disabled = false; btn.textContent = label; }
    });
  });

  // Disconnect buttons
  container.querySelectorAll('[data-ct-disc]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const src = btn.dataset.ctDisc, id = parseInt(btn.dataset.ctId);
      const msg = src === 'caldav' ? t('confirm_caldav_disconnect')
                : src === 'google' ? t('confirm_google_disconnect')
                : 'Konto wirklich trennen?';
      if (!confirm(msg)) return;
      try {
        if (src === 'caldav') {
          await api.delete(`/caldav/accounts/${id}`);
          state.accounts = state.accounts.filter(a => a.id !== id);
        } else if (src === 'google') {
          await api.delete(`/google/accounts/${id}`);
          state.googleAccounts = state.googleAccounts.filter(a => a.id !== id);
        } else if (src === 'ha') {
          await api.delete(`/homeassistant/accounts/${id}`);
          state.haAccounts = state.haAccounts.filter(a => a.id !== id);
        }
        renderCalendarTable(); renderCalendarList(); fetchAndRender(true);
        showToast(t('caldav_disconnected'));
      } catch (e) { showToast(e.message, true); }
    });
  });

  // Export / Import
  container.querySelectorAll('[data-ct-export]').forEach(btn => {
    btn.addEventListener('click', async () => {
      try { await api.download(`/local/calendars/${btn.dataset.ctId}/export`, `${btn.dataset.ctName || 'calendar'}.ics`); }
      catch (e) { showToast(e.message, true); }
    });
  });
  container.querySelectorAll('[data-ct-import]').forEach(btn => {
    btn.addEventListener('click', () => triggerIcsImport(parseInt(btn.dataset.ctId)));
  });

  // CalDAV publishing
  container.querySelectorAll('.ct-dav-toggle').forEach(btn => {
    btn.addEventListener('click', async () => {
      const id = parseInt(btn.dataset.ctDavId);
      const newVal = btn.dataset.ctDavOn !== '1';
      const cal = state.localCalendars.find(c => c.id === id);
      if (!cal) return;
      try {
        const updated = await api.put(`/local/calendars/${id}`, { caldav_published: newVal });
        cal.caldav_published = updated.caldav_published;
        cal.caldav_url = updated.caldav_url;
        renderCalendarTable();
      } catch (e) { showToast(e.message, true); }
    });
  });
  container.querySelectorAll('.ct-dav-copy').forEach(btn => {
    btn.addEventListener('click', () => {
      const input = btn.parentElement.querySelector('.ct-dav-url');
      if (!input || !input.value) return;
      navigator.clipboard.writeText(input.value).then(() => showToast(t('caldav_url_copied')));
    });
  });
  container.querySelectorAll('.ct-dav-rotate').forEach(btn => {
    btn.addEventListener('click', async () => {
      const id = parseInt(btn.dataset.ctDavId);
      const cal = state.localCalendars.find(c => c.id === id);
      if (!cal || !confirm(t('caldav_rotate_confirm'))) return;
      try {
        const updated = await api.post(`/local/calendars/${id}/dav-token/rotate`);
        cal.caldav_url = updated.caldav_url;
        renderCalendarTable();
        showToast(t('caldav_token_rotated'));
      } catch (e) { showToast(e.message, true); }
    });
  });

  // Delete
  container.querySelectorAll('[data-ct-del]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const src = btn.dataset.ctDel, id = parseInt(btn.dataset.ctId);
      const msg = src === 'local' ? t('confirm_delete_local_cal') : t('confirm_remove_ical');
      if (!confirm(msg)) return;
      try {
        if (src === 'local') {
          await api.delete(`/local/calendars/${id}`);
          state.localCalendars = state.localCalendars.filter(c => c.id !== id);
        } else {
          await api.delete(`/ical/subscriptions/${id}`);
          state.icalSubscriptions = state.icalSubscriptions.filter(s => s.id !== id);
        }
        renderCalendarTable(); renderCalendarList(); fetchAndRender(true);
      } catch (e) { showToast(e.message, true); }
    });
  });
}

async function loadUsers() {
  try {
    const users = await api.get('/users/');
    const list = document.getElementById('users-list');
    list.innerHTML = users.map(u =>
      `<div class="users-list-item">
        <div>
          <div class="uname">${escHtml(u.username)}</div>
          ${u.email ? `<div class="uemail">${escHtml(u.email)}</div>` : ''}
        </div>
        <div style="display:flex;gap:8px;align-items:center">
          ${u.is_admin ? '<span class="ubadge">Admin</span>' : ''}
          ${u.id !== JSON.parse(localStorage.getItem('user')||'{}').id
            ? `<button class="btn btn-ghost" style="padding:4px 10px;font-size:12px" data-del-user="${u.id}">Löschen</button>`
            : ''}
        </div>
      </div>`
    ).join('');

    list.querySelectorAll('[data-del-user]').forEach(btn => {
      btn.addEventListener('click', async () => {
        if (!confirm(t('confirm_delete_user'))) return;
        try {
          await api.delete(`/users/${btn.dataset.delUser}`);
          loadUsers();
        } catch (e) { showToast(e.message, true); }
      });
    });
  } catch (e) { /* not admin */ }
}

function bindSettingsModal() {
  ['cfg-primary','cfg-accent','cfg-today','cfg-month-divider','cfg-month-label'].forEach(prefix => {
    const preview = document.getElementById(prefix + '-preview');
    const hex = document.getElementById(prefix + '-hex');
    preview.addEventListener('click', async () => {
      const picked = await openColorPicker(preview, hex.value || '#4285f4');
      if (picked) { hex.value = picked.toUpperCase(); preview.style.background = picked; }
    });
    hex.addEventListener('change', () => {
      let val = hex.value.trim();
      if (!val.startsWith('#')) val = '#' + val;
      if (/^#[0-9a-fA-F]{6}$/.test(val)) { hex.value = val.toUpperCase(); preview.style.background = val; }
    });
  });

  // Optional override colours (text / line / background) — empty = use default.
  // Live-apply to the page so the user sees the effect while typing, not only after Save.
  const overrideFieldMap = {
    'cfg-text-color': 'text_color',
    'cfg-line-color': 'line_color',
    'cfg-bg-color':   'bg_color',
  };
  const liveApplyOverride = (prefix, value) => {
    const field = overrideFieldMap[prefix];
    if (!field) return;
    state.settings[field] = value || null;
    applyTheme(state.settings);
  };
  [
    { prefix: 'cfg-text-color', defaultColor: DEFAULT_TEXT_COLOR },
    { prefix: 'cfg-line-color', defaultColor: DEFAULT_LINE_COLOR },
    { prefix: 'cfg-bg-color',   defaultColor: DEFAULT_BG_COLOR },
  ].forEach(({ prefix, defaultColor }) => {
    const preview = document.getElementById(prefix + '-preview');
    const hex = document.getElementById(prefix + '-hex');
    const reset = document.getElementById(prefix + '-reset');
    if (!preview || !hex || !reset) return;

    const normalize = (raw) => {
      let v = (raw || '').trim();
      if (!v) return '';
      if (!v.startsWith('#')) v = '#' + v;
      return /^#[0-9a-fA-F]{6}$/.test(v) ? v.toUpperCase() : null;
    };

    preview.addEventListener('click', async () => {
      const picked = await openColorPicker(preview, hex.value || defaultColor);
      if (picked) {
        hex.value = picked.toUpperCase();
        preview.style.background = picked;
        liveApplyOverride(prefix, picked);
      }
    });

    const onTyped = () => {
      const norm = normalize(hex.value);
      if (norm === '') {
        preview.style.background = defaultColor;
        liveApplyOverride(prefix, null);
      } else if (norm) {
        preview.style.background = norm;
        liveApplyOverride(prefix, norm);
      }
    };
    hex.addEventListener('input', onTyped);
    hex.addEventListener('change', () => {
      const norm = normalize(hex.value);
      if (norm) hex.value = norm;
    });

    reset.addEventListener('click', () => {
      hex.value = '';
      preview.style.background = defaultColor;
      liveApplyOverride(prefix, null);
    });
  });

  // Panel navigation
  document.querySelectorAll('.settings-nav-btn').forEach(btn => {
    btn.addEventListener('click', () => activateSettingsPanel(btn.dataset.panel));
  });

  // Contrast / hour-height selectors
  document.querySelectorAll('.contrast-selector').forEach(sel => {
    sel.addEventListener('click', e => {
      const btn = e.target.closest('.contrast-btn');
      if (!btn) return;
      sel.querySelectorAll('.contrast-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
    });
  });

  document.getElementById('btn-add-user').onclick = () => {
    document.getElementById('add-user-form').classList.toggle('hidden');
  };

  document.getElementById('new-user-save').onclick = async () => {
    const username = document.getElementById('new-username').value.trim();
    const password = document.getElementById('new-password').value;
    const is_admin = document.getElementById('new-is-admin').checked;
    if (!username || !password) { showToast(t('error_username_password'), true); return; }
    try {
      await api.post('/users/', { username, password, is_admin });
      showToast(t("user_created", {name: username}));
      document.getElementById('add-user-form').classList.add('hidden');
      document.getElementById('new-username').value = '';
      document.getElementById('new-password').value = '';
      loadUsers();
    } catch (e) { showToast(e.message, true); }
  };

  // Profile chapter save (name/login/email → /profile, separate from settings).
  const profileSaveBtn = document.getElementById('cfg-profile-save');
  if (profileSaveBtn) profileSaveBtn.onclick = async () => {
    const email = document.getElementById('cfg-email').value.trim();
    const displayName = document.getElementById('cfg-display-name').value.trim();
    const loginName = document.getElementById('cfg-login-name').value.trim();
    const user = JSON.parse(localStorage.getItem('user') || '{}');
    const body = { email: email || null };
    if (displayName) body.display_name = displayName;
    if (loginName && loginName.toLowerCase() !== (user.username || '')) body.username = loginName;
    try {
      const res = await api.put('/profile/', body);
      if (res && res.access_token) localStorage.setItem('token', res.access_token);
      const updated = { ...user };
      if (displayName) updated.display_name = displayName;
      if (body.username) updated.username = body.username.toLowerCase();
      localStorage.setItem('user', JSON.stringify(updated));
      const dd = document.getElementById('dropdown-username');
      if (dd) dd.textContent = updated.display_name || updated.username || 'Benutzer';
      showToast(t('profile_saved'));
    } catch (e) { showToast(e.message, true); }
  };

  document.getElementById('settings-save').onclick = async () => {
    const getActive = (id) => {
      const btn = document.querySelector(`#${id} .contrast-btn.active`);
      return btn ? Number(btn.dataset.val) : null;
    };
    // Optional override colours: empty input → null (use default).
    // Tolerant: accepts both "ff0000" and "#ff0000".
    const colourOrNull = (id) => {
      let v = (document.getElementById(id).value || '').trim();
      if (!v) return null;
      if (!v.startsWith('#')) v = '#' + v;
      return /^#[0-9a-fA-F]{6}$/.test(v) ? v.toUpperCase() : null;
    };
    const settings = {
      default_view:        document.getElementById('cfg-default-view').value,
      week_start_day:      document.getElementById('cfg-week-start').value,
      primary_color:       document.getElementById('cfg-primary-hex').value,
      accent_color:        document.getElementById('cfg-accent-hex').value,
      today_color:         document.getElementById('cfg-today-hex').value,
      month_divider_color: document.getElementById('cfg-month-divider-hex').value,
      month_label_color:   document.getElementById('cfg-month-label-hex').value,
      text_color:          colourOrNull('cfg-text-color-hex'),
      line_color:          colourOrNull('cfg-line-color-hex'),
      bg_color:            colourOrNull('cfg-bg-color-hex'),
      dim_past_events:     document.getElementById('cfg-dim-past').checked,
      default_event_duration_minutes: getActive('cfg-event-duration') || 60,
      hour_height:         getActive('cfg-hour-height')   || 44,
      language:            document.getElementById('cfg-language').value,
      private_event_visibility: document.getElementById('cfg-private-visibility').value,
    };
    const gvVal = document.getElementById('cfg-group-visible-list')?.dataset.selected;
    settings.group_visible_calendar_id = gvVal ? parseInt(gvVal) : null;
    const shareIconPicker = document.getElementById('cfg-share-icon');
    settings.share_calendar_icon = shareIconPicker?.querySelector('.group-icon-opt.on')?.dataset.shareIcon || null;
    try {
      await api.put('/settings/', settings);
      state.settings = { ...state.settings, ...settings };
      state.dimPast  = settings.dim_past_events;
      weekStartDay   = settings.week_start_day;
      setLang(settings.language);
      applyTheme(state.settings);
      showToast(t('settings_saved'));
      closeModal('modal-settings');
      renderCalendarList();
      renderMiniCal();
      fetchAndRender();
    } catch (e) { showToast(e.message, true); }
  };

  // Add-account buttons in calendar panel
  const addBtnMap = {
    'settings-btn-add-local':  openLocalCalModal,
    'settings-btn-add-caldav': openAccountModal,
    'settings-btn-add-ical':   openICalSubModal,
    'settings-btn-add-ha':     openHAAccountModal,
    'settings-btn-add-google': async () => {
      const url = await api.get('/google/auth/url');
      if (url && url.auth_url) window.open(url.auth_url, '_blank');
    },
  };
  Object.entries(addBtnMap).forEach(([id, fn]) => {
    const btn = document.getElementById(id);
    if (btn) btn.addEventListener('click', () => { closeModal('modal-settings'); fn(); });
  });
}

// ── Profile Modal ─────────────────────────────────────────
export function openProfileModal() {
  const user = JSON.parse(localStorage.getItem('user') || '{}');

  // Names & email
  document.getElementById('profile-username').value = user.username || '';
  document.getElementById('profile-display-name-input').value = user.display_name || user.username || '';
  document.getElementById('profile-display-name').textContent = user.display_name || user.username || '';

  // Load fresh profile data
  api.get('/profile/').then(profile => {
    document.getElementById('profile-email').value = profile.email || '';

    // Avatar
    const letter = document.getElementById('profile-avatar-letter');
    const img = document.getElementById('profile-avatar-img');
    const removeBtn = document.getElementById('profile-avatar-remove');
    if (profile.has_avatar) {
      fetchAvatarBlob().then(blobUrl => {
        img.src = blobUrl;
        img.classList.remove('hidden');
        letter.classList.add('hidden');
      }).catch(() => {
        img.classList.add('hidden');
        letter.classList.remove('hidden');
        letter.textContent = (user.username || '?')[0].toUpperCase();
      });
      removeBtn.classList.remove('hidden');
    } else {
      img.classList.add('hidden');
      letter.classList.remove('hidden');
      letter.textContent = (user.username || '?')[0].toUpperCase();
      removeBtn.classList.add('hidden');
    }

    // 2FA status
    document.getElementById('2fa-disabled-section').classList.toggle('hidden', profile.totp_enabled);
    document.getElementById('2fa-setup-section').classList.add('hidden');
    document.getElementById('2fa-enabled-section').classList.toggle('hidden', !profile.totp_enabled);
  }).catch(() => {});

  // Clear password fields
  document.getElementById('profile-pw-current').value = '';
  document.getElementById('profile-pw-new').value = '';
  document.getElementById('profile-pw-confirm').value = '';
  document.getElementById('2fa-disable-pw').value = '';
  document.getElementById('2fa-verify-code').value = '';

  // Load calendars
  renderProfileCalendars();

  openModal('modal-profile');
}

function renderProfileCalendars() {
  const container = document.getElementById('profile-calendars');
  if (!state.accounts.length) {
    container.innerHTML = `<p class="text-muted">${t('no_caldav')}</p>`;
    return;
  }
  const html = state.accounts.map(acc =>
    acc.calendars.map(cal =>
      `<div class="profile-cal-item">
        <div class="profile-cal-dot" style="background:${cal.color}"></div>
        <div>
          <div class="profile-cal-name">${escHtml(cal.name)}</div>
          <div class="profile-cal-account">${escHtml(acc.name)}</div>
        </div>
      </div>`
    ).join('')
  ).join('');
  container.innerHTML = html;
}

function bindProfileModal() {
  // Save profile info (display name, login name, email)
  document.getElementById('profile-save-info').onclick = async () => {
    const email = document.getElementById('profile-email').value.trim();
    const displayName = document.getElementById('profile-display-name-input').value.trim();
    const loginName = document.getElementById('profile-username').value.trim();
    const user = JSON.parse(localStorage.getItem('user') || '{}');
    const body = { email: email || null };
    if (displayName) body.display_name = displayName;
    if (loginName && loginName.toLowerCase() !== (user.username || '')) body.username = loginName;
    try {
      const res = await api.put('/profile/', body);
      // A login-name change returns a fresh token (the old one is now invalid).
      if (res && res.access_token) localStorage.setItem('token', res.access_token);
      // Keep the cached user (menu, "created by", etc.) in sync.
      const updated = { ...user };
      if (displayName) updated.display_name = displayName;
      if (body.username) updated.username = body.username.toLowerCase();
      localStorage.setItem('user', JSON.stringify(updated));
      const dd = document.getElementById('dropdown-username');
      if (dd) dd.textContent = updated.display_name || updated.username || 'Benutzer';
      showToast(t('profile_saved'));
    } catch (e) { showToast(e.message, true); }
  };

  // Avatar upload
  document.getElementById('profile-avatar-upload').onclick = () => {
    document.getElementById('profile-avatar-input').click();
  };

  document.getElementById('profile-avatar-input').onchange = (e) => {
    const file = e.target.files[0];
    if (!file) return;
    e.target.value = '';
    openCropModal(file);
  };

  document.getElementById('profile-avatar-remove').onclick = async () => {
    try {
      await api.delete('/profile/avatar');
      showToast(t('avatar_removed'));
      document.getElementById('profile-avatar-img').classList.add('hidden');
      document.getElementById('profile-avatar-letter').classList.remove('hidden');
      document.getElementById('profile-avatar-remove').classList.add('hidden');
      updateTopbarAvatar(false);
    } catch (e) { showToast(e.message, true); }
  };

  // Password change
  document.getElementById('profile-pw-save').onclick = async () => {
    const current = document.getElementById('profile-pw-current').value;
    const newPw = document.getElementById('profile-pw-new').value;
    const confirm = document.getElementById('profile-pw-confirm').value;
    if (!current || !newPw) { showToast(t('error_fill_all'), true); return; }
    if (newPw !== confirm) { showToast(t('error_pw_mismatch'), true); return; }
    if (newPw.length < 6) { showToast(t('error_pw_length'), true); return; }
    try {
      await api.post('/profile/password', { current_password: current, new_password: newPw });
      showToast(t('password_changed'));
      document.getElementById('profile-pw-current').value = '';
      document.getElementById('profile-pw-new').value = '';
      document.getElementById('profile-pw-confirm').value = '';
    } catch (e) { showToast(e.message, true); }
  };

  // 2FA Setup
  document.getElementById('2fa-setup-btn').onclick = async () => {
    try {
      const res = await api.post('/profile/2fa/setup', {});
      document.getElementById('2fa-qr-img').src = res.qr_code;
      document.getElementById('2fa-secret-code').textContent = res.secret;
      document.getElementById('2fa-disabled-section').classList.add('hidden');
      document.getElementById('2fa-setup-section').classList.remove('hidden');
    } catch (e) { showToast(e.message, true); }
  };

  document.getElementById('2fa-copy-secret').onclick = () => {
    const secret = document.getElementById('2fa-secret-code').textContent;
    navigator.clipboard.writeText(secret).then(() => showToast(t('key_copied')));
  };

  document.getElementById('2fa-enable-btn').onclick = async () => {
    const code = document.getElementById('2fa-verify-code').value.trim();
    if (!code || code.length !== 6) { showToast(t('error_enter_6digit'), true); return; }
    try {
      await api.post('/profile/2fa/enable', { code });
      showToast(t('totp_enabled'));
      document.getElementById('2fa-setup-section').classList.add('hidden');
      document.getElementById('2fa-enabled-section').classList.remove('hidden');
    } catch (e) { showToast(e.message, true); }
  };

  document.getElementById('2fa-cancel-btn').onclick = () => {
    document.getElementById('2fa-setup-section').classList.add('hidden');
    document.getElementById('2fa-disabled-section').classList.remove('hidden');
  };

  document.getElementById('2fa-disable-btn').onclick = async () => {
    const pw = document.getElementById('2fa-disable-pw').value;
    if (!pw) { showToast(t('error_enter_password'), true); return; }
    try {
      await api.post('/profile/2fa/disable', { password: pw });
      showToast(t('totp_disabled'));
      document.getElementById('2fa-enabled-section').classList.add('hidden');
      document.getElementById('2fa-disabled-section').classList.remove('hidden');
      document.getElementById('2fa-disable-pw').value = '';
    } catch (e) { showToast(e.message, true); }
  };
}

function updateTopbarAvatar(hasAvatar) {
  const avatar = document.getElementById('user-avatar');
  if (hasAvatar) {
    fetchAvatarBlob().then(blobUrl => {
      const img = new Image();
      img.onload = () => {
        avatar.innerHTML = '';
        img.style.cssText = 'width:100%;height:100%;object-fit:cover;position:absolute;inset:0';
        avatar.appendChild(img);
      };
      img.src = blobUrl;
    }).catch(() => {
      avatar.innerHTML = '';
      const u = JSON.parse(localStorage.getItem('user')||'{}');
      avatar.textContent = (u.username||'?')[0].toUpperCase();
    });
    // Update localStorage so avatar persists across reloads
    const u = JSON.parse(localStorage.getItem('user')||'{}');
    u.has_avatar = true;
    localStorage.setItem('user', JSON.stringify(u));
  } else {
    avatar.innerHTML = '';
    const user = JSON.parse(localStorage.getItem('user') || '{}');
    avatar.textContent = (user.username || '?')[0].toUpperCase();
    user.has_avatar = false;
    localStorage.setItem('user', JSON.stringify(user));
  }
}

// ── Calendar Color Picker ─────────────────────────────────
async function openCalColorPicker(anchor, calId) {
  // Find current color of the calendar
  let currentColor = '#4285f4';
  for (const acc of state.accounts) {
    for (const cal of acc.calendars) {
      if (cal.id === calId && cal.color) currentColor = cal.color;
    }
  }

  const picked = await openColorPicker(anchor, currentColor);
  if (!picked) return;

  await api.put(`/caldav/calendars/${calId}`, { color: picked });
  for (const acc of state.accounts) {
    for (const cal of acc.calendars) {
      if (cal.id === calId) cal.color = picked;
    }
  }
  applyCalendarColor('caldav', calId, picked);
}

// ── Avatar Crop ──────────────────────────────────────────
let activeCropper = null;

function openCropModal(file) {
  const reader = new FileReader();
  reader.onload = (e) => {
    const cropImg = document.getElementById('crop-image');

    // Destroy previous cropper if any
    if (activeCropper) { activeCropper.destroy(); activeCropper = null; }

    // Reset image src first to force reload
    cropImg.removeAttribute('src');

    openModal('modal-crop');

    // Use requestAnimationFrame to ensure modal is visible before initializing cropper
    requestAnimationFrame(() => {
      cropImg.onload = () => {
        // Small delay to ensure the image is fully rendered in the DOM
        setTimeout(() => {
          if (activeCropper) { activeCropper.destroy(); activeCropper = null; }
          activeCropper = new Cropper(cropImg, {
            aspectRatio: 1,
            viewMode: 1,
            dragMode: 'move',
            autoCropArea: 1,
            cropBoxResizable: true,
            cropBoxMovable: true,
            background: false,
          });
        }, 100);
      };
      cropImg.src = e.target.result;
    });
  };
  reader.readAsDataURL(file);
}

document.getElementById('crop-save').onclick = async () => {
  if (!activeCropper) return;
  const canvas = activeCropper.getCroppedCanvas({
    width: 512,
    height: 512,
    imageSmoothingQuality: 'high',
  });

  canvas.toBlob(async (blob) => {
    const form = new FormData();
    form.append('file', blob, 'avatar.jpg');
    try {
      await api.upload('/profile/avatar', form);
      showToast(t('avatar_uploaded'));
      // Update profile modal avatar
      const img = document.getElementById('profile-avatar-img');
      fetchAvatarBlob().then(blobUrl => {
        img.src = blobUrl;
        img.classList.remove('hidden');
        document.getElementById('profile-avatar-letter').classList.add('hidden');
      });
      document.getElementById('profile-avatar-remove').classList.remove('hidden');
      // Update topbar avatar
      updateTopbarAvatar(true);
      closeModal('modal-crop');
    } catch (err) { showToast(err.message, true); }
  }, 'image/jpeg', 0.9);
};

// Clean up cropper when modal closes
document.getElementById('modal-crop').addEventListener('click', (e) => {
  if (e.target.matches('[data-modal="modal-crop"]') || e.target === document.getElementById('modal-crop')) {
    if (activeCropper) { activeCropper.destroy(); activeCropper = null; }
  }
});

// ── Modal helpers ─────────────────────────────────────────
function openModal(id) {
  document.getElementById(id).classList.remove('hidden');
}
function closeModal(id) {
  document.getElementById(id).classList.add('hidden');
  if (id === 'modal-settings') {
    uiSettingsOpen = false;
    writeUrlState();
  }
}

// Close button bindings (added once)
document.querySelectorAll('.modal-close, [data-modal]').forEach(el => {
  el.addEventListener('click', () => {
    const target = el.dataset.modal || el.closest('.modal-overlay')?.id;
    if (target) closeModal(target);
  });
});
document.querySelectorAll('.modal-overlay').forEach(overlay => {
  overlay.addEventListener('click', e => {
    if (e.target === overlay) closeModal(overlay.id);
  });
});

// ── Toast ─────────────────────────────────────────────────
let toastTimer = null;
export function showToast(msg, isError = false) {
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.className = 'toast' + (isError ? ' error' : '');
  el.classList.remove('hidden');
  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.add('hidden'), 3500);
}

// ── Helpers ───────────────────────────────────────────────
function fmtTime(d) {
  return d.toLocaleTimeString('de', { hour: '2-digit', minute: '2-digit' });
}
function fmtDatetime(d) {
  return d.toLocaleString('de', { weekday:'short', day:'2-digit', month:'short', hour:'2-digit', minute:'2-digit' });
}
function escHtml(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

function buildWritableCalendars(excludeEv) {
  // Determine the event's current calendar to exclude it from copy targets
  let excludeType = null;
  let excludeId = null;
  if (excludeEv) {
    const cid = String(excludeEv.calendar_id);
    if (excludeEv.source === 'local') {
      excludeType = 'local'; excludeId = parseInt(cid.replace('local-', ''));
    } else if (excludeEv.source === 'google') {
      excludeType = 'google'; excludeId = parseInt(cid.replace('google-', ''));
    } else if (excludeEv.source === 'homeassistant') {
      excludeType = 'homeassistant'; excludeId = parseInt(cid.replace('homeassistant-', ''));
    } else if (excludeEv.source === 'caldav' || !excludeEv.source) {
      excludeType = 'caldav'; excludeId = parseInt(cid);
    }
  }
  const skip = (type, id) => excludeType === type && excludeId === id;

  const list = [];
  let idx = 0;
  for (const acc of state.accounts) {
    for (const cal of acc.calendars) {
      if (cal.sidebar_hidden || skip('caldav', cal.id)) continue;
      list.push({ _idx: idx++, id: cal.id, name: `${acc.name} / ${cal.name}`, color: cal.color || '#4285f4', type: 'caldav' });
    }
  }
  for (const cal of state.localCalendars) {
    if (cal.sidebar_hidden || skip('local', cal.id)) continue;
    list.push({ _idx: idx++, id: cal.id, name: cal.name, color: cal.color || '#34a853', type: 'local' });
  }
  for (const acc of state.googleAccounts) {
    for (const cal of acc.calendars) {
      if (cal.sidebar_hidden || skip('google', cal.id)) continue;
      list.push({ _idx: idx++, id: cal.id, name: `${acc.email} / ${cal.name}`, color: cal.color || '#4285f4', type: 'google' });
    }
  }
  for (const acc of state.haAccounts) {
    for (const cal of acc.calendars) {
      if (cal.sidebar_hidden || skip('homeassistant', cal.id)) continue;
      list.push({ _idx: idx++, id: cal.id, name: `${acc.name} / ${cal.name}`, color: cal.color || '#03a9f4', type: 'homeassistant' });
    }
  }
  return list;
}

async function copyEventToCalendar(ev, cal) {
  const { title, allDay, location, description, color } = ev;
  // Normalize to UTC ISO string so the backend doesn't misinterpret bare local times
  const toISO = s => (s && s.length > 10) ? new Date(s).toISOString() : s;
  const start = allDay ? ev.start : toISO(ev.start);
  const end   = allDay ? ev.end   : toISO(ev.end);
  try {
    if (cal.type === 'google') {
      await api.post('/google/events', {
        calendar_db_id: cal.id, title, start, end, allDay,
        location: location || '', description: description || '',
      });
    } else if (cal.type === 'local') {
      await api.post('/local/events', {
        calendar_id: cal.id, title, start, end, allDay,
        location: location || '', description: description || '', color: color || null,
      });
    } else if (cal.type === 'homeassistant') {
      await api.post('/homeassistant/events', {
        calendar_id: cal.id, title, start, end, allDay,
        location: location || '', description: description || '',
      });
    } else {
      await api.post('/caldav/events', {
        calendar_id: cal.id, title, start, end, allDay,
        location: location || '', description: description || '', color: color || null,
      });
    }
    showToast(t('event_copied'));
    fetchAndRender(true);
  } catch (e) { showToast(e.message, true); }
}
