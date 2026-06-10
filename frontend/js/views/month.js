import { isToday, isPast, isSameDay, dayOfWeek, weekStart, getISOWeekNumber } from '../utils.js';
import { t } from '../i18n.js';

const LANE_H   = 20; // px per lane (event height 18px + 2px gap)
const DAY_H    = 30; // day-number row height
const NUM_ROWS = 5;  // rolling view: always 5 weeks

export function renderMonth(container, currentDate, events, onDayClick, onEventClick, weekStartDay = 'monday', selectedDate = null) {
  // Dynamic lane limit: how many events fit in the actual row height
  const containerH = container.clientHeight || 600;
  const headerH    = 34; // month-header DOW row
  const rowH       = (containerH - headerH) / NUM_ROWS;
  const MAX_LANES  = Math.max(1, Math.floor((rowH - DAY_H) / LANE_H) - 1);
  // "Primary month" = currentDate's month (used for muting other-month days)
  const primaryMonth = currentDate.getMonth();
  const DOW = weekStartDay === 'sunday' ? t('dow_sunday') : t('dow_monday');

  // Rolling grid: start at the week that contains currentDate
  const gridStart = weekStart(currentDate, weekStartDay);

  // Build NUM_ROWS × 7 cells
  const cells = [];
  const d = new Date(gridStart);
  for (let i = 0; i < NUM_ROWS * 7; i++) {
    cells.push(new Date(d));
    d.setDate(d.getDate() + 1);
  }

  // Normalize each event's date range once
  const normed = events.map(ev => {
    const s = new Date(ev.start); s.setHours(0, 0, 0, 0);
    const e = new Date(ev.end);   e.setHours(0, 0, 0, 0);
    if (ev.allDay && e > s) e.setDate(e.getDate() - 1); // exclusive → inclusive
    return { ev, ns: s, ne: e };
  });

  // Header
  const headerHtml =
    `<div class="month-kw-header">KW</div>` +
    DOW.map(d => `<div class="month-dow">${d}</div>`).join('');

  // Build rows
  let bodyHtml = '';
  for (let row = 0; row < NUM_ROWS; row++) {
    const rowCells = cells.slice(row * 7, row * 7 + 7);
    const rowStart = new Date(rowCells[0]); rowStart.setHours(0, 0, 0, 0);
    const rowEnd   = new Date(rowCells[6]); rowEnd.setHours(0, 0, 0, 0);
    const kw = getISOWeekNumber(rowCells[0]);

    // Collect events overlapping this row
    const rowItems = [];
    normed.forEach(({ ev, ns, ne }) => {
      if (ne < rowStart || ns > rowEnd) return;
      const colStart = Math.max(0, daysBetween(rowStart, ns));
      const colEnd   = Math.min(6, daysBetween(rowStart, ne));
      if (colEnd < colStart) return;
      rowItems.push({
        ev,
        colStart,
        span: colEnd - colStart + 1,
        continuesLeft:  ns < rowStart,
        continuesRight: ne > rowEnd,
      });
    });

    // Sort: all-day first, then span desc, then start time
    rowItems.sort((a, b) => {
      if (a.ev.allDay && !b.ev.allDay) return -1;
      if (!a.ev.allDay && b.ev.allDay) return 1;
      if (b.span !== a.span) return b.span - a.span;
      return new Date(a.ev.start) - new Date(b.ev.start);
    });

    // Assign lanes using a 2D occupancy grid (per-column tracking).
    // This prevents gaps: an event in cols 3-6 no longer blocks col 0-2 in the same lane.
    const occupiedGrid = []; // occupiedGrid[lane] = Set<col>
    rowItems.forEach(item => {
      const cols = Array.from({ length: item.span }, (_, i) => item.colStart + i);
      let laneIdx = 0;
      for (;;) {
        if (!occupiedGrid[laneIdx]) occupiedGrid[laneIdx] = new Set();
        if (cols.every(c => !occupiedGrid[laneIdx].has(c))) {
          cols.forEach(c => occupiedGrid[laneIdx].add(c));
          item.lane = laneIdx;
          break;
        }
        laneIdx++;
      }
    });

    // Track overflow per column
    const overflowByCol = {};
    rowItems.forEach(item => {
      if (item.lane >= MAX_LANES) {
        for (let c = item.colStart; c < item.colStart + item.span; c++) {
          overflowByCol[c] = (overflowByCol[c] || 0) + 1;
        }
      }
    });

    // Render event spans HTML (placed in overlay)
    let eventsHtml = '';
    rowItems.forEach(item => {
      if (item.lane >= MAX_LANES) return;
      const { ev, colStart, span, continuesLeft, continuesRight } = item;
      const leftPct  = (colStart / 7) * 100;
      const widthPct = (span / 7) * 100 - 0.4;
      const topPx    = item.lane * LANE_H + 2;
      const color    = ev.color || ev.calendarColor || '#4285f4';
      const pastCls  = isPast(ev) ? 'past' : '';
      const cL = continuesLeft  ? 'continues-left'  : '';
      const cR = continuesRight ? 'continues-right' : '';
      const titleEsc = escHtml(ev.title);
      const labelHtml = ev.allDay
        ? titleEsc
        : `<span class="month-event-time">${escHtml(fmtTime(new Date(ev.start)))}</span> ${titleEsc}`;
      eventsHtml += `<div class="month-span-event ${pastCls} ${cL} ${cR}"
        data-id="${ev.id}" data-url="${escAttr(ev.url)}"
        style="left:${leftPct.toFixed(3)}%;width:${widthPct.toFixed(3)}%;top:${topPx}px;background:${color}"
        title="${escAttr(ev.title)}">${labelHtml}</div>`;
    });

    // "+N more" per column
    Object.entries(overflowByCol).forEach(([col, count]) => {
      const c = parseInt(col);
      eventsHtml += `<div class="month-more"
        data-date="${dateKey(rowCells[c])}"
        style="left:${((c / 7) * 100).toFixed(3)}%;width:${(100 / 7).toFixed(3)}%;bottom:2px">${t('more_events', { n: count })}</div>`;
    });

    // Detect a month boundary in this row. monthChangeIdx is the index of
    // the first-of-month cell, or -1 if the row doesn't span a month change.
    let monthChangeIdx = -1;
    rowCells.forEach((cell, idx) => {
      if (cell.getDate() === 1 && idx > 0) monthChangeIdx = idx;
    });

    // Full-height column divs (click targets + borders)
    const monthsShort = t('months_short');
    let colsHtml = '';
    rowCells.forEach((cell, idx) => {
      const key      = dateKey(cell);
      const isOther  = cell.getMonth() !== primaryMonth;
      const todayCls    = isToday(cell) ? 'today' : '';
      const otherCls    = isOther       ? 'other-month' : '';
      const selDate     = selectedDate || currentDate;
      const selectedCls = isSameDay(cell, selDate) ? 'month-selected' : '';
      const numCls      = isToday(cell) ? 'today' : '';
      // First-of-month marker: show month abbreviation, push day number below
      const isFirstOfMonth = cell.getDate() === 1;
      const firstCls   = isFirstOfMonth ? 'first-of-month' : '';
      // Step-shaped boundary at month change: bottom under the previous-month
      // tail, vertical at the change, top across the new-month head.
      const dividerClasses = [];
      if (isFirstOfMonth && idx > 0) dividerClasses.push('month-divider-left');
      if (monthChangeIdx > 0 && idx >= monthChangeIdx) dividerClasses.push('month-divider-top');
      if (monthChangeIdx > 0 && idx < monthChangeIdx) dividerClasses.push('month-divider-bottom');
      const dividerCls = dividerClasses.join(' ');
      const monthLabel = isFirstOfMonth
        ? `<span class="month-marker">${monthsShort[cell.getMonth()]}</span>`
        : '';
      colsHtml += `<div class="month-col ${todayCls} ${otherCls} ${selectedCls} ${firstCls} ${dividerCls}" data-date="${key}">
        <div class="cell-day ${numCls}">${cell.getDate()}</div>
        ${monthLabel}
      </div>`;
    });

    // If the row starts on the 1st of a new month, draw a full-width divider above the row
    const rowDividerCls = rowCells[0].getDate() === 1 ? 'month-divider-top' : '';
    // If any cell in the row is first-of-month, push events overlay down so the day
    // number isn't hidden by spanning event bars
    const hasMonthMarker = rowCells.some(c => c.getDate() === 1);
    const rowMarkerCls = hasMonthMarker ? 'has-month-marker' : '';
    bodyHtml += `<div class="month-row ${rowDividerCls} ${rowMarkerCls}">
      <div class="month-kw-cell">${kw}</div>
      <div class="month-row-right">
        ${colsHtml}
        <div class="month-events-overlay">${eventsHtml}</div>
      </div>
    </div>`;
  }

  container.innerHTML = `<div class="month-view">
    <div class="month-header">${headerHtml}</div>
    <div class="month-body">${bodyHtml}</div>
  </div>`;

  // Click handlers via event delegation on the body
  const body = container.querySelector('.month-body');

  // Single click: select day (or handle event / more clicks)
  body.addEventListener('click', e => {
    // Span event click
    const spanEl = e.target.closest('.month-span-event');
    if (spanEl) {
      e.stopPropagation();
      const ev = events.find(ev => ev.id === spanEl.dataset.id && ev.url === spanEl.dataset.url);
      if (ev) onEventClick(ev, spanEl);
      return;
    }
    // "+N more" → show overflow popup with all events for that day
    const moreEl = e.target.closest('.month-more');
    if (moreEl) {
      e.stopPropagation();
      const dayDate = new Date(moreEl.dataset.date + 'T00:00:00');
      const dayEvents = normed
        .filter(({ ns, ne }) => ns <= dayDate && ne >= dayDate)
        .map(({ ev }) => ev)
        .sort((a, b) => {
          if (a.allDay && !b.allDay) return -1;
          if (!a.allDay && b.allDay) return 1;
          return new Date(a.start) - new Date(b.start);
        });
      showOverflowPopup(moreEl, dayDate, dayEvents, onEventClick);
      return;
    }
    // Column click → select day
    const colEl = e.target.closest('.month-col');
    if (colEl) {
      onDayClick(new Date(colEl.dataset.date + 'T00:00:00'), 'select');
    }
  });

  // Double click: navigate to day view
  body.addEventListener('dblclick', e => {
    const colEl = e.target.closest('.month-col');
    if (colEl && !e.target.closest('.month-span-event')) {
      onDayClick(new Date(colEl.dataset.date + 'T00:00:00'), 'navigate');
    }
  });

  // Right click: context menu
  body.addEventListener('contextmenu', e => {
    const colEl = e.target.closest('.month-col');
    if (colEl) {
      e.preventDefault();
      onDayClick(new Date(colEl.dataset.date + 'T00:00:00'), 'context', e);
    }
  });
}

