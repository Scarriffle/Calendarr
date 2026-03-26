import { api } from './api.js';
import { initCalendar, showToast } from './calendar.js';

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

  // Logout on avatar click (simple UX)
  avatar.addEventListener('click', () => {
    if (confirm('Abmelden?')) {
      localStorage.removeItem('token');
      localStorage.removeItem('user');
      window.location.reload();
    }
  });

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
  document.getElementById('login-form').addEventListener('submit', async e => {
    e.preventDefault();
    const username = document.getElementById('login-username').value.trim();
    const password = document.getElementById('login-password').value;
    const errEl    = document.getElementById('login-error');
    errEl.classList.add('hidden');

    try {
      const res = await api.login(username, password);
      localStorage.setItem('token', res.access_token);
      localStorage.setItem('user', JSON.stringify(res.user));
      await launchApp();
    } catch (err) {
      errEl.textContent = err.message;
      errEl.classList.remove('hidden');
    }
  });
}

// ── Start ─────────────────────────────────────────────────
boot();
