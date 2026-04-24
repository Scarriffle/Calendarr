import { api } from './api.js';
import { applyTheme, isToday, isSameDay, toLocalDatetimeInput, toDateInput, dateKey, dayOfWeek, weekStart } from './utils.js';
import { renderMonth }  from './views/month.js';
import { renderWeek }   from './views/week.js';
import { renderAgenda } from './views/agenda.js';
import { renderQuarter } from './views/quarter.js';
import { openColorPicker } from './color-picker.js';
import { openDatePicker, formatDtDisplay } from './date-picker.js';
import { t, setLang, getLang } from './i18n.js';
import { APP_VERSION } from './version.js';

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
};

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

  setLang(settings.language || 'de');
  applyTheme(settings);
  updateViewButtons();
  document.querySelectorAll('.sidebar-copyright, .impressum-link').forEach(el => {
    el.innerHTML = `© 2026 Scarriffleservices · ${APP_VERSION}`;
  });
  const impVer = document.getElementById('impressum-version');
  if (impVer) impVer.textContent = `Calendarr ${APP_VERSION}`;
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
}

// ── Event cache ───────────────────────────────────────────
const CACHE_BUF      = 56 * 86400000; // initial ±8 weeks
const PREFETCH_EXT   = 56 * 86400000; // extend by 8 weeks when triggered
const PREFETCH_EDGE  = 28 * 86400000; // trigger when within 4 weeks of cache edge

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
async function fetchAndRender(force = false, silent = false) {
  const { start, end } = getViewRange();

  // Cache hit: requested range is fully within what we already have
  if (!force && eventCache.start && eventCache.end &&
      start >= eventCache.start && end <= eventCache.end) {
    state.events = eventCache.events;
    renderView();
    updateTitle();
    renderMiniCal();
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
      date => { state.currentDate = date; state.currentView = 'day'; updateViewButtons(); fetchAndRender(); },
      showEventPopup,
      weekStartDay
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
  // If dimPast is enabled, events are still shown but CSS handles opacity via .past class
  return events;
}

function showLoading() {
  document.getElementById('view-container').innerHTML =
    `<div class="loading-view"><div class="spinner"></div></div>`;
}

function updateTitle() {
  const d = state.currentDate;
  let title = '';
  const M = t('months');
  if (state.currentView === 'month') {
    // Show date range of the rolling 5-week window
    const ws = weekStart(d, weekStartDay);
    const we = new Date(ws); we.setDate(we.getDate() + 34); // last day of 5th week
    const Ms = t('months_short');
    if (ws.getFullYear() !== we.getFullYear()) {
      title = `${Ms[ws.getMonth()]} ${ws.getFullYear()} – ${Ms[we.getMonth()]} ${we.getFullYear()}`;
    } else if (ws.getMonth() !== we.getMonth()) {
      title = `${Ms[ws.getMonth()]} – ${Ms[we.getMonth()]} ${we.getFullYear()}`;
    } else {
      title = `${M[ws.getMonth()]} ${ws.getFullYear()}`;
    }
  } else if (state.currentView === 'week') {
    const mon = weekStart(d, weekStartDay);
    const sun = new Date(mon);
    sun.setDate(mon.getDate() + 6);
    const sameMonth = mon.getMonth() === sun.getMonth();
    title = sameMonth
      ? `${mon.getDate()}. – ${sun.getDate()}. ${M[sun.getMonth()]} ${sun.getFullYear()}`
      : `${mon.getDate()}. ${M[mon.getMonth()]} – ${sun.getDate()}. ${M[sun.getMonth()]} ${sun.getFullYear()}`;
  } else if (state.currentView === 'day') {
    title = `${d.getDate()}. ${M[d.getMonth()]} ${d.getFullYear()}`;
  } else if (state.currentView === 'quarter') {
    const q = Math.floor(d.getMonth() / 3) + 1;
    title = `Q${q} ${d.getFullYear()}`;
  } else {
    title = `${d.getDate()}. ${M[d.getMonth()]} ${d.getFullYear()}`;
  }
  document.getElementById('view-title').textContent = title;
  document.title = `Calendarr - ${title}`;
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

  // Build event date set
  const eventDates = new Set(state.events.map(ev => {
    const s = new Date(ev.start);
    return `${s.getFullYear()}-${s.getMonth()}-${s.getDate()}`;
  }));

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
function renderCalendarList() {
  const container = document.getElementById('cal-list-items');
  let html = '';

  // ── CalDAV accounts ────────────────────────────────────
  if (state.accounts.length) {
    html += state.accounts.map(acc => {
      const visibleCals = acc.calendars.filter(c => !c.sidebar_hidden);
      if (!visibleCals.length) return '';
      return `<div class="cal-account-name">${escHtml(acc.name)}</div>` +
        visibleCals.map(cal =>
          `<div class="cal-item" data-cal-id="${cal.id}" data-source="caldav">
            <input type="checkbox" ${cal.enabled ? 'checked' : ''} data-cal-id="${cal.id}" data-source="caldav" />
            <div class="cal-item-dot" style="background:${cal.color}" data-cal-id="${cal.id}" data-source="caldav" title="${t('change_color')}"></div>
            <span class="cal-item-name" data-source="caldav">${escHtml(cal.name)}</span>
            <button class="icon-btn mini-btn cal-item-remove" data-cal-id="${cal.id}" data-source="caldav" title="${t('hide_cal')}">
              <svg viewBox="0 0 24 24" fill="currentColor" width="14" height="14"><path d="M12 7c2.76 0 5 2.24 5 5 0 .65-.13 1.26-.36 1.83l2.92 2.92c1.51-1.26 2.7-2.89 3.43-4.75-1.73-4.39-6-7.5-11-7.5-1.4 0-2.74.25-3.98.7l2.16 2.16C10.74 7.13 11.35 7 12 7zM2 4.27l2.28 2.28.46.46C3.08 8.3 1.78 10.02 1 12c1.73 4.39 6 7.5 11 7.5 1.55 0 3.03-.3 4.38-.84l.42.42L19.73 22 21 20.73 3.27 3 2 4.27zM7.53 9.8l1.55 1.55c-.05.21-.08.43-.08.65 0 1.66 1.34 3 3 3 .22 0 .44-.03.65-.08l1.55 1.55c-.67.33-1.41.53-2.2.53-2.76 0-5-2.24-5-5 0-.79.2-1.53.53-2.2zm4.31-.78l3.15 3.15.02-.16c0-1.66-1.34-3-3-3l-.17.01z"/></svg>
            </button>
          </div>`
        ).join('');
    }).join('');
  }

  // ── Local calendars ────────────────────────────────────
  if (state.localCalendars.length) {
    html += `<div class="cal-account-name">${t('cal_local')}</div>`;
    html += state.localCalendars.map(cal =>
      `<div class="cal-item" data-cal-id="${cal.id}" data-source="local">
        <input type="checkbox" ${cal.enabled ? 'checked' : ''} data-cal-id="${cal.id}" data-source="local" />
        <div class="cal-item-dot" style="background:${cal.color}" data-cal-id="${cal.id}" data-source="local" title="${t('change_color')}"></div>
        <span class="cal-item-name" data-source="local">${escHtml(cal.name)}</span>
        <button class="icon-btn mini-btn cal-item-remove" data-cal-id="${cal.id}" data-source="local" title="${t('remove_cal')}">
          <svg viewBox="0 0 24 24" fill="currentColor" width="14" height="14"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>
        </button>
      </div>`
    ).join('');
  }

  // ── iCal subscriptions ─────────────────────────────────
  if (state.icalSubscriptions.length) {
    html += `<div class="cal-account-name">${t('cal_ical')}</div>`;
    html += state.icalSubscriptions.map(sub =>
      `<div class="cal-item" data-sub-id="${sub.id}" data-source="ical">
        <input type="checkbox" ${sub.enabled ? 'checked' : ''} data-sub-id="${sub.id}" data-source="ical" />
        <div class="cal-item-dot" style="background:${sub.color}" data-sub-id="${sub.id}" data-source="ical" title="${t('change_color')}"></div>
        <span class="cal-item-name" data-source="ical">${escHtml(sub.name)}</span>
        <button class="icon-btn mini-btn cal-item-remove" data-sub-id="${sub.id}" data-source="ical" title="${t('remove_ical_sub')}">
          <svg viewBox="0 0 24 24" fill="currentColor" width="14" height="14"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>
        </button>
      </div>`
    ).join('');
  }

  // ── Google accounts ───────────────────────────────────
  if (state.googleAccounts.length) {
    html += state.googleAccounts.map(acc => {
      const visibleCals = acc.calendars.filter(c => !c.sidebar_hidden);
      if (!visibleCals.length) return `<div class="cal-account-name">${escHtml(acc.email)}</div>`;
      return `<div class="cal-account-name">${escHtml(acc.email)}</div>` +
        visibleCals.map(cal =>
          `<div class="cal-item" data-cal-id="${cal.id}" data-source="google">
            <input type="checkbox" ${cal.enabled ? 'checked' : ''} data-cal-id="${cal.id}" data-source="google" />
            <div class="cal-item-dot" style="background:${cal.color || '#4285f4'}" data-cal-id="${cal.id}" data-source="google" title="${t('change_color')}"></div>
            <span class="cal-item-name" data-source="google">${escHtml(cal.name)}</span>
            <button class="icon-btn mini-btn cal-item-remove" data-cal-id="${cal.id}" data-source="google" title="${t('hide_cal')}">
              <svg viewBox="0 0 24 24" fill="currentColor" width="14" height="14"><path d="M12 7c2.76 0 5 2.24 5 5 0 .65-.13 1.26-.36 1.83l2.92 2.92c1.51-1.26 2.7-2.89 3.43-4.75-1.73-4.39-6-7.5-11-7.5-1.4 0-2.74.25-3.98.7l2.16 2.16C10.74 7.13 11.35 7 12 7zM2 4.27l2.28 2.28.46.46C3.08 8.3 1.78 10.02 1 12c1.73 4.39 6 7.5 11 7.5 1.55 0 3.03-.3 4.38-.84l.42.42L19.73 22 21 20.73 3.27 3 2 4.27zM7.53 9.8l1.55 1.55c-.05.21-.08.43-.08.65 0 1.66 1.34 3 3 3 .22 0 .44-.03.65-.08l1.55 1.55c-.67.33-1.41.53-2.2.53-2.76 0-5-2.24-5-5 0-.79.2-1.53.53-2.2zm4.31-.78l3.15 3.15.02-.16c0-1.66-1.34-3-3-3l-.17.01z"/></svg>
            </button>
          </div>`
        ).join('');
    }).join('');
  }

  // ── Home Assistant accounts ───────────────────────────
  if (state.haAccounts.length) {
    html += state.haAccounts.map(acc => {
      const visibleCals = acc.calendars.filter(c => !c.sidebar_hidden);
      if (!visibleCals.length) return `<div class="cal-account-name">${escHtml(acc.name)}</div>`;
      return `<div class="cal-account-name">${escHtml(acc.name)}</div>` +
        visibleCals.map(cal =>
          `<div class="cal-item" data-cal-id="${cal.id}" data-source="homeassistant">
            <input type="checkbox" ${cal.enabled ? 'checked' : ''} data-cal-id="${cal.id}" data-source="homeassistant" />
            <div class="cal-item-dot" style="background:${cal.color || '#03a9f4'}" data-cal-id="${cal.id}" data-source="homeassistant" title="${t('change_color')}"></div>
            <span class="cal-item-name" data-source="homeassistant">${escHtml(cal.name)}</span>
            <button class="icon-btn mini-btn cal-item-remove" data-cal-id="${cal.id}" data-source="homeassistant" title="${t('hide_cal')}">
              <svg viewBox="0 0 24 24" fill="currentColor" width="14" height="14"><path d="M12 7c2.76 0 5 2.24 5 5 0 .65-.13 1.26-.36 1.83l2.92 2.92c1.51-1.26 2.7-2.89 3.43-4.75-1.73-4.39-6-7.5-11-7.5-1.4 0-2.74.25-3.98.7l2.16 2.16C10.74 7.13 11.35 7 12 7zM2 4.27l2.28 2.28.46.46C3.08 8.3 1.78 10.02 1 12c1.73 4.39 6 7.5 11 7.5 1.55 0 3.03-.3 4.38-.84l.42.42L19.73 22 21 20.73 3.27 3 2 4.27zM7.53 9.8l1.55 1.55c-.05.21-.08.43-.08.65 0 1.66 1.34 3 3 3 .22 0 .44-.03.65-.08l1.55 1.55c-.67.33-1.41.53-2.2.53-2.76 0-5-2.24-5-5 0-.79.2-1.53.53-2.2zm4.31-.78l3.15 3.15.02-.16c0-1.66-1.34-3-3-3l-.17.01z"/></svg>
            </button>
          </div>`
        ).join('');
    }).join('');
  }

  if (!html) {
    container.innerHTML = `<div style="padding:8px 16px;font-size:12px;color:var(--text-3)">${t('error_no_calendars')}</div>`;
    return;
  }

  container.innerHTML = html;

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
        await api.put(`/local/calendars/${calId}`, { enabled: cb.checked });
        const cal = state.localCalendars.find(c => c.id === calId);
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
  document.getElementById('btn-create-event').onclick = () => openNewEventModal(new Date());

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
  };

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

// ── Event Popup ───────────────────────────────────────────
function showEventPopup(ev, anchor) {
  const popup = document.getElementById('popup-event');
  document.getElementById('popup-copy-menu').classList.add('hidden');
  popup.classList.remove('hidden');

  const color = ev.color || ev.calendarColor || '#4285f4';
  document.getElementById('popup-color-dot').style.background = color;
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
  document.getElementById('popup-location').style.display = ev.location ? '' : 'none';
  document.getElementById('popup-description').textContent = ev.description || '';
  document.getElementById('popup-description').style.display = ev.description ? '' : 'none';
  document.getElementById('popup-calendar').textContent = ev.calendar_name || '';

  // Position near anchor
  const rect = anchor.getBoundingClientRect();
  const pw = 300, ph = 200;
  let left = rect.right + 8;
  let top  = rect.top;
  if (left + pw > window.innerWidth) left = rect.left - pw - 8;
  if (top + ph > window.innerHeight) top = window.innerHeight - ph - 16;
  popup.style.left = Math.max(8, left) + 'px';
  popup.style.top  = Math.max(8, top)  + 'px';

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
    menu.innerHTML = `<div class="popup-copy-label">${t('copy_to_calendar')}</div>` +
      targets.map(c =>
        `<div class="popup-copy-item" data-cal-idx="${c._idx}">
          <span class="popup-copy-dot" style="background:${c.color}"></span>
          <span>${escHtml(c.name)}</span>
        </div>`
      ).join('');
    menu.classList.remove('hidden');
    menu.querySelectorAll('.popup-copy-item').forEach(el => {
      el.addEventListener('click', async ev2 => {
        ev2.stopPropagation();
        menu.classList.add('hidden');
        popup.classList.add('hidden');
        const cal = targets[parseInt(el.dataset.calIdx)];
        await copyEventToCalendar(ev, cal);
      });
    });
  };

  document.getElementById('popup-delete').onclick = async () => {
    if (!confirm(t("confirm_delete_event", {title: ev.title}))) return;
    popup.classList.add('hidden');
    try {
      if (ev.source === 'google') {
        const accId = ev.calendar_id.replace('google-', '');
        await api.delete(`/google/events/${accId}/${encodeURIComponent(ev.id)}`);
      } else if (ev.source === 'local') {
        await api.delete(`/local/events/${encodeURIComponent(ev.id)}`);
      } else if (ev.source === 'ical') {
        const subId = ev.calendar_id.replace('ical-', '');
        await api.delete(`/ical/events/${subId}/${encodeURIComponent(ev.id)}`);
      } else {
        await api.delete(`/caldav/events/${encodeURIComponent(ev.id)}?event_url=${encodeURIComponent(ev.url)}`);
      }
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
  const sel = document.getElementById('ev-calendar');
  sel.innerHTML = '';
  // CalDAV calendars
  state.accounts.forEach(acc => {
    acc.calendars.filter(c => c.enabled).forEach(cal => {
      const opt = document.createElement('option');
      opt.value = cal.id;
      opt.textContent = `${acc.name} / ${cal.name}`;
      if (cal.id === selectedId) opt.selected = true;
      sel.appendChild(opt);
    });
  });
  // Local calendars
  state.localCalendars.filter(c => c.enabled).forEach(cal => {
    const opt = document.createElement('option');
    opt.value = `local-${cal.id}`;
    opt.textContent = cal.name;
    if (`local-${cal.id}` === selectedId) opt.selected = true;
    sel.appendChild(opt);
  });
  // iCal subscriptions are read-only, not shown here
  // Google calendars (read/write)
  state.googleAccounts.forEach(acc => {
    acc.calendars.filter(c => c.enabled).forEach(cal => {
      const opt = document.createElement('option');
      opt.value = `google-${cal.id}`;
      opt.textContent = `${acc.email} / ${cal.name}`;
      if (`google-${cal.id}` === selectedId) opt.selected = true;
      sel.appendChild(opt);
    });
  });
}

// ── Date field helpers ────────────────────────────────────
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
  const end   = new Date(date);
  end.setHours(end.getHours() + 1);
  setDtValue('ev-start',      toLocalDatetimeInput(start), 'datetime');
  setDtValue('ev-end',        toLocalDatetimeInput(end),   'datetime');
  setDtValue('ev-start-date', toDateInput(start),          'date');
  setDtValue('ev-end-date',   toDateInput(start),          'date');

  toggleAlldayFields(false);
  populateCalendarSelect(null);
  resetColorPicker('');
  document.getElementById('ev-delete').classList.add('hidden');
  openModal('modal-event');
}

function openEditEventModal(ev) {
  state.editingEvent = ev;
  state.selectedEventColor = ev.color || '';

  document.getElementById('modal-event-title-label').textContent = 'Termin bearbeiten';
  document.getElementById('ev-title').value       = ev.title;
  document.getElementById('ev-location').value    = ev.location || '';
  document.getElementById('ev-description').value = ev.description || '';
  document.getElementById('ev-allday').checked    = ev.allDay;

  if (ev.allDay) {
    setDtValue('ev-start-date', ev.start.slice(0, 10), 'date');
    setDtValue('ev-end-date',   ev.end.slice(0, 10),   'date');
    toggleAlldayFields(true);
  } else {
    const s = new Date(ev.start);
    const e = new Date(ev.end);
    setDtValue('ev-start', toLocalDatetimeInput(s), 'datetime');
    setDtValue('ev-end',   toLocalDatetimeInput(e), 'datetime');
    toggleAlldayFields(false);
  }

  populateCalendarSelect(ev.calendar_id);
  resetColorPicker(ev.color || '');
  document.getElementById('ev-delete').classList.remove('hidden');
  openModal('modal-event');
}

function toggleAlldayFields(allDay) {
  document.getElementById('ev-time-row').style.display = allDay ? 'none' : '';
  document.getElementById('ev-date-row').style.display = allDay ? '' : 'none';
}

function resetColorPicker(color) {
  state.selectedEventColor = color;
  const hex = document.getElementById('ev-color-hex');
  const preview = document.getElementById('ev-color-preview');
  hex.value = color ? color.toUpperCase() : '';
  preview.style.background = color || 'var(--primary)';
}

function bindEventModal() {
  document.getElementById('ev-allday').addEventListener('change', e => {
    toggleAlldayFields(e.target.checked);
  });

  // Date/time pickers
  [
    { displayId: 'ev-start-display',      inputId: 'ev-start',      mode: 'datetime' },
    { displayId: 'ev-end-display',        inputId: 'ev-end',        mode: 'datetime' },
    { displayId: 'ev-start-date-display', inputId: 'ev-start-date', mode: 'date'     },
    { displayId: 'ev-end-date-display',   inputId: 'ev-end-date',   mode: 'date'     },
  ].forEach(({ displayId, inputId, mode }) => {
    const disp = document.getElementById(displayId);
    if (!disp) return;
    const open = async () => {
      const current = document.getElementById(inputId)?.value || '';
      const result  = await openDatePicker(disp, current, mode);
      if (result !== null) setDtValue(inputId, result, mode);
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

  document.getElementById('ev-save').onclick = async () => {
    const title = document.getElementById('ev-title').value.trim();
    if (!title) { showToast(t('error_enter_title'), true); return; }

    const allDay  = document.getElementById('ev-allday').checked;
    const calVal  = document.getElementById('ev-calendar').value;
    const isLocal = calVal.startsWith('local-');
    const isGoogle = calVal.startsWith('google-');
    const loc     = document.getElementById('ev-location').value.trim();
    const desc    = document.getElementById('ev-description').value.trim();
    const color   = state.selectedEventColor;

    let start, end;
    if (allDay) {
      start = document.getElementById('ev-start-date').value;
      end   = document.getElementById('ev-end-date').value;
      if (!start) { showToast(t('error_enter_date'), true); return; }
      if (!end || end < start) end = start;
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
            { title, start, end, allDay, location: loc, description: desc, color: color || null }
          );
        } else if (ev.source === 'ical') {
          const subId = ev.calendar_id.replace('ical-', '');
          await api.put(`/ical/events/${subId}/${encodeURIComponent(ev.id)}`,
            { title, start, end, allDay, location: loc, description: desc, color: color || null }
          );
        } else {
          await api.put(
            `/caldav/events/${encodeURIComponent(ev.id)}?event_url=${encodeURIComponent(ev.url)}`,
            { title, start, end, allDay, location: loc, description: desc, color: color || null }
          );
        }
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
        });
        showToast(t('event_created'));
      } else {
        const calId = parseInt(calVal);
        await api.post('/caldav/events', {
          calendar_id: calId, title, start, end, allDay,
          location: loc, description: desc, color: color || null,
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
    if (!confirm(t("confirm_delete_event", {title: ev.title}))) return;
    try {
      if (ev.source === 'google') {
        const accId = ev.calendar_id.replace('google-', '');
        await api.delete(`/google/events/${accId}/${encodeURIComponent(ev.id)}`);
      } else if (ev.source === 'local') {
        await api.delete(`/local/events/${encodeURIComponent(ev.id)}`);
      } else if (ev.source === 'ical') {
        const subId = ev.calendar_id.replace('ical-', '');
        await api.delete(`/ical/events/${subId}/${encodeURIComponent(ev.id)}`);
      } else {
        await api.delete(`/caldav/events/${encodeURIComponent(ev.id)}?event_url=${encodeURIComponent(ev.url)}`);
      }
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
  document.getElementById('ha-account-username').value = '';
  document.getElementById('ha-account-userpass').value = '';
  document.getElementById('ha-account-error').classList.add('hidden');
  // Reset to token method
  document.getElementById('ha-auth-token').checked = true;
  document.getElementById('ha-token-group').classList.remove('hidden');
  document.getElementById('ha-credentials-group').classList.add('hidden');
  openModal('modal-ha-account');
}

function bindHAAccountModal() {
  // Toggle auth method fields
  document.querySelectorAll('[name="ha-auth-method"]').forEach(r => {
    r.addEventListener('change', () => {
      const isPw = document.getElementById('ha-auth-password').checked;
      document.getElementById('ha-token-group').classList.toggle('hidden', isPw);
      document.getElementById('ha-credentials-group').classList.toggle('hidden', !isPw);
    });
  });

  document.getElementById('ha-account-save').onclick = async () => {
    const name = document.getElementById('ha-account-name').value.trim();
    const url = document.getElementById('ha-account-url').value.trim();
    const isPw = document.getElementById('ha-auth-password').checked;
    const errEl = document.getElementById('ha-account-error');

    if (!name || !url) {
      errEl.textContent = 'Bitte Name und URL ausfüllen';
      errEl.classList.remove('hidden');
      return;
    }

    const body = { name, url };
    if (isPw) {
      const username = document.getElementById('ha-account-username').value.trim();
      const password = document.getElementById('ha-account-userpass').value.trim();
      if (!username || !password) {
        errEl.textContent = 'Bitte Benutzername und Passwort ausfüllen';
        errEl.classList.remove('hidden');
        return;
      }
      body.username = username;
      body.password = password;
    } else {
      const token = document.getElementById('ha-account-token').value.trim();
      if (!token) {
        errEl.textContent = 'Bitte Access Token ausfüllen';
        errEl.classList.remove('hidden');
        return;
      }
      body.token = token;
    }
    errEl.classList.add('hidden');

    const saveBtn = document.getElementById('ha-account-save');
    saveBtn.disabled = true;
    saveBtn.textContent = 'Verbinde…';
    try {
      const account = await api.post('/homeassistant/accounts', body);
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

// ── Settings Modal ────────────────────────────────────────
function openSettingsModal() {
  const s = state.settings;
  document.getElementById('cfg-default-view').value  = s.default_view   || 'month';
  document.getElementById('cfg-week-start').value    = s.week_start_day || 'monday';
  const colors = [
    { id: 'cfg-primary', val: s.primary_color || '#4285f4' },
    { id: 'cfg-accent',  val: s.accent_color  || '#ea4335' },
    { id: 'cfg-today',   val: s.today_color   || '#4285f4' },
  ];
  colors.forEach(({ id, val }) => {
    document.getElementById(id + '-hex').value = val.toUpperCase();
    document.getElementById(id + '-preview').style.background = val;
  });
  document.getElementById('cfg-dim-past').checked = !!s.dim_past_events;
  document.getElementById('cfg-language').value = getLang();

  // Set active contrast/hour-height buttons
  [
    { id: 'cfg-text-contrast', val: s.text_contrast || 3 },
    { id: 'cfg-line-contrast', val: s.line_contrast || 3 },
    { id: 'cfg-hour-height',   val: s.hour_height   || 60 },
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

  // Activate first panel
  const firstBtn = document.querySelector('.settings-nav-btn:not(.hidden)');
  if (firstBtn) activateSettingsPanel(firstBtn.dataset.panel);

  // Render all accounts and hidden calendars
  renderAllAccounts();
  renderHiddenCalendars();

  openModal('modal-settings');
}

function activateSettingsPanel(panel) {
  document.querySelectorAll('.settings-nav-btn').forEach(b => b.classList.toggle('active', b.dataset.panel === panel));
  document.querySelectorAll('.settings-panel').forEach(p => p.classList.toggle('active', p.id === 'settings-panel-' + panel));
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
      localList.innerHTML = state.localCalendars.map(cal =>
        `<div class="accounts-row">
          <div style="display:flex;align-items:center;gap:8px;min-width:0">
            <span class="accounts-local-dot" style="background:${cal.color || '#34a853'}"></span>
            <span class="accounts-row-name">${escHtml(cal.name)}</span>
          </div>
        </div>`
      ).join('');
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

  // Google accounts section — delegate to existing function
  renderGoogleAccounts();

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
}

function renderHiddenCalendars() {
  const list = document.getElementById('hidden-cals-list');
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
  ['cfg-primary','cfg-accent','cfg-today'].forEach(prefix => {
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

  document.getElementById('settings-save').onclick = async () => {
    const getActive = (id) => {
      const btn = document.querySelector(`#${id} .contrast-btn.active`);
      return btn ? Number(btn.dataset.val) : null;
    };
    const settings = {
      default_view:    document.getElementById('cfg-default-view').value,
      week_start_day:  document.getElementById('cfg-week-start').value,
      primary_color:   document.getElementById('cfg-primary-hex').value,
      accent_color:    document.getElementById('cfg-accent-hex').value,
      today_color:     document.getElementById('cfg-today-hex').value,
      dim_past_events: document.getElementById('cfg-dim-past').checked,
      text_contrast:   getActive('cfg-text-contrast') || 3,
      line_contrast:   getActive('cfg-line-contrast') || 3,
      hour_height:     getActive('cfg-hour-height')   || 44,
      language:        document.getElementById('cfg-language').value,
    };
    try {
      await api.put('/settings/', settings);
      state.settings = { ...state.settings, ...settings };
      state.dimPast  = settings.dim_past_events;
      weekStartDay   = settings.week_start_day;
      setLang(settings.language);
      applyTheme(state.settings);
      showToast(t('settings_saved'));
      closeModal('modal-settings');
      renderMiniCal();
      fetchAndRender();
    } catch (e) { showToast(e.message, true); }
  };
}

// ── Profile Modal ─────────────────────────────────────────
export function openProfileModal() {
  const user = JSON.parse(localStorage.getItem('user') || '{}');

  // Username & email
  document.getElementById('profile-username').value = user.username || '';
  document.getElementById('profile-display-name').textContent = user.username || '';

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
  // Save profile info (email)
  document.getElementById('profile-save-info').onclick = async () => {
    const email = document.getElementById('profile-email').value.trim();
    try {
      await api.put('/profile/', { email: email || null });
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

function buildWritableCalendars(_excludeEv) {
  const list = [];
  let idx = 0;
  for (const acc of state.accounts) {
    for (const cal of acc.calendars) {
      if (cal.sidebar_hidden) continue;
      list.push({ _idx: idx++, id: cal.id, name: `${acc.name} / ${cal.name}`, color: cal.color || '#4285f4', type: 'caldav' });
    }
  }
  for (const cal of state.localCalendars) {
    list.push({ _idx: idx++, id: cal.id, name: cal.name, color: cal.color || '#34a853', type: 'local' });
  }
  for (const acc of state.googleAccounts) {
    for (const cal of acc.calendars) {
      if (cal.sidebar_hidden) continue;
      list.push({ _idx: idx++, id: cal.id, name: `${acc.email} / ${cal.name}`, color: cal.color || '#4285f4', type: 'google' });
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