// ── Helpers ───────────────────────────────────────────────

function daysBetween(a, b) {
  return Math.round((b - a) / 86400000);
}

function dateKey(d) {
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
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

function showOverflowPopup(anchor, date, events, onEventClick) {
  document.querySelectorAll('.month-overflow-popup').forEach(p => p.remove());

  const popup = document.createElement('div');
  popup.className = 'month-overflow-popup';

  // Header: "Mo, 3. Jul"
  const months = t('months');
  const dow    = t('dow_monday');
  const dowIdx = (date.getDay() + 6) % 7; // 0=Mon
  const header = document.createElement('div');
  header.className = 'mop-header';
  header.textContent = `${dow[dowIdx]}, ${date.getDate()}. ${months[date.getMonth()]}`;
  popup.appendChild(header);

  events.forEach(ev => {
    const row = document.createElement('div');
    row.className = 'mop-row';

    const dot = document.createElement('span');
    dot.className = 'mop-dot';
    dot.style.background = ev.color || ev.calendarColor || '#4285f4';

    const time = document.createElement('span');
    time.className = 'mop-time';
    time.textContent = ev.allDay ? t('allday_cap') : fmtTime(new Date(ev.start));

    const title = document.createElement('span');
    title.className = 'mop-title';
    title.textContent = ev.title;

    row.append(dot, time, title);
    row.addEventListener('click', e => {
      e.stopPropagation();
      popup.remove();
      onEventClick(ev, row);
    });
    popup.appendChild(row);
  });

  document.body.appendChild(popup);

  // Position near anchor, stay in viewport
  const r  = anchor.getBoundingClientRect();
  const pw = popup.offsetWidth  || 260;
  const ph = popup.offsetHeight || 200;
  let left = r.left;
  let top  = r.bottom + 4;
  if (left + pw > window.innerWidth  - 8) left = window.innerWidth  - pw - 8;
  if (top  + ph > window.innerHeight - 8) top  = r.top - ph - 4;
  if (left < 8) left = 8;
  if (top  < 8) top  = 8;
  popup.style.left = left + 'px';
  popup.style.top  = top  + 'px';

  setTimeout(() => {
    document.addEventListener('click', function close() {
      popup.remove();
      document.removeEventListener('click', close);
    });
  }, 0);
}
