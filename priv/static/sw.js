// Ideajar service worker (slice 10).
//
// D2 strategy — cache static assets only. HTML pages and WebSocket
// connections are NOT intercepted. Phoenix LiveView is WebSocket-driven,
// so caching the root HTML brings no benefit (the WS handshake is the
// real blocking step) and risks serving a stale shell after deploy.
//
// Cache invalidation: bump the CACHE_NAME suffix (v1 → v2 → …) every
// time PRECACHE_URLS changes or this file's logic changes. The activate
// handler then evicts every cache that does not match the new name.
// Manual policy — couple-2-user app, infrequent deploys. If you forget
// to bump, installed users keep the old shell until they manually
// reload.

const CACHE_NAME = "ideajar-static-v1"

const PRECACHE_URLS = [
  "/manifest.json",
  "/icons/icon-192.png",
  "/icons/icon-512.png"
]

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(PRECACHE_URLS))
      .then(() => self.skipWaiting())
  )
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))
      )
    ).then(() => self.clients.claim())
  )
})

// Fetch handler — cache-first for precached static assets, network
// fallthrough for everything else. Non-GET requests (POST for form
// submits, longpoll client→server frames) bypass entirely. The
// longpoll GET poll URL `/live/longpoll?…` falls through to network
// because it's not in PRECACHE_URLS — keep it that way, never add a
// /live/* cache rule.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return

  event.respondWith(
    caches.match(event.request).then((cached) => cached || fetch(event.request))
  )
})
