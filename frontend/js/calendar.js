import { api } from './api.js';
import { applyTheme, isToday, isSameDay, toLocalDatetimeInput, toDateInput, dateKey, dayOfWeek, weekStart } from './utils.js';
import { renderMonth }  from './views/month.js';
import { renderWeek }   from './views/week.js';
import { renderAgenda } from './views/agenda.js';
import { openColorPicker } from './color-picker.js';

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

const MONTHS = ['Januar','Februar','März','April','Mai','Juni',
                'Juli','August','September','Oktober','November','Dezember'];

let state = {
  currentDate: new Date(),
  currentView: 'month',
  events: [],
  accounts: [],
  settings: {},
  dimPast: false,
  editingEvent: null,      // null = new event
  selectedEventColor: '',  // '' = use calendar color
};

// ── Public init ───────────────────────────────────────────
export async function initCalendar() {
  const [settings, accounts] = await Promise.all([
    api.get('/settings/'),
    api.get('/caldav/accounts'),
  ]);

  state.settings = settings;
  state.accounts = accounts;
  state.currentView = settings.default_view || 'month';
  state.dimPast = settings.dim_past_events;
  weekStartDay = settings.week_start_day || 'monday';

  applyTheme(settings);
  updateViewButtons();
  renderCalendarList();
  renderMiniCal();
  await fetchAndRender();
  bindTopbar();
  bindSidebar();
  bindEventModal();
  bindAccountModal();
  bindSettingsModal();
  bindProfileModal();
}

