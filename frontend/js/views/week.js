import { isToday, isPast } from '../utils.js';

const DOW_SHORT = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];

export function renderWeek(container, currentDate, events, onSlotClick, onEventClick, isSingleDay = false) {
  // Build the days array (7 days for week, 1 for day)
  const days = [];
  if (isSingleDay) {
    days.push(new Date(currentDate));
  } else {
    const sunday = new Date(currentDate);
    sunday.setDate(sunday.getDate() - sunday.getDay());
    for (let i = 0; i < 7; i++) {
      const d = new Date(sunday);
      d.setDate(d.getDate() + i);
      days.push(d);
    }
  }

  // Separate all-day and timed events
  const allDayEvs = events.filter(ev => ev.allDay);
  const timedEvs  = events.filter(ev => !ev.allDay);

  // ── Header ────────────────────────────────────────────
  const headerCols = days.map(day => {
    const todayCls = isToday(day) ? 'today' : '';
    return `<div class="week-day-header ${todayCls}" data-date="${dayKey(day)}">
      <div class="day-name">${DOW_SHORT[day.getDay()]}</div>
      <div class="day-num">${day.getDate()}</div>
    </div>`;
  }).join('');

  // ── All-day row ───────────────────────────────────────
  const alldayCols = days.map(day => {
    const key = dayKey(day);
    const dayEvs = allDayEvs.filter(ev => {
      const s = new Date(ev.start); s.setHours(0,0,0,0);
      const e = new Date(ev.end);   e.setHours(0,0,0,0);
      const d = new Date(day);      d.setHours(0,0,0,0);
      return d >= s && d < e || isSameDay(d, s);
    });
    const inner = dayEvs.map(ev => {
      const color = ev.color || ev.calendarColor || '#4285f4';
      return `<div class="allday-event" style="background:${color};color:#fff"
        data-id="${ev.id}" data-url="${escAttr(ev.url)}" title="${escAttr(ev.title)}">${escHtml(ev.title)}</div>`;
    }).join('');
    return `<div class="allday-col" data-date="${key}">${inner}</div>`;
  }).join('');

  // ── Time column labels ────────────────────────────────
  const timeLabels = Array.from({length: 24}, (_, h) =>
    `<div class="time-label">${h === 0 ? '' : `${String(h).padStart(2,'0')}:00`}</div>`
  ).join('');

  // ── Day columns ───────────────────────────────────────
  // For each day, lay out timed events
  const dayCols = days.map(day => {
    const key = dayKey(day);
    const dayEvs = timedEvs.filter(ev => {
      const s = new Date(ev.start);
      return isSameDay(s, day);
    });

    // Compute layout columns for overlapping events
    const positioned = layoutEvents(dayEvs);

    const hourLines = Array.from({length: 24}, (_, h) =>
      `<div class="hour-line" style="top:${h * 60}px"><div class="half-line"></div></div>`
    ).join('');

    const evHtml = positioned.map(({ ev, col, cols }) => {
      const s = new Date(ev.start);
      const e = new Date(ev.end);
      const top    = (s.getHours() * 60 + s.getMinutes());
      const height = Math.max(20, (e - s) / 60000);
      const left   = (col / cols) * 100;
      const width  = (1 / cols) * 100 - 0.5;
      const color  = ev.color || ev.calendarColor || '#4285f4';
      const pastCls = isPast(ev) ? 'past' : '';
      const startStr = fmtTime(s);
      const locHtml = ev.location ? `<div class="ev-loc">${escHtml(ev.location)}</div>` : '';
      return `<div class="timed-event ${pastCls}"
        style="top:${top}px;height:${height}px;left:${left}%;width:${width}%;background:${color};color:#fff"
        data-id="${ev.id}" data-url="${escAttr(ev.url)}" title="${escAttr(ev.title)}">
        <div class="ev-time">${startStr}</div>
        <div class="ev-title">${escHtml(ev.title)}</div>
        ${locHtml}
      </div>`;
    }).join('');

    return `<div class="week-day-col" data-date="${key}" style="height:${60*24}px">
      ${hourLines}
      ${evHtml}
    </div>`;
  }).join('');

  const viewClass = isSingleDay ? 'day-view' : 'week-view';

  container.innerHTML = `<div class="${viewClass}">
    <div class="week-header-row">
      <div class="week-time-gutter"></div>
      ${headerCols}
    </div>
    <div class="week-allday-row">
      <div class="allday-gutter">ganztägig</div>
      <div class="allday-cols">${alldayCols}</div>
    </div>
    <div class="week-body">
      <div class="week-time-col">${timeLabels}</div>
      <div class="week-days-col">${dayCols}</div>
    </div>
  </div>`;

  // Scroll to ~8:00
  const body = container.querySelector('.week-body');
  if (body) body.scrollTop = 8 * 60 - 20;

  // Render current-time line
  renderNowLine(container, days);

  // Click: slot
  container.querySelectorAll('.week-day-col').forEach(col => {
    col.addEventListener('click', e => {
      if (e.target.closest('.timed-event')) return;
      const rect = col.getBoundingClientRect();
      const y    = e.clientY - rect.top + (container.querySelector('.week-body')?.scrollTop || 0);
      const mins = Math.floor(y);
      const h    = Math.floor(mins / 60);
      const m    = Math.round((mins % 60) / 15) * 15;
      const date = new Date(col.dataset.date + 'T00:00:00');
      date.setHours(h, m, 0, 0);
      onSlotClick(date);
    });
  });

  // Click: header (navigate to day)
  container.querySelectorAll('.week-day-header').forEach(el => {
    el.addEventListener('click', () => {
      onSlotClick(new Date(el.dataset.date + 'T09:00:00'), true);
    });
  });

  // Click: timed event
  container.querySelectorAll('.timed-event').forEach(el => {
    el.addEventListener('click', e => {
      e.stopPropagation();
      const ev = events.find(ev => ev.id === el.dataset.id && ev.url === el.dataset.url);
      if (ev) onEventClick(ev, el);
    });
  });

  // Click: all-day event
  container.querySelectorAll('.allday-event').forEach(el => {
    el.addEventListener('click', e => {
      e.stopPropagation();
      const ev = events.find(ev => ev.id === el.dataset.id && ev.url === el.dataset.url);
      if (ev) onEventClick(ev, el);
    });
  });
}

