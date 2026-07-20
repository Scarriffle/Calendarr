// Instance-wide branding + default theme (public GET /api/instance/). Loaded as
// early as possible so the login screen is already branded. See
// backend/routers/admin_router.py.

import { setInstanceDefaults } from './settings-sync.js';
import { setCustomFavicon, applyFavicon } from './utils.js';

export let instanceConfig = {};

// Cache the bundled default logo markup so "remove logo" can restore it.
const originalLogoHtml = {};

function setBrandLogo(url) {
  document.querySelectorAll('.topbar-logo, .auth-logo').forEach(el => {
    const key = el.classList.contains('topbar-logo') ? 'topbar' : 'auth';
    if (!(key in originalLogoHtml)) originalLogoHtml[key] = el.innerHTML;
    if (url) {
      const cls = key === 'topbar' ? 'topbar-logo-img' : 'auth-logo-img';
      el.innerHTML = `<img class="${cls}" src="${url}" alt="Logo">`;
    } else {
      el.innerHTML = originalLogoHtml[key];
    }
  });
}

export function applyInstanceBranding(cfg) {
  cfg = cfg || {};
  setInstanceDefaults(cfg.default_theme || {});
  setCustomFavicon(cfg.has_favicon ? cfg.favicon_url : null);
  setBrandLogo(cfg.has_logo ? cfg.logo_url : null);
  applyFavicon();  // no arg → uses instance/built-in primary as fallback
}

// Memoised so boot() and initCalendar() share a single fetch; callers can await
// it to guarantee instance defaults are set before the first applyTheme().
let loadPromise = null;
export function loadInstance() {
  if (loadPromise) return loadPromise;
  loadPromise = (async () => {
    try {
      const res = await fetch('/api/instance/', { headers: { Accept: 'application/json' } });
      instanceConfig = res.ok ? await res.json() : {};
    } catch (_) {
      instanceConfig = {};
    }
    applyInstanceBranding(instanceConfig);
    return instanceConfig;
  })();
  return loadPromise;
}

// Force a re-fetch (after an admin changes branding/theme).
export function reloadInstance() {
  loadPromise = null;
  return loadInstance();
}