// ── Data fetching ─────────────────────────────────────────
async function fetchAndRender() {
  const { start, end } = getViewRange();
  showLoading();
  try {
    const events = await api.get(`/caldav/events?start=${start.toISOString()}&end=${end.toISOString()}`);
    state.events = events;
  } catch (e) {
    showToast('Fehler beim Laden der Termine: ' + e.message, true);
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
    start = new Date(d.getFullYear(), d.getMonth(), 1);
    start.setDate(start.getDate() - dayOfWeek(start, weekStartDay) - 1);
    end   = new Date(d.getFullYear(), d.getMonth() + 1, 0);
    end.setDate(end.getDate() + (6 - dayOfWeek(end, weekStartDay)) + 1);
  } else if (state.currentView === 'week') {
    start = weekStart(d, weekStartDay);
    end = new Date(start);
    end.setDate(start.getDate() + 7);
  } else if (state.currentView === 'day') {
    start = new Date(d);
    start.setHours(0, 0, 0, 0);
    end = new Date(start);
    end.setDate(end.getDate() + 1);
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
      weekStartDay
    );
  } else if (state.currentView === 'day') {
    renderWeek(container, state.currentDate, evs,
      (date, switchDay) => { if (!switchDay) openNewEventModal(date); },
      showEventPopup,
      true,
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
  if (state.currentView === 'month') {
    title = `${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
  } else if (state.currentView === 'week') {
    const mon = weekStart(d, weekStartDay);
    const sun = new Date(mon);
    sun.setDate(mon.getDate() + 6);
    const sameMonth = mon.getMonth() === sun.getMonth();
    title = sameMonth
      ? `${mon.getDate()}. – ${sun.getDate()}. ${MONTHS[sun.getMonth()]} ${sun.getFullYear()}`
      : `${mon.getDate()}. ${MONTHS[mon.getMonth()]} – ${sun.getDate()}. ${MONTHS[sun.getMonth()]} ${sun.getFullYear()}`;
  } else if (state.currentView === 'day') {
    title = `${d.getDate()}. ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
  } else {
    title = `Ab ${d.getDate()}. ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
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
    `${MONTHS[miniD.getMonth()]} ${miniD.getFullYear()}`;

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
  if (!state.accounts.length) {
    container.innerHTML = `<div style="padding:8px 16px;font-size:12px;color:var(--text-3)">Kein CalDAV-Konto</div>`;
    return;
  }

  const html = state.accounts.map(acc =>
    `<div class="cal-account-name">${escHtml(acc.name)}</div>` +
    acc.calendars.map(cal =>
      `<div class="cal-item" data-cal-id="${cal.id}">
        <input type="checkbox" ${cal.enabled ? 'checked' : ''} data-cal-id="${cal.id}" />
        <div class="cal-item-dot" style="background:${cal.color}" data-cal-id="${cal.id}" title="Farbe ändern"></div>
        <span class="cal-item-name">${escHtml(cal.name)}</span>
        <button class="icon-btn mini-btn cal-item-remove" data-acc-id="${acc.id}" title="Konto entfernen">
          <svg viewBox="0 0 24 24" fill="currentColor" width="14" height="14"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>
        </button>
      </div>`
    ).join('')
  ).join('');

  container.innerHTML = html;

  container.querySelectorAll('input[type=checkbox]').forEach(cb => {
    cb.addEventListener('change', async () => {
      const calId = parseInt(cb.dataset.calId);
      await api.put(`/caldav/calendars/${calId}`, { enabled: cb.checked });
      // Update local state
      for (const acc of state.accounts) {
        for (const cal of acc.calendars) {
          if (cal.id === calId) cal.enabled = cb.checked;
        }
      }
      fetchAndRender();
    });
  });

  container.querySelectorAll('.cal-item-dot').forEach(dot => {
    dot.addEventListener('click', e => {
      e.stopPropagation();
      const calId = parseInt(dot.dataset.calId);
      openCalColorPicker(dot, calId);
    });
  });

  container.querySelectorAll('.cal-item-name').forEach(nameEl => {
    nameEl.addEventListener('dblclick', e => {
      e.stopPropagation();
      const calId = parseInt(nameEl.closest('.cal-item').dataset.calId);
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
          await api.put(`/caldav/calendars/${calId}`, { name: newName });
          for (const acc of state.accounts) {
            for (const cal of acc.calendars) {
              if (cal.id === calId) cal.name = newName;
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

  container.querySelectorAll('.cal-item-remove').forEach(btn => {
    btn.addEventListener('click', async e => {
      e.stopPropagation();
      if (!confirm('CalDAV-Konto wirklich entfernen?')) return;
      const accId = parseInt(btn.dataset.accId);
      await api.delete(`/caldav/accounts/${accId}`);
      state.accounts = state.accounts.filter(a => a.id !== accId);
      renderCalendarList();
      fetchAndRender();
    });
  });
}

// ── Navigation ────────────────────────────────────────────
function navigate(dir) {
  const d = state.currentDate;
  if (state.currentView === 'month') {
    state.currentDate = new Date(d.getFullYear(), d.getMonth() + dir, 1);
  } else if (state.currentView === 'week') {
    state.currentDate = new Date(d);
    state.currentDate.setDate(d.getDate() + dir * 7);
  } else if (state.currentView === 'day') {
    state.currentDate = new Date(d);
    state.currentDate.setDate(d.getDate() + dir);
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
}

// ── Sidebar toggle ────────────────────────────────────────
function bindSidebar() {
  document.getElementById('sidebar-toggle').onclick = () => {
    document.getElementById('sidebar').classList.toggle('collapsed');
  };
  document.getElementById('btn-add-account').onclick = openAccountModal;
}

// ── Event Popup ───────────────────────────────────────────
function showEventPopup(ev, anchor) {
  const popup = document.getElementById('popup-event');
  popup.classList.remove('hidden');

  const color = ev.color || ev.calendarColor || '#4285f4';
  document.getElementById('popup-color-dot').style.background = color;
  document.getElementById('popup-title').textContent = ev.title;

  // Time
  if (ev.allDay) {
    document.getElementById('popup-time').textContent = 'Ganztägig';
  } else {
    const s = new Date(ev.start);
    const e = new Date(ev.end);
    document.getElementById('popup-time').textContent =
      `${fmtDatetime(s)} – ${fmtTime(e)}`;
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
  document.getElementById('popup-delete').onclick = async () => {
    if (!confirm(`"${ev.title}" wirklich löschen?`)) return;
    popup.classList.add('hidden');
    try {
      await api.delete(`/caldav/events/${encodeURIComponent(ev.id)}?event_url=${encodeURIComponent(ev.url)}`);
      showToast('Termin gelöscht');
      fetchAndRender();
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
  state.accounts.forEach(acc => {
    acc.calendars.filter(c => c.enabled).forEach(cal => {
      const opt = document.createElement('option');
      opt.value = cal.id;
      opt.textContent = `${acc.name} / ${cal.name}`;
      if (cal.id === selectedId) opt.selected = true;
      sel.appendChild(opt);
    });
  });
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
  document.getElementById('ev-start').value = toLocalDatetimeInput(start);
  document.getElementById('ev-end').value   = toLocalDatetimeInput(end);
  document.getElementById('ev-start-date').value = toDateInput(start);
  document.getElementById('ev-end-date').value   = toDateInput(start);

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
    document.getElementById('ev-start-date').value = ev.start.slice(0, 10);
    document.getElementById('ev-end-date').value   = ev.end.slice(0, 10);
    toggleAlldayFields(true);
  } else {
    const s = new Date(ev.start);
    const e = new Date(ev.end);
    document.getElementById('ev-start').value = toLocalDatetimeInput(s);
    document.getElementById('ev-end').value   = toLocalDatetimeInput(e);
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
    if (!title) { showToast('Bitte Titel eingeben', true); return; }

    const allDay  = document.getElementById('ev-allday').checked;
    const calId   = parseInt(document.getElementById('ev-calendar').value);
    const loc     = document.getElementById('ev-location').value.trim();
    const desc    = document.getElementById('ev-description').value.trim();
    const color   = state.selectedEventColor;

    let start, end;
    if (allDay) {
      start = document.getElementById('ev-start-date').value;
      end   = document.getElementById('ev-end-date').value;
      if (!start) { showToast('Bitte Datum eingeben', true); return; }
      if (!end || end < start) end = start;
    } else {
      const sv = document.getElementById('ev-start').value;
      const ev2 = document.getElementById('ev-end').value;
      if (!sv) { showToast('Bitte Start-Zeit eingeben', true); return; }
      start = new Date(sv).toISOString();
      end   = ev2 ? new Date(ev2).toISOString() : new Date(new Date(sv).getTime() + 3600000).toISOString();
    }

    try {
      if (state.editingEvent) {
        await api.put(
          `/caldav/events/${encodeURIComponent(state.editingEvent.id)}?event_url=${encodeURIComponent(state.editingEvent.url)}`,
          { title, start, end, allDay, location: loc, description: desc, color: color || null }
        );
        showToast('Termin aktualisiert');
      } else {
        await api.post('/caldav/events', {
          calendar_id: calId, title, start, end, allDay,
          location: loc, description: desc, color: color || null,
        });
        showToast('Termin erstellt');
      }
      closeModal('modal-event');
      fetchAndRender();
    } catch (e) {
      showToast(e.message, true);
    }
  };

  document.getElementById('ev-delete').onclick = async () => {
    const ev = state.editingEvent;
    if (!ev) return;
    if (!confirm(`"${ev.title}" wirklich löschen?`)) return;
    try {
      await api.delete(`/caldav/events/${encodeURIComponent(ev.id)}?event_url=${encodeURIComponent(ev.url)}`);
      showToast('Termin gelöscht');
      closeModal('modal-event');
      fetchAndRender();
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
      showToast(`Konto "${name}" hinzugefügt`);
      fetchAndRender();
    } catch (e) {
      errEl.textContent = e.message;
      errEl.classList.remove('hidden');
    } finally {
      document.getElementById('acc-save').disabled = false;
      document.getElementById('acc-save').textContent = 'Verbinden';
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

  // Show users section only for admins
  const user = JSON.parse(localStorage.getItem('user') || '{}');
  const usersSection = document.getElementById('settings-users-section');
  if (user.is_admin) {
    usersSection.classList.remove('hidden');
    loadUsers();
  } else {
    usersSection.classList.add('hidden');
  }

  openModal('modal-settings');
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
        if (!confirm('Benutzer löschen?')) return;
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

  document.getElementById('btn-add-user').onclick = () => {
    document.getElementById('add-user-form').classList.toggle('hidden');
  };

  document.getElementById('new-user-save').onclick = async () => {
    const username = document.getElementById('new-username').value.trim();
    const password = document.getElementById('new-password').value;
    const is_admin = document.getElementById('new-is-admin').checked;
    if (!username || !password) { showToast('Benutzername und Passwort erforderlich', true); return; }
    try {
      await api.post('/users/', { username, password, is_admin });
      showToast(`Benutzer "${username}" erstellt`);
      document.getElementById('add-user-form').classList.add('hidden');
      document.getElementById('new-username').value = '';
      document.getElementById('new-password').value = '';
      loadUsers();
    } catch (e) { showToast(e.message, true); }
  };

  document.getElementById('settings-save').onclick = async () => {
    const settings = {
      default_view:    document.getElementById('cfg-default-view').value,
      week_start_day:  document.getElementById('cfg-week-start').value,
      primary_color:   document.getElementById('cfg-primary-hex').value,
      accent_color:    document.getElementById('cfg-accent-hex').value,
      today_color:     document.getElementById('cfg-today-hex').value,
      dim_past_events: document.getElementById('cfg-dim-past').checked,
    };
    try {
      await api.put('/settings/', settings);
      state.settings = { ...state.settings, ...settings };
      state.dimPast  = settings.dim_past_events;
      weekStartDay   = settings.week_start_day;
      applyTheme(settings);
      showToast('Einstellungen gespeichert');
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
    container.innerHTML = '<p class="text-muted">Keine CalDAV-Konten verbunden.</p>';
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
      showToast('Profil gespeichert');
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
      showToast('Profilbild entfernt');
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
    if (!current || !newPw) { showToast('Bitte alle Felder ausfüllen', true); return; }
    if (newPw !== confirm) { showToast('Passwörter stimmen nicht überein', true); return; }
    if (newPw.length < 6) { showToast('Mindestens 6 Zeichen', true); return; }
    try {
      await api.post('/profile/password', { current_password: current, new_password: newPw });
      showToast('Passwort geändert');
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
    navigator.clipboard.writeText(secret).then(() => showToast('Schlüssel kopiert'));
  };

  document.getElementById('2fa-enable-btn').onclick = async () => {
    const code = document.getElementById('2fa-verify-code').value.trim();
    if (!code || code.length !== 6) { showToast('Bitte 6-stelligen Code eingeben', true); return; }
    try {
      await api.post('/profile/2fa/enable', { code });
      showToast('2FA aktiviert');
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
    if (!pw) { showToast('Bitte Passwort eingeben', true); return; }
    try {
      await api.post('/profile/2fa/disable', { password: pw });
      showToast('2FA deaktiviert');
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
  renderCalendarList();
  fetchAndRender();
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
      showToast('Profilbild hochgeladen');
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
