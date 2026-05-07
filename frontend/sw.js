// Calendarr Service Worker
// Cache-first for static assets, network-first for /api/* (graceful offline)

const CACHE_VERSION = 'calendarr-v9';
const STATIC_ASSETS = [
  '/',
  '/index.html',
  '/manifest.json',
  '/static/css/app.css',
  '/static/favicon.svg',
  '/static/js/app.js',
  '/static/js/api.js',
  '/static/js/calendar.js',
  '/static/js/color-picker.js',
  '/static/js/date-picker.js',
  '/static/js/i18n.js',
  '/static/js/utils.js',
  '/static/js/version.js',
  '/static/js/views/agenda.js',
  '/static/js/views/month.js',
  '/static/js/views/quarter.js',
  '/static/js/views/week.js',
  '/icons/icon-192.png',
  '/icons/icon-512.png',
  '/icons/icon.svg',
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then(cache =>
      // Use addAll with a fallback so a single missing file doesn't abort install
      Promise.all(
        STATIC_ASSETS.map(url =>
          cache.add(url).catch(err => console.warn('[SW] skip', url, err))
        )
      )
    ).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_VERSION).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  // Network-first for API routes — fail silently if offline
  if (url.pathname.startsWith('/api/')) {
    event.respondWith(
      fetch(req).catch(() =>
        new Response(JSON.stringify({ offline: true }), {
          status: 503,
          headers: { 'Content-Type': 'application/json' },
        })
      )
    );
    return;
  }

  // Cache-first for everything else (static)
  event.respondWith(
    caches.match(req).then(cached => {
      if (cached) return cached;
      return fetch(req).then(resp => {
        // Only cache successful, basic-origin responses
        if (resp && resp.status === 200 && resp.type === 'basic') {
          const clone = resp.clone();
          caches.open(CACHE_VERSION).then(c => c.put(req, clone)).catch(() => {});
        }
        return resp;
      }).catch(() => {
        // Offline fallback for navigation requests
        if (req.mode === 'navigate') return caches.match('/index.html');
        return new Response('', { status: 503 });
      });
    })
  );
});
