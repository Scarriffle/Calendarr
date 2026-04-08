import { isToday, isPast, dayOfWeek, weekStart, getISOWeekNumber } from '../utils.js';
import { t } from '../i18n.js';

export function renderWeek(container, currentDate, events, onSlotClick, onEventClick, isSingleDay = false, weekStartDay = 'monday', hourH = 60) {
  // Build the days array (7 days for week, 1 for day)
  const days = [];
  if (isSingleDay) {
    days.push(new Date(currentDate));
  } else {
    const monday = weekStart(currentDate, weekStartDay);
    for (let i = 0; i < 7; i++) {
      const d = new Date(monday);
      d.setDate(d.getDate() + i);
      days.push(d);
    }
  }

  // Separate all-day and timed events
  const allDayEvs      = events.filter(ev => ev.allDay);
  const timedEvs       = events.filter(ev => !ev.allDay);
  // Multi-day timed events: timed but spanning more than one calendar day
  const multiDayTimedEvs = timedEvs.filter(ev => !isSameDay(new Date(ev.start), new Date(ev.end)));

  // Returns true if event overlaps any part of the given day
  function spansDay(ev, day) {
    const evStart  = new Date(ev.start);
    const evEnd    = new Date(ev.end);
    const dayStart = new Date(day); dayStart.setHours(0, 0, 0, 0);
    const dayEnd   = new Date(day); dayEnd.setHours(24, 0, 0, 0);
    return evStart < dayEnd && evEnd > dayStart;
  }

  // ── KW Badge ──────────────────────────────────────────
  const kwNum = getISOWeekNumber(days[0]);
  const kwBadge = !isSingleDay
    ? `<div class="week-kw-badge">${t('week_abbr')} ${kwNum}</div>`
    : '';

  // ── Header ────────────────────────────────────────────
  const headerCols = days.map(day => {
    const todayCls = isToday(day) ? 'today' : '';
    return `<div class="week-day-header ${todayCls}" data-date="${dayKey(day)}">
      <div class="day-name">${t('dow_index')[day.getDay()]}</div>
      <div class="day-num">${day.getDate()}</div>
    </div>`;
  }).join('');

  // ── All-day row (spanning bars, same logic as month view) ──
  const ALLDAY_LANE_H = 22;
  const allDayAndMulti = [...allDayEvs, ...multiDayTimedEvs];
  const alldayLayout   = layoutWeekAllDay(allDayAndMulti, days);
  // Items that span more than one column → used for column background tint
  const multiDayLayoutItems = alldayLayout.filter(item => item.colEnd > item.colStart);
  const maxAlldayLane  = alldayLayout.length ? alldayLayout.reduce((m, it) => Math.max(m, it.lane), 0) : -1;
  const alldayRowH     = maxAlldayLane < 0 ? 28 : (maxAlldayLane + 1) * ALLDAY_LANE_H + 6;

  const alldaySpanHtml = alldayLayout.map(({ ev, colStart, colEnd, lane }) => {
    const isMultiTimed = multiDayTimedEvs.includes(ev);
    const n     = days.length;
    const left  = (colStart / n) * 100;
    const width = ((colEnd - colStart + 1) / n) * 100;
    const top   = lane * ALLDAY_LANE_H + 2;
    const color = ev.color || ev.calendarColor || '#4285f4';
    const pastCls  = isPast(ev) ? 'past' : '';
    const multiCls = isMultiTimed ? 'multiday-timed' : '';
    const cL = new Date(ev.start) < new Date(days[0]) ? 'continues-left' : '';
    const cR = new Date(ev.end)   > (() => { const d = new Date(days[n-1]); d.setHours(24,0,0,0); return d; })() ? 'continues-right' : '';
    const label = isMultiTimed && isSameDay(new Date(ev.start), days[colStart])
      ? `${fmtTime(new Date(ev.start))} ${ev.title}`
      : ev.title;
    return `<div class="allday-span ${pastCls} ${multiCls} ${cL} ${cR}"
      style="left:calc(${left.toFixed(2)}% + 1px);width:calc(${width.toFixed(2)}% - 2px);top:${top}px;background:${color};color:#fff"
      data-id="${ev.id}" data-url="${escAttr(ev.url)}" title="${escAttr(ev.title)}">${escHtml(label)}</div>`;
  }).join('');

  const alldayBgCols = days.map(day =>
    `<div class="allday-col-bg" data-date="${dayKey(day)}"></div>`
  ).join('');

  const alldayCols = `<div class="allday-cols-wrap" style="height:${alldayRowH}px">
    ${alldayBgCols}
    <div class="allday-spans-layer">${alldaySpanHtml}</div>
  </div>`;

  // ── Time column labels ────────────────────────────────
  const timeLabels = Array.from({length: 24}, (_, h) =>
    `<div class="time-label">${h === 0 ? '' : `${String(h).padStart(2,'0')}:00`}</div>`
  ).join('');

  // ── Day columns ───────────────────────────────────────
  const dayCols = days.map((day, dayIdx) => {
    const key = dayKey(day);
    const dayEvs = timedEvs.filter(ev => {
      const s = new Date(ev.start);
      return isSameDay(s, day);
    });

    const positioned = layoutEvents(dayEvs);

    const hourLines = Array.from({length: 24}, (_, h) =>
      `<div class="hour-line" style="top:${h * hourH}px"><div class="half-line"></div></div>`
    ).join('');

    const evHtml = positioned.map(({ ev, col, cols }) => {
      const s = new Date(ev.start);
      const e = new Date(ev.end);
      const top    = s.getHours() * hourH + s.getMinutes() * hourH / 60;
      const dayEnd = new Date(s); dayEnd.setHours(24, 0, 0, 0);
      const clampedEnd = e > dayEnd ? dayEnd : e;
      const height = Math.max(20, (clampedEnd - s) / 60000 * hourH / 60);
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

    // Background tint: reuse alldayLayout (proven correct) — colEnd > colStart = multi-day
    const dayTintEvs = multiDayLayoutItems
      .filter(item => dayIdx >= item.colStart && dayIdx <= item.colEnd)
      .map(item => item.ev);
    const tintHtml = (() => {
      if (!dayTintEvs.length) return '';
      const colors = dayTintEvs.map(ev => ev.color || ev.calendarColor || '#4285f4');
      let bg;
      if (colors.length === 1) {
        bg = colors[0] + '26';
      } else {
        // Vertical gradient bands for multiple overlapping multi-day events
        const stops = colors.flatMap((c, i) => {
          const p1 = ((i / colors.length) * 100).toFixed(1);
          const p2 = (((i + 1) / colors.length) * 100).toFixed(1);
          return [`${c}26 ${p1}%`, `${c}26 ${p2}%`];
        }).join(',');
        bg = `linear-gradient(to bottom,${stops})`;
      }
      return `<div class="col-span-tint" style="background:${bg}"></div>`;
    })();

    return `<div class="week-day-col" data-date="${key}" style="height:${hourH * 24}px">
      ${tintHtml}
      ${hourLines}
      ${evHtml}
    </div>`;
  }).join('');

  const viewClass = isSingleDay ? 'day-view' : 'week-view';

  container.innerHTML = `<div class="${viewClass}">
    <div class="week-head-sticky">
      <div class="week-header-row">
        <div class="week-time-gutter">${kwBadge}</div>
        ${headerCols}
      </div>
      <div class="week-allday-row">
        <div class="allday-gutter">${t('allday')}</div>
        ${alldayCols}
      </div>
    </div>
    <div class="week-time-area">
      <div class="week-time-col">${timeLabels}</div>
      <div class="week-days-col">${dayCols}</div>
    </div>
  </div>`;

  // Scroll to ~8:00
  const scrollEl = container.querySelector(`.${viewClass}`);
  if (scrollEl) scrollEl.scrollTop = 8 * hourH - 20;

  // Render current-time line
  renderNowLine(container, days, hourH);

  // Click: slot
  container.querySelectorAll('.week-day-col').forEach(col => {
    col.addEventListener('click', e => {
      if (e.target.closest('.timed-event')) return;
      const rect = col.getBoundingClientRect();
      const y    = e.clientY - rect.top + (scrollEl?.scrollTop || 0);
      const h    = Math.floor(y / hourH);
      const m    = Math.round(((y % hourH) / hourH * 60) / 15) * 15;
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

  // Click: all-day span
  container.querySelectorAll('.allday-span').forEach(el => {
    el.addEventListener('click', e => {
      e.stopPropagation();
      const ev = events.find(ev => ev.id === el.dataset.id && ev.url === el.dataset.url);
      if (ev) onEventClick(ev, el);
    });
  });
}

function renderNowLine(container, days, hourH = 60) {
  const now = new Date();
  const todayCol = container.querySelector(`.week-day-col[data-date="${dayKey(now)}"]`);
  if (!todayCol) return;

  const top = now.getHours() * hourH + now.getMinutes() * hourH / 60;
  const line = document.createElement('div');
  line.className = 'now-line';
  line.style.top = top + 'px';
  line.innerHTML = '<div class="now-dot"></div>';
  todayCol.appendChild(line);

  setTimeout(() => renderNowLine(container, days, hourH), 60000);
}

function layoutWeekAllDay(evs, days) {
  const items = [];
  evs.forEach(ev => {
    let colStart = -1, colEnd = -1;
    days.forEach((day, i) => {
      const ds = new Date(day); ds.setHours(0, 0, 0, 0);
      const de = new Date(day); de.setHours(24, 0, 0, 0);
      if (new Date(ev.start) < de && new Date(ev.end) > ds) {
        if (colStart === -1) colStart = i;
        colEnd = i;
      }
    });
    if (colStart === -1) return;
    items.push({ ev, colStart, colEnd });
  });

  // Sort: longer spans first, then by start column
  items.sort((a, b) =>
    (b.colEnd - b.colStart) - (a.colEnd - a.colStart) || a.colStart - b.colStart
  );

  // Greedy lane assignment
  const laneEnds = [];
  items.forEach(item => {
    let lane = laneEnds.findIndex(end => item.colStart > end);
    if (lane === -1) { lane = laneEnds.length; laneEnds.push(-1); }
    item.lane = lane;
    laneEnds[lane] = item.colEnd;
  });

  return items;
}

function layoutEvents(events) {
  if (!events.length) return [];

  const sorted = events.slice().sort((a, b) => new Date(a.start) - new Date(b.start));
  const columns = [];

  const result = sorted.map(ev => {
    const start = new Date(ev.start);
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

  return result.map(ev => {
    const start = new Date(ev.start);
    const end   = new Date(ev.end);
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
