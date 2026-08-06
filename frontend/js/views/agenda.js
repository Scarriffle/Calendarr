import { isPast, eventTitle, birthdayIconSvg } from '../utils.js';
import { t, getLocale } from '../i18n.js';

export function renderAgenda(container, currentDate, events, onEventClick) {
  if (!events.length) {
    container.innerHTML = `<div class="agenda-view"><div class="agenda-empty">${t('no_events')}</div></div>`;
    return;
  }

  // Group events by date
  const groups = {};
  events.forEach(ev => {
    const d = new Date(ev.start);
    const key = `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
    if (!groups[key]) groups[key] = [];
    groups[key].push(ev);
  });

  // Sort groups
  const sortedKeys = Object.keys(groups).sort();

  const html = sortedKeys.map(key => {
    const date = new Date(key + 'T00:00:00');
    const isToday = isTodayDate(date);
    const todayCls = isToday ? 'today' : '';

    const evHtml = groups[key]
      .sort((a, b) => {
        if (a.allDay && !b.allDay) return -1;
        if (!a.allDay && b.allDay) return 1;
        return new Date(a.start) - new Date(b.start);
      })
      .map(ev => {
        const color = ev.color || ev.calendarColor || '#4285f4';
        const pastCls = isPast(ev) ? 'past' : '';
        let timeStr = t('allday_cap');
        if (!ev.allDay) {
          const s = new Date(ev.start);
          const e = new Date(ev.end);
          timeStr = `${fmtTime(s)} – ${fmtTime(e)}`;
        }
        const locHtml = ev.location
          ? `<span class="agenda-ev-meta"> · ${escHtml(ev.location)}</span>`
          : '';
        return `<div class="agenda-event ${pastCls}" data-id="${ev.id}" data-url="${escAttr(ev.url)}">
          <div class="agenda-ev-color" style="background:${color}"></div>
          <div class="agenda-ev-info">
            <div class="agenda-ev-title">${ev.is_birthday ? birthdayIconSvg() : ''}${escHtml(eventTitle(ev))}</div>
            <div class="agenda-ev-meta">${timeStr}${locHtml}</div>
          </div>
        </div>`;
      }).join('');

    return `<div class="agenda-day" data-date="${key}">
      <div class="agenda-date ${todayCls}">
        <div class="agenda-date-num">${date.getDate()}</div>
        <div class="agenda-date-label">
          <span class="wd">${t('days_long')[date.getDay()]}</span>
          <span class="mo">${t('months_short')[date.getMonth()]} ${date.getFullYear()}</span>
        </div>
      </div>
      ${evHtml}
    </div>`;
  }).join('');

  container.innerHTML = `<div class="agenda-view">${html}</div>`;

  // The agenda lists the whole cached range (past + future). Scroll so the
  // current date (e.g. "today" after the Today button) sits at the top — or
  // the next day with events if the current date itself has none.
  const scrollEl = container.querySelector('.agenda-view');
  if (scrollEl) {
    const curKey = `${currentDate.getFullYear()}-${String(currentDate.getMonth()+1).padStart(2,'0')}-${String(currentDate.getDate()).padStart(2,'0')}`;
    const days = [...scrollEl.querySelectorAll('.agenda-day')];
    const target = days.find(d => d.dataset.date >= curKey) || days[days.length - 1];
    if (target) {
      scrollEl.scrollTop += target.getBoundingClientRect().top - scrollEl.getBoundingClientRect().top;
    }
  }

  container.querySelectorAll('.agenda-event').forEach(el => {
    el.addEventListener('click', () => {
      const ev = events.find(ev => ev.id === el.dataset.id && ev.url === el.dataset.url);
      if (ev) onEventClick(ev, el);
    });
  });
}

function isTodayDate(d) {
  const now = new Date();
  return d.getFullYear() === now.getFullYear() &&
         d.getMonth()    === now.getMonth()    &&
         d.getDate()     === now.getDate();
}

function fmtTime(d) {
  return d.toLocaleTimeString(getLocale(), { hour: '2-digit', minute: '2-digit' });
}

function escHtml(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}
function escAttr(s) {
  return String(s).replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}
