import { api } from './api.js';
import { initCalendar, showToast, openProfileModal } from './calendar.js';
import { t } from './i18n.js';
import { loadInstance } from './instance.js';

// ── Single Sign-On ────────────────────────────────────────
// Error slug from a failed SSO round-trip, shown once the login screen is up.
let ssoErrorSlug = null;
// True when an SSO identity is parked server-side, waiting to be linked to
// whichever account the user signs into next.
let ssoLinkPending = false;

/**
 * Handle the return leg of an OIDC login.
 *
 * The callback redirected us to /?sso=1 with the access token in a one-time
 * HttpOnly cookie; trade it for the token here. Returns true when the user is
 * now logged in. Must run before the setup/token checks in boot().
 */
async function consumeSsoHandoff() {
  const params = new URLSearchParams(window.location.search);
  const ok   = params.has('sso');
  const err  = params.get('sso_error');
  const link = params.has('sso_link');
  if (!ok && !err && !link) return false;      // normal load — zero cost

  // Strip the marker before awaiting anything: a reload mid-flight must not
  // try to redeem a cookie that has already been spent.
  window.history.replaceState({}, '', window.location.pathname + window.location.hash);

  if (link) { ssoLinkPending = true; return false; }
  if (err) { ssoErrorSlug = err; return false; }

  try {
    const res = await api.oidcComplete();
    if (!res || !res.access_token) { ssoErrorSlug = 'generic'; return false; }
    localStorage.setItem('token', res.access_token);
    localStorage.setItem('user', JSON.stringify(res.user));
    return true;
  } catch (e) {
    ssoErrorSlug = 'generic';
    return false;
  }
}

/** Render one button per configured provider on the login screen. */
async function renderSsoButtons() {
  const block = document.getElementById('sso-block');
  const list  = document.getElementById('sso-buttons');
  if (!block || !list) return;

  if (ssoLinkPending) {
    const hintEl = document.getElementById('login-hint');
    if (hintEl) {
      hintEl.textContent = t('sso_link_prompt');
      hintEl.classList.remove('hidden');
    }
  }

  if (ssoErrorSlug) {
    const errEl = document.getElementById('login-error');
    if (errEl) {
      // Backend slugs come in both shapes: policy refusals are prefixed
      // ("oidc_account_not_linked"), flow errors are not ("state_mismatch").
      const bare = ssoErrorSlug.replace(/^oidc_/, '');
      const msg = [`sso_err_${ssoErrorSlug}`, `sso_err_${bare}`]
        .map(k => [k, t(k)])
        .find(([k, v]) => v !== k);
      // An unmapped slug still has to be diagnosable — showing only the
      // generic text hides the one piece of information that identifies the
      // fault.
      errEl.textContent = msg ? msg[1] : `${t('sso_err_generic')} (${ssoErrorSlug})`;
      errEl.classList.remove('hidden');
    }
    ssoErrorSlug = null;
  }

  let cfg;
  try {
    cfg = await api.oidcProviders();
  } catch (e) {
    return;                                    // SSO unreachable → password only
  }
  if (!cfg || !cfg.enabled || !cfg.providers.length) return;

  list.innerHTML = '';
  for (const p of cfg.providers) {
    const a = document.createElement('a');
    a.className = 'btn btn-secondary btn-full sso-btn';
    // A real link, not fetch(): /start answers 302 to the identity provider and
    // needs a top-level navigation to follow it and to set the flow cookie.
    a.href = p.start_url;
    a.textContent = `${p.icon ? p.icon + ' ' : ''}${t('sso_login_with', { name: p.name })}`;
    list.appendChild(a);
  }
  const divider = block.querySelector('.auth-divider');
  if (divider) divider.textContent = t('sso_or');
  block.classList.remove('hidden');
}

