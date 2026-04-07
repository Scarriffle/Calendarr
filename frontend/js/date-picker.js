/**
 * Custom dark date/time picker
 * openDatePicker(anchor, value, mode) → Promise<string|null>
 *   anchor : DOM element to position near
 *   value  : ISO string ("YYYY-MM-DDTHH:MM" | "YYYY-MM-DD") or ""
 *   mode   : 'datetime' | 'date'
 */
import { t } from './i18n.js';

const ITEM_H  = 40;  // px per scroll item
const VISIBLE = 3;   // visible items in time scroller

export function openDatePicker(anchor, value, mode = 'datetime') {
  return new Promise(resolve => {
    // ── Parse initial value ───────────────────────────────
    let selDate = new Date();
    selDate.setHours(0, 0, 0, 0);
    let selHour = selDate.getHours();
    let selMin  = 0;

    if (value) {
      try {
        const raw = mode === 'datetime'
          ? value.replace(' ', 'T')
          : value + 'T00:00:00';
        const d = new Date(raw);
        if (!isNaN(d)) {
          selDate = new Date(d.getFullYear(), d.getMonth(), d.getDate());
          if (mode === 'datetime') { selHour = d.getHours(); selMin = d.getMinutes(); }
        }
      } catch (_) {}
    }

    let viewYear  = selDate.getFullYear();
    let viewMonth = selDate.getMonth();

    // ── Build DOM ─────────────────────────────────────────
    const overlay = document.createElement('div');
    overlay.className = 'dtp-overlay';
    document.body.appendChild(overlay);

    const card = document.createElement('div');
    card.className = 'dtp-card';
    overlay.appendChild(card);

    function done(result) {
      overlay.remove();
      resolve(result);
    }

    // Click outside → cancel
    overlay.addEventListener('mousedown', e => {
      if (e.target === overlay) done(null);
    });

    // ── Calendar builder ──────────────────────────────────
    function buildCalendar() {
      const months  = t('months');
      const dowKeys = t('dow_monday'); // always Monday-first in calendar

      const firstDay  = new Date(viewYear, viewMonth, 1);
      const gridStart = new Date(firstDay);
      let dow = firstDay.getDay();
      dow = dow === 0 ? 6 : dow - 1; // 0=Mon…6=Sun
      gridStart.setDate(gridStart.getDate() - dow);

      const cells = [];
      const iter  = new Date(gridStart);
      for (let i = 0; i < 42; i++) {
        cells.push(new Date(iter));
        iter.setDate(iter.getDate() + 1);
      }

      const today = new Date(); today.setHours(0, 0, 0, 0);

      const dowHtml  = dowKeys.map(d => `<div class="dtp-dow">${d}</div>`).join('');
      const daysHtml = cells.map(cell => {
        const isOther    = cell.getMonth() !== viewMonth;
        const isToday    = cell.getTime() === today.getTime();
        const isSelected = cell.getTime() === selDate.getTime();
        let cls = 'dtp-day';
        if (isOther)    cls += ' other';
        if (isToday)    cls += ' today';
        if (isSelected) cls += ' selected';
        return `<div class="${cls}" data-ts="${cell.getTime()}">${cell.getDate()}</div>`;
      }).join('');

      return `<div class="dtp-cal-header">
        <button class="dtp-nav-btn" id="dtp-prev">&#8249;</button>
        <span class="dtp-month-label">${months[viewMonth]} ${viewYear}</span>
        <button class="dtp-nav-btn" id="dtp-next">&#8250;</button>
      </div>
      <div class="dtp-grid">
        ${dowHtml}
        ${daysHtml}
      </div>`;
    }

    // ── Time scroll builder ───────────────────────────────
    function buildTime() {
      if (mode !== 'datetime') return '';
      const hItems = Array.from({ length: 24 }, (_, i) =>
        `<div class="dtp-ti" data-val="${i}">${String(i).padStart(2,'0')}</div>`
      ).join('');
      const mItems = Array.from({ length: 60 }, (_, i) =>
        `<div class="dtp-ti" data-val="${i}">${String(i).padStart(2,'0')}</div>`
      ).join('');
      return `<div class="dtp-time-row">
        <div class="dtp-tc-wrap">
          <div class="dtp-tc" id="dtp-h">${hItems}</div>
        </div>
        <div class="dtp-colon">:</div>
        <div class="dtp-tc-wrap">
          <div class="dtp-tc" id="dtp-m">${mItems}</div>
        </div>
      </div>`;
    }

    // ── Render ────────────────────────────────────────────
    function render() {
      card.innerHTML =
        buildCalendar() +
        buildTime() +
        `<div class="dtp-actions">
          <button class="btn btn-ghost btn-sm" id="dtp-cancel">${t('cancel')}</button>
          <button class="btn btn-primary btn-sm" id="dtp-ok">${t('save')}</button>
        </div>`;

      bindEvents();
      if (mode === 'datetime') initScrollers();
      positionCard();
    }

    // ── Event bindings ────────────────────────────────────
    function bindEvents() {
      card.querySelector('#dtp-prev').onclick = () => {
        viewMonth--;
        if (viewMonth < 0) { viewMonth = 11; viewYear--; }
        render();
      };
      card.querySelector('#dtp-next').onclick = () => {
        viewMonth++;
        if (viewMonth > 11) { viewMonth = 0; viewYear++; }
        render();
      };

      // Day click
      card.querySelectorAll('.dtp-day').forEach(el => {
        el.addEventListener('click', () => {
          selDate = new Date(parseInt(el.dataset.ts));
          if (el.classList.contains('other')) {
            viewYear  = selDate.getFullYear();
            viewMonth = selDate.getMonth();
          }
          render();
        });
      });

      card.querySelector('#dtp-cancel').onclick = () => done(null);
      card.querySelector('#dtp-ok').onclick = () => done(buildResult());
    }

    // ── Time scroll initialisation ────────────────────────
    function initScrollers() {
      const hCol = card.querySelector('#dtp-h');
      const mCol = card.querySelector('#dtp-m');
      if (!hCol || !mCol) return;

      // Scroll to selected value (padding-top = ITEM_H, so scrollTop = val * ITEM_H)
      hCol.scrollTop = selHour * ITEM_H;
      mCol.scrollTop = selMin  * ITEM_H;
      highlightItems(hCol, selHour);
      highlightItems(mCol, selMin);

      let hTimer, mTimer;

      hCol.addEventListener('scroll', () => {
        clearTimeout(hTimer);
        hTimer = setTimeout(() => {
          selHour = Math.max(0, Math.min(23, Math.round(hCol.scrollTop / ITEM_H)));
          hCol.scrollTop = selHour * ITEM_H;
          highlightItems(hCol, selHour);
        }, 80);
      });

      mCol.addEventListener('scroll', () => {
        clearTimeout(mTimer);
        mTimer = setTimeout(() => {
          selMin = Math.max(0, Math.min(59, Math.round(mCol.scrollTop / ITEM_H)));
          mCol.scrollTop = selMin * ITEM_H;
          highlightItems(mCol, selMin);
        }, 80);
      });

      // Click item to select
      hCol.querySelectorAll('.dtp-ti').forEach((el, i) => {
        el.addEventListener('click', () => {
          selHour = i;
          hCol.scrollTo({ top: i * ITEM_H, behavior: 'smooth' });
          highlightItems(hCol, i);
        });
      });
      mCol.querySelectorAll('.dtp-ti').forEach((el, i) => {
        el.addEventListener('click', () => {
          selMin = i;
          mCol.scrollTo({ top: i * ITEM_H, behavior: 'smooth' });
          highlightItems(mCol, i);
        });
      });
    }

    function highlightItems(col, val) {
      col.querySelectorAll('.dtp-ti').forEach((el, i) => {
        el.classList.toggle('selected', i === val);
      });
    }

    // ── Result builder ────────────────────────────────────
    function buildResult() {
      const y  = selDate.getFullYear();
      const mo = String(selDate.getMonth() + 1).padStart(2, '0');
      const dd = String(selDate.getDate()).padStart(2, '0');
      if (mode === 'date') return `${y}-${mo}-${dd}`;
      const h  = String(selHour).padStart(2, '0');
      const mi = String(selMin).padStart(2, '0');
      return `${y}-${mo}-${dd}T${h}:${mi}`;
    }

    // ── Positioning ───────────────────────────────────────
    function positionCard() {
      const r  = anchor.getBoundingClientRect();
      const cw = card.offsetWidth  || 280;
      const ch = card.offsetHeight || 420;
      let left = r.left;
      let top  = r.bottom + 6;
      if (left + cw > window.innerWidth  - 8) left = window.innerWidth  - cw - 8;
      if (top  + ch > window.innerHeight - 8) top  = r.top - ch - 6;
      if (left < 8) left = 8;
      if (top  < 8) top  = 8;
      card.style.left = left + 'px';
      card.style.top  = top  + 'px';
    }

    render();
  });
}

/**
 * Format an ISO value for display in the UI
 * mode: 'datetime' | 'date'
 * lang: 'de' | 'en'
 */
export function formatDtDisplay(isoStr, mode, lang = 'de') {
  if (!isoStr) return '—';
  try {
    const d = mode === 'datetime'
      ? new Date(isoStr.replace(' ', 'T'))
      : new Date(isoStr + 'T00:00:00');
    if (isNaN(d)) return isoStr;
    const locale = lang === 'en' ? 'en-GB' : 'de-CH';
    if (mode === 'datetime') {
      return d.toLocaleString(locale, {
        day: '2-digit', month: '2-digit', year: 'numeric',
        hour: '2-digit', minute: '2-digit', hour12: false,
      });
    }
    return d.toLocaleDateString(locale, {
      day: '2-digit', month: '2-digit', year: 'numeric',
    });
  } catch (_) { return isoStr; }
}
