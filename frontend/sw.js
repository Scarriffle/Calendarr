// Calendarr Service Worker — minimal-cache strategy
//
// Strategy: network-first for everything. The cache is only used as a
// last-resort fallback when offline (so the app shell still opens). This
// means every online request hits the network and respects the
// server's Cache-Control headers (≤ 2h for static assets, no-cache for
// the entry HTML / version files). New releases take effect on the next
// reload, no manual SW unregister required.

const CACHE_VERSION  = 'calendarr-v13';
const OFFLINE_SHELL  = ['/', '/index.html'];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then(cache =>
      Promise.all(OFFLINE_SHELL.map(url =>
        cache.add(url).catch(err => console.warn('[SW] skip', url, err))
      ))
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

  // API routes: always go to the network, no offline fallback (we'd just
  // be returning stale account/event data otherwise).
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

  // Everything else: network-first. The browser's HTTP cache (driven by
  // the server's Cache-Control headers) already throttles re-fetches —
  // the SW just makes sure offline still works for the entry HTML.
  event.respondWith(
    fetch(req).then(resp => {
      // Keep a fresh copy of navigation requests / index.html for offline
      const isNavigation = req.mode === 'navigate'
        || url.pathname === '/'
        || url.pathname === '/index.html';
      if (isNavigation && resp && resp.status === 200) {
        const clone = resp.clone();
        caches.open(CACHE_VERSION).then(c => c.put(req, clone)).catch(() => {});
      }
      return resp;
    }).catch(() => {
      // Offline fallback: only the HTML shell is served from cache, so the
      // app at least renders and can show its own offline UI.
      if (req.mode === 'navigate'
          || url.pathname === '/'
          || url.pathname === '/index.html') {
        return caches.match(req).then(c => c || caches.match('/index.html'));
      }
      return new Response('', { status: 503 });
    })
  );
});
