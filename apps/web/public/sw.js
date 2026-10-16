/* global caches, self, clients */
// Service Worker for LogYourBody PWA
const CACHE_PREFIX = 'logyourbody-';
const CACHE_NAME = `${CACHE_PREFIX}v3`;
const OFFLINE_PAGE = '/offline.html';

// Files to cache for offline use (only critical assets)
const urlsToCache = [
  OFFLINE_PAGE,
  '/site.webmanifest',
  '/favicon.ico',
  '/android-chrome-192x192.png',
  '/android-chrome-512x512.png',
  '/apple-touch-icon.png',
];

// Cache only explicitly public files. Never persist account HTML, API data,
// private photos, or URLs carrying query credentials in the Cache API.
function isPublicAsset(request, url) {
  return (
    !url.search &&
    !request.headers.has('authorization') &&
    request.cache !== 'no-store' &&
    (urlsToCache.includes(url.pathname) || url.pathname.startsWith('/_next/static/'))
  );
}

function canCache(response) {
  const policy = response.headers.get('cache-control') || '';
  const vary = response.headers.get('vary') || '';
  return (
    response.status === 200 &&
    !response.redirected &&
    (response.type === 'basic' || response.type === 'default') &&
    !/(?:^|,)\s*(?:private|no-store|no-cache)(?:\s*(?:=|,|$))/i.test(policy) &&
    !vary
      .split(',')
      .some((header) => ['*', 'cookie', 'authorization'].includes(header.trim().toLowerCase()))
  );
}

async function cachedPublicAsset(request) {
  try {
    const cache = await caches.open(CACHE_NAME);
    return await cache.match(request);
  } catch {
    return undefined;
  }
}

async function fetchPublicAsset(request) {
  const response = await fetch(request, { credentials: 'omit' });
  if (canCache(response)) {
    try {
      const cache = await caches.open(CACHE_NAME);
      await cache.put(request, response.clone());
    } catch {
      // Storage may be unavailable or full; the network response is still valid.
    }
  }
  return response;
}

// Install event - cache the public offline shell and icons without cookies.
self.addEventListener('install', (event) => {
  event.waitUntil(
    Promise.all(urlsToCache.map((url) => fetchPublicAsset(url))).then(() => self.skipWaiting()),
  );
});

// Activate event - clean up old caches
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((cacheNames) => {
        return Promise.all(
          cacheNames.map((cacheName) => {
            // v1/v2 may contain private responses. Purge them, preserving caches
            // belonging to other applications on this origin.
            if (cacheName.startsWith(CACHE_PREFIX) && cacheName !== CACHE_NAME) {
              return caches.delete(cacheName);
            }
          }),
        );
      })
      .then(() => self.clients.claim()),
  );
});

// Navigation stays network-only, with a generic offline fallback. APIs and
// all other dynamic requests remain entirely under the browser's network path.
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // Skip non-GET requests
  if (request.method !== 'GET') return;

  // Skip cross-origin requests
  if (url.origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request).catch(
        async () =>
          (await cachedPublicAsset(OFFLINE_PAGE)) ||
          new Response('You are offline.', {
            status: 503,
            headers: { 'Content-Type': 'text/plain', 'Cache-Control': 'no-store' },
          }),
      ),
    );
    return;
  }

  if (!isPublicAsset(request, url)) return;
  const response = cachedPublicAsset(request).then((cached) => cached || fetchPublicAsset(request));
  event.respondWith(response);
  event.waitUntil(
    response.then(
      () => undefined,
      () => undefined,
    ),
  );
});

// Check for updates periodically
self.addEventListener('message', (event) => {
  if (event.origin !== self.location.origin) return;
  if (event.data && event.data.type === 'SKIP_WAITING') {
    event.waitUntil(self.skipWaiting());
  }

  if (event.data && event.data.type === 'CHECK_UPDATE') {
    // Force check for updates
    event.waitUntil(self.registration.update());
  }
});

// Handle push notifications
self.addEventListener('push', (event) => {
  const options = {
    body: event.data ? event.data.text() : 'New update available',
    icon: '/android-chrome-192x192.png',
    badge: '/android-chrome-192x192.png',
    vibrate: [100, 50, 100],
    data: {
      dateOfArrival: Date.now(),
      primaryKey: 1,
    },
  };

  event.waitUntil(self.registration.showNotification('LogYourBody', options));
});

// Handle notification clicks
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(clients.openWindow('/'));
});
