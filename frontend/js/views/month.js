import { isToday, isPast, isSameDay, dayOfWeek, weekStart, getISOWeekNumber } from '../utils.js';
import { t } from '../i18n.js';

const LANE_H   = 20; // px per lane (event height 18px + 2px gap)
const DAY_H    = 30; // day-number row height
const NUM_ROWS = 5;  // rolling view: always 5 weeks

export function renderMonth(container, currentDate, events, onDayClick, onEventClick, weekStartDay = 'monday') {
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

    // Assign lanes (greedy interval packing)
    const lanes = [];
    rowItems.forEach(item => {
      let laneIdx = lanes.findIndex(l => item.colStart >= l.colEnd);
      if (laneIdx === -1) { laneIdx = lanes.length; lanes.push({ colEnd: 0 }); }
      item.lane = laneIdx;
      lanes[laneIdx].colEnd = item.colStart + item.span;
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
      const label = ev.allDay
        ? ev.title
        : `${fmtTime(new Date(ev.start))} ${ev.title}`;
      eventsHtml += `<div class="month-span-event ${pastCls} ${cL} ${cR}"
        data-id="${ev.id}" data-url="${escAttr(ev.url)}"
        style="left:${leftPct.toFixed(3)}%;width:${widthPct.toFixed(3)}%;top:${topPx}px;background:${color}"
        title="${escAttr(ev.title)}">${escHtml(label)}</div>`;
    });

    // "+N more" per column
    Object.entries(overflowByCol).forEach(([col, count]) => {
      const c = parseInt(col);
      eventsHtml += `<div class="month-more"
        data-date="${dateKey(rowCells[c])}"
        style="left:${((c / 7) * 100).toFixed(3)}%;width:${(100 / 7).toFixed(3)}%;bottom:2px">${t('more_events', { n: count })}</div>`;
    });

    // Full-height column divs (click targets + borders)
    let colsHtml = '';
    rowCells.forEach(cell => {
      const key      = dateKey(cell);
      const isOther  = cell.getMonth() !== primaryMonth;
      const todayCls    = isToday(cell) ? 'today' : '';
      const otherCls    = isOther       ? 'other-month' : '';
      const selectedCls = isSameDay(cell, currentDate) ? 'month-selected' : '';
      const numCls      = isToday(cell) ? 'today' : '';
      colsHtml += `<div class="month-col ${todayCls} ${otherCls} ${selectedCls}" data-date="${key}">
        <div class="cell-day ${numCls}">${cell.getDate()}</div>
      </div>`;
    });

    bodyHtml += `<div class="month-row">
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
    // "+N more" → navigate to day view
    const moreEl = e.target.closest('.month-more');
    if (moreEl) {
      e.stopPropagation();
      onDayClick(new Date(moreEl.dataset.date + 'T00:00:00'), 'navigate');
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