// ── Bootstrap ─────────────────────────────────────────────
async function boot() {
  // Apply instance branding (logo/favicon/default theme) ASAP so the login and
  // setup screens are already branded. Public endpoint — no token needed.
  loadInstance();

  // Returning from an SSO login? That has to be settled before anything else,
  // because we arrive unauthenticated with a one-time cookie in hand.
  if (await consumeSsoHandoff()) {
    await launchApp();
    return;
  }

  // Check if setup is required
  let setupRequired = false;
  try {
    const res = await api.setupRequired();
    setupRequired = res.required;
  } catch (e) {
    showScreen('login');
    return;
  }

  if (setupRequired) {
    showScreen('setup');
    bindSetupForm();
    return;
  }

  // Check if already logged in
  const token = localStorage.getItem('token');
  if (token) {
    let authed = false;
    try {
      await api.get('/auth/me'); // validate the TOKEN only
      authed = true;
    } catch (_) {
      // The token is genuinely invalid/expired — clear it and show login.
      localStorage.removeItem('token');
      localStorage.removeItem('user');
    }
    if (authed) {
      // Token is valid → stay logged in. launchApp() runs OUTSIDE the auth
      // try/catch on purpose: a later data/render error inside app init must
      // never bounce a validly-authenticated user back to the login screen
      // (that was the "logged out on every reload" bug).
      await launchApp();
      return;
    }
  }

  showScreen('login');
  bindLoginForm();
  renderSsoButtons();
}

function showScreen(name) {
  document.getElementById('screen-setup').classList.add('hidden');
  document.getElementById('screen-login').classList.add('hidden');
  document.getElementById('app').classList.add('hidden');

  if (name === 'setup') document.getElementById('screen-setup').classList.remove('hidden');
  else if (name === 'login') document.getElementById('screen-login').classList.remove('hidden');
  else if (name === 'app') document.getElementById('app').classList.remove('hidden');
}

async function launchApp() {
  showScreen('app');

  // Confirm a linking that happened during this login.
  const linkedName = sessionStorage.getItem('ssoLinkedName');
  if (linkedName !== null) {
    sessionStorage.removeItem('ssoLinkedName');
    showToast(t('sso_linked_toast', { name: linkedName }));
  }

  // Set user avatar initials
  const user = JSON.parse(localStorage.getItem('user') || '{}');
  const avatar = document.getElementById('user-avatar');
  if (user.username) {
    avatar.textContent = user.username[0].toUpperCase();
    avatar.title = user.username;
  }

  // User dropdown menu
  const dropdown = document.getElementById('user-dropdown');
  document.getElementById('dropdown-username').textContent = user.display_name || user.username || 'Benutzer';

  avatar.addEventListener('click', e => {
    e.stopPropagation();
    dropdown.classList.toggle('hidden');
  });

  document.addEventListener('click', e => {
    if (!dropdown.contains(e.target) && !avatar.contains(e.target)) {
      dropdown.classList.add('hidden');
    }
  });

  document.getElementById('btn-profile').addEventListener('click', () => {
    dropdown.classList.add('hidden');
    openProfileModal();
  });

  document.getElementById('btn-logout').addEventListener('click', () => {
    localStorage.removeItem('token');
    localStorage.removeItem('user');
    window.location.reload();
  });

  // Load avatar image if available
  try {
    const me = await api.get('/auth/me');
    // Store extended user info
    localStorage.setItem('user', JSON.stringify({ ...user, ...me }));
    if (me.has_avatar) {
      loadAvatarImage(avatar, user.username);
    }
  } catch (_) {}

  await initCalendar();
}

// ── Setup Form ────────────────────────────────────────────
function bindSetupForm() {
  document.getElementById('setup-form').addEventListener('submit', async e => {
    e.preventDefault();
    const username = document.getElementById('setup-username').value.trim();
    const email    = document.getElementById('setup-email').value.trim() || null;
    const pw1      = document.getElementById('setup-password').value;
    const pw2      = document.getElementById('setup-password2').value;
    const errEl    = document.getElementById('setup-error');

    errEl.classList.add('hidden');

    if (pw1 !== pw2) {
      errEl.textContent = t('setup_pw_mismatch');
      errEl.classList.remove('hidden');
      return;
    }
    if (pw1.length < 6) {
      errEl.textContent = t('setup_pw_short');
      errEl.classList.remove('hidden');
      return;
    }

    try {
      const res = await api.setup({ username, email, password: pw1 });
      localStorage.setItem('token', res.access_token);
      localStorage.setItem('user', JSON.stringify(res.user));
      await launchApp();
    } catch (err) {
      errEl.textContent = err.message;
      errEl.classList.remove('hidden');
    }
  });
}

