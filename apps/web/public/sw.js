// Service Worker for LogYourBody PWA
const CACHE_NAME = 'logyourbody-v2'; // Increment version to force update
const OFFLINE_PAGE = '/offline.html';

// Files to cache for offline use (only critical assets)
const urlsToCache = [
  OFFLINE_PAGE,
  '/site.webmanifest',
  '/favicon.ico',
  '/android-chrome-192x192.png',
  '/android-chrome-512x512.png',
  '/apple-touch-icon.png'
];

// Install event - cache essential files
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => {
        console.log('Opened cache');
        return cache.addAll(urlsToCache);
      })
  );
  // Force the waiting service worker to become the active service worker
  self.skipWaiting();
});

// Activate event - clean up old caches
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (cacheName !== CACHE_NAME) {
            console.log('Deleting old cache:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
  // Claim all clients to ensure the new service worker takes effect immediately
  self.clients.claim();
});

// Fetch event - Network First strategy for HTML, Cache First for assets
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // Skip non-GET requests
  if (request.method !== 'GET') return;

  // Skip cross-origin requests
  if (!url.origin.includes(self.location.origin)) return;

  // Network First for HTML/API requests (always get fresh content)
  if (request.mode === 'navigate' || 
      request.headers.get('accept')?.includes('text/html') ||
      url.pathname.startsWith('/api/')) {
    event.respondWith(
      fetch(request)
        .then(response => {
          // Clone the response before using it
          const responseToCache = response.clone();
          
          // Update cache in the background
          caches.open(CACHE_NAME).then(cache => {
            cache.put(request, responseToCache);
          });
          
          return response;
        })
        .catch(() => {
          // If network fails, try cache
          return caches.match(request).then(response => {
            return response || caches.match(OFFLINE_PAGE);
          });
        })
    );
    return;
  }

  // Cache First for static assets (images, CSS, JS)
  if (url.pathname.match(/\.(js|css|png|jpg|jpeg|svg|ico|webp|woff2?)$/)) {
    event.respondWith(
      caches.match(request)
        .then(response => {
          if (response) {
            // Return cached version and update cache in background
            const fetchPromise = fetch(request).then(networkResponse => {
              caches.open(CACHE_NAME).then(cache => {
                cache.put(request, networkResponse.clone());
              });
              return networkResponse;
            });
            
            return response;
          }
          
          // Not in cache, fetch from network
          return fetch(request).then(response => {
            const responseToCache = response.clone();
            caches.open(CACHE_NAME).then(cache => {
              cache.put(request, responseToCache);
            });
            return response;
          });
        })
    );
    return;
  }

  // Default: Network First
  event.respondWith(
    fetch(request).catch(() => caches.match(request))
  );
});

// Check for updates periodically
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
  
  if (event.data && event.data.type === 'CHECK_UPDATE') {
    // Force check for updates
    self.registration.update();
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
      primaryKey: 1
    }
  };

  event.waitUntil(
    self.registration.showNotification('LogYourBody', options)
  );
});

// Handle notification clicks
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.openWindow('/')
  );
});