function renderNowLine(container, days) {
  const now = new Date();
  const todayCol = container.querySelector(`.week-day-col[data-date="${dayKey(now)}"]`);
  if (!todayCol) return;

  const top = now.getHours() * 60 + now.getMinutes();
  const line = document.createElement('div');
  line.className = 'now-line';
  line.style.top = top + 'px';
  line.innerHTML = '<div class="now-dot"></div>';
  todayCol.appendChild(line);

  // Update every minute
  setTimeout(() => renderNowLine(container, days), 60000);
}

function layoutEvents(events) {
  if (!events.length) return [];

  // Sort by start time
  const sorted = events.slice().sort((a, b) => new Date(a.start) - new Date(b.start));
  const columns = []; // each column is an array of events

  const result = sorted.map(ev => {
    const start = new Date(ev.start);
    const end   = new Date(ev.end);

    // Find the first column where the event doesn't overlap
    let placed = false;
    for (let c = 0; c < columns.length; c++) {
      const lastInCol = columns[c][columns[c].length - 1];
      if (new Date(lastInCol.end) <= start) {
        columns[c].push(ev);
        placed = true;
        ev._col = c;
        break;
      }
    }
    if (!placed) {
      ev._col = columns.length;
      columns.push([ev]);
    }
    return ev;
  });

  // Calculate how many columns each event spans
  return result.map(ev => {
    const start = new Date(ev.start);
    const end   = new Date(ev.end);
    // Count overlapping events
    let maxCol = ev._col;
    sorted.forEach(other => {
      if (other === ev) return;
      const os = new Date(other.start);
      const oe = new Date(other.end);
      if (os < end && oe > start) {
        maxCol = Math.max(maxCol, other._col ?? 0);
      }
    });
    return { ev, col: ev._col, cols: maxCol + 1 };
  });
}

function dayKey(d) {
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
}

function isSameDay(a, b) {
  return a.getFullYear() === b.getFullYear() &&
         a.getMonth()    === b.getMonth()    &&
         a.getDate()     === b.getDate();
}

function fmtTime(d) {
  return d.toLocaleTimeString('de', { hour: '2-digit', minute: '2-digit' });
}

function escHtml(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}
function escAttr(s) {
  return String(s).replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}