// ── Login Form ────────────────────────────────────────────
function bindLoginForm() {
  const totpRow = document.getElementById('login-totp-row');

  document.getElementById('login-form').addEventListener('submit', async e => {
    e.preventDefault();
    const username = document.getElementById('login-username').value.trim();
    const password = document.getElementById('login-password').value;
    const totpCode = document.getElementById('login-totp')?.value.trim() || null;
    const remember = document.getElementById('login-remember')?.checked || false;
    const errEl    = document.getElementById('login-error');
    errEl.classList.add('hidden');

    try {
      const res = await api.login(username, password, totpCode, remember);
      localStorage.setItem('token', res.access_token);
      localStorage.setItem('user', JSON.stringify(res.user));
      // A parked SSO identity is attached to exactly the account that just
      // proved itself with a password — no email guesswork involved.
      if (ssoLinkPending) {
        ssoLinkPending = false;
        try {
          const linked = await api.oidcLinkPending();
          if (linked && linked.linked) {
            sessionStorage.setItem('ssoLinkedName', linked.name || '');
          }
        } catch (e) { /* linking is optional; the login itself succeeded */ }
      }
      await launchApp();
    } catch (err) {
      if (err.message === '2fa_required') {
        totpRow.classList.remove('hidden');
        // Focus only after the revealed row has been laid out. Password
        // managers position their inline icon from the field's bounding box at
        // the moment focus fires, and focusing in the same tick as the unhide
        // can hand them a stale rect. setTimeout rather than
        // requestAnimationFrame on purpose: rAF does not run in a backgrounded
        // tab, which would swallow the focus entirely.
        setTimeout(() => {
          window.dispatchEvent(new Event('resize'));  // nudge overlay repositioning
          document.getElementById('login-totp').focus();
        }, 0);
      } else {
        errEl.textContent = err.message;
        errEl.classList.remove('hidden');
      }
    }
  });
}

// ── Avatar Helper ────────────────────────────────────────
function loadAvatarImage(avatarEl, username) {
  const token = localStorage.getItem('token');
  fetch(`/api/profile/avatar?t=${Date.now()}`, {
    headers: token ? { 'Authorization': `Bearer ${token}` } : {}
  })
    .then(res => {
      if (!res.ok) throw new Error('No avatar');
      return res.blob();
    })
    .then(blob => {
      const img = new Image();
      img.onload = () => {
        avatarEl.innerHTML = '';
        img.style.cssText = 'width:100%;height:100%;object-fit:cover;position:absolute;inset:0';
        avatarEl.appendChild(img);
      };
      img.src = URL.createObjectURL(blob);
    })
    .catch(() => {
      avatarEl.innerHTML = '';
      avatarEl.textContent = (username || '?')[0].toUpperCase();
    });
}

// ── Start ─────────────────────────────────────────────────
boot();

// ── Service Worker registration (PWA) ─────────────────────
if ('serviceWorker' in navigator) {
  // Auto-update: when a new service worker takes control, reload once so the
  // page runs the fresh assets. Guarded so it never loops and never fires on
  // the very first install (when there was no previous controller).
  let refreshing = false;
  const hadController = !!navigator.serviceWorker.controller;
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (refreshing || !hadController) return;
    refreshing = true;
    window.location.reload();
  });

  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js', { scope: '/' }).then(reg => {
      // Check for a new SW now and hourly, so long-open tabs pick up releases.
      reg.update();
      setInterval(() => reg.update(), 60 * 60 * 1000);
    }).catch(err => {
      console.warn('SW registration failed:', err);
    });
  });
}
