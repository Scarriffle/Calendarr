import { formatDate, isSameDay, isToday, isPast, dayOfWeek, getISOWeekNumber } from '../utils.js';

const DOW_MONDAY = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const DOW_SUNDAY = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];

export function renderMonth(container, currentDate, events, onDayClick, onEventClick, weekStartDay = 'monday') {
  const year = currentDate.getFullYear();
  const month = currentDate.getMonth();
  const DOW = weekStartDay === 'sunday' ? DOW_SUNDAY : DOW_MONDAY;

  const firstDay = new Date(year, month, 1);
  const lastDay  = new Date(year, month + 1, 0);

  // Start grid on the correct weekday
  const gridStart = new Date(firstDay);
  const offset = dayOfWeek(firstDay, weekStartDay);
  gridStart.setDate(gridStart.getDate() - offset);

  const cells = [];
  const d = new Date(gridStart);
  for (let i = 0; i < 42; i++) {
    cells.push(new Date(d));
    d.setDate(d.getDate() + 1);
  }

  // Build event map keyed by date string
  const evMap = {};
  events.forEach(ev => {
    const s = new Date(ev.start);
    const e = ev.allDay ? new Date(ev.end) : new Date(ev.end);
    // Spread multi-day events across cells
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

  // Header: KW-Spalte + Wochentage
  const headerHtml = `<div class="month-kw-header">KW</div>` +
    DOW.map(d => `<div class="month-dow">${d}</div>`).join('');

  // Build rows (6 weeks × 7 days)
  let cellsHtml = '';
  for (let row = 0; row < 6; row++) {
    // KW cell for the first day of this row
    const rowFirstDay = cells[row * 7];
    const kw = getISOWeekNumber(rowFirstDay);
    cellsHtml += `<div class="month-kw-cell">${kw}</div>`;

    for (let col = 0; col < 7; col++) {
      const cell = cells[row * 7 + col];
      const key = dateKey(cell);
      const cellEvs = (evMap[key] || []).slice().sort((a, b) => {
        if (a.allDay && !b.allDay) return -1;
        if (!a.allDay && b.allDay) return 1;
        return new Date(a.start) - new Date(b.start);
      });

      const isOther = cell.getMonth() !== month;
      const todayClass = isToday(cell) ? 'today' : '';
      const otherClass = isOther ? 'other-month' : '';
      const numClass = isToday(cell) ? 'today' : '';

      const MAX_VISIBLE = 3;
      const visible = cellEvs.slice(0, MAX_VISIBLE);
      const hiddenCount = cellEvs.length - MAX_VISIBLE;

      const evHtml = visible.map(ev => {
        const color = ev.color || ev.calendarColor || '#4285f4';
        const pastClass = isPast(ev) ? 'past' : '';
        const title = ev.allDay ? ev.title : `${fmtTime(new Date(ev.start))} ${ev.title}`;
        return `<div class="month-event ${pastClass}" data-id="${ev.id}" data-url="${escAttr(ev.url)}"
          style="background:${color};color:#fff"
          title="${escAttr(ev.title)}">${escHtml(title)}</div>`;
      }).join('');

      const moreHtml = hiddenCount > 0
        ? `<div class="month-more" data-date="${key}">+${hiddenCount} weitere</div>`
        : '';

      cellsHtml += `<div class="month-cell ${todayClass} ${otherClass}" data-date="${key}">
        <div class="cell-day ${numClass}">${cell.getDate()}</div>
        ${evHtml}${moreHtml}
      </div>`;
    }
  }

  container.innerHTML = `<div class="month-view">
    <div class="month-header">${headerHtml}</div>
    <div class="month-grid">${cellsHtml}</div>
  </div>`;

  // Events
  container.querySelectorAll('.month-cell').forEach(cell => {
    cell.addEventListener('click', e => {
      const evEl = e.target.closest('.month-event');
      if (evEl) {
        e.stopPropagation();
        const ev = events.find(ev => ev.id === evEl.dataset.id && ev.url === evEl.dataset.url);
        if (ev) onEventClick(ev, evEl);
        return;
      }
      const moreEl = e.target.closest('.month-more');
      if (moreEl) {
        e.stopPropagation();
        onDayClick(new Date(moreEl.dataset.date + 'T00:00:00'));
        return;
      }
      onDayClick(new Date(cell.dataset.date + 'T00:00:00'));
    });
  });
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
