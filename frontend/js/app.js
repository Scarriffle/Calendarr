import { api } from './api.js';
import { initCalendar, showToast, openProfileModal } from './calendar.js';

// ── Bootstrap ─────────────────────────────────────────────
async function boot() {
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
    try {
      await api.get('/auth/me'); // validate token
      await launchApp();
      return;
    } catch (_) {
      localStorage.removeItem('token');
      localStorage.removeItem('user');
    }
  }

  showScreen('login');
  bindLoginForm();
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

  // Set user avatar initials
  const user = JSON.parse(localStorage.getItem('user') || '{}');
  const avatar = document.getElementById('user-avatar');
  if (user.username) {
    avatar.textContent = user.username[0].toUpperCase();
    avatar.title = user.username;
  }

  // User dropdown menu
  const dropdown = document.getElementById('user-dropdown');
  document.getElementById('dropdown-username').textContent = user.username || 'Benutzer';

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
      errEl.textContent = 'Passwörter stimmen nicht überein';
      errEl.classList.remove('hidden');
      return;
    }
    if (pw1.length < 6) {
      errEl.textContent = 'Passwort muss mindestens 6 Zeichen haben';
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
    const errEl    = document.getElementById('login-error');
    errEl.classList.add('hidden');

    try {
      const res = await api.login(username, password, totpCode);
      localStorage.setItem('token', res.access_token);
      localStorage.setItem('user', JSON.stringify(res.user));
      await launchApp();
    } catch (err) {
      if (err.message === '2fa_required') {
        totpRow.classList.remove('hidden');
        document.getElementById('login-totp').focus();
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
