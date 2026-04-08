import { isToday, isSameDay, isPast, dayOfWeek, getISOWeekNumber } from '../utils.js';
import { t } from '../i18n.js';

export function renderQuarter(container, currentDate, events, onDayClick, onEventClick, weekStartDay = 'monday') {
  const year = currentDate.getFullYear();
  // Quarter: Q1=0, Q2=1, Q3=2, Q4=3
  const quarter = Math.floor(currentDate.getMonth() / 3);
  const firstMonthOfQ = quarter * 3;

  // Build event map keyed by date string
  const evMap = {};
  events.forEach(ev => {
    const s = new Date(ev.start);
    const e = new Date(ev.end);
    const cur = new Date(s);
    cur.setHours(0, 0, 0, 0);
    const endNorm = new Date(e);
    endNorm.setHours(0, 0, 0, 0);
    if (ev.allDay && endNorm > cur) endNorm.setDate(endNorm.getDate() - 1);
    while (cur <= endNorm) {
      const key = dateKey(cur);
      if (!evMap[key]) evMap[key] = [];
      evMap[key].push(ev);
      cur.setDate(cur.getDate() + 1);
    }
  });

  const DOW = weekStartDay === 'sunday' ? t('dow_sunday') : t('dow_monday');
  const MONTHS = t('months');

  const monthsHtml = [0, 1, 2].map(offset => {
    const month = firstMonthOfQ + offset;
    const firstDay = new Date(year, month, 1);
    const lastDay  = new Date(year, month + 1, 0);

    // Start grid on correct weekday
    const gridStart = new Date(firstDay);
    const startOffset = dayOfWeek(firstDay, weekStartDay);
    gridStart.setDate(gridStart.getDate() - startOffset);

    const cells = [];
    const d = new Date(gridStart);
    for (let i = 0; i < 42; i++) {
      cells.push(new Date(d));
      d.setDate(d.getDate() + 1);
    }

    // DOW header
    const dowHeader = DOW.map(d => `<div class="qtr-dow">${d}</div>`).join('');

    // Rows
    let rowsHtml = '';
    for (let row = 0; row < 6; row++) {
      for (let col = 0; col < 7; col++) {
        const cell = cells[row * 7 + col];
        const key = dateKey(cell);
        const cellEvs = evMap[key] || [];

        const isOther   = cell.getMonth() !== month;
        const todayCls  = isToday(cell)          ? 'today'    : '';
        const otherCls  = isOther                ? 'other-month' : '';
        const selCls    = isSameDay(cell, currentDate) && !isToday(cell) ? 'selected' : '';

        // Up to 3 event dots
        const dots = cellEvs.slice(0, 3).map(ev => {
          const color = ev.color || ev.calendarColor || '#4285f4';
          const pastCls = isPast(ev) ? 'past' : '';
          return `<span class="qtr-dot ${pastCls}" style="background:${color}" title="${escAttr(ev.title)}" data-id="${ev.id}" data-url="${escAttr(ev.url || '')}"></span>`;
        }).join('');
        const moreDot = cellEvs.length > 3
          ? `<span class="qtr-dot-more">+${cellEvs.length - 3}</span>`
          : '';

        rowsHtml += `<div class="qtr-cell ${todayCls} ${otherCls} ${selCls}" data-date="${key}">
          <div class="qtr-day-num">${cell.getDate()}</div>
          <div class="qtr-dots">${dots}${moreDot}</div>
        </div>`;
      }
    }

    return `<div class="qtr-month">
      <div class="qtr-month-name">${MONTHS[month]}</div>
      <div class="qtr-month-grid">
        <div class="qtr-header">${dowHeader}</div>
        <div class="qtr-cells">${rowsHtml}</div>
      </div>
    </div>`;
  }).join('');

  container.innerHTML = `<div class="quarter-view">${monthsHtml}</div>`;

  // Click handlers
  container.querySelectorAll('.qtr-cell').forEach(cell => {
    cell.addEventListener('click', e => {
      // Check if a dot was clicked
      const dot = e.target.closest('.qtr-dot');
      if (dot) {
        e.stopPropagation();
        const ev = events.find(ev => ev.id === dot.dataset.id && ev.url === dot.dataset.url);
        if (ev) { onEventClick(ev, dot); return; }
      }
      onDayClick(new Date(cell.dataset.date + 'T00:00:00'));
    });
  });
}

function dateKey(d) {
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
}

function escAttr(s) {
  return String(s).replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}
