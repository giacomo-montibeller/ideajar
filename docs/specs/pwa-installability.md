# Spec: PWA installability — manifest + service worker + icons

> Slice 10. Adds the three artifacts that turn ideajar into an
> installable Progressive Web App: a Web App Manifest at
> `/manifest.json`, a vanilla service worker at `/sw.js` that
> precaches static assets (D2 strategy), and two maskable PNG icons
> at `/icons/icon-192.png` + `/icons/icon-512.png`. Adds the
> `<link rel="manifest">` / `<meta name="theme-color">` /
> `<link rel="apple-touch-icon">` tags to the root layout and
> registers the SW from `app.js`. Static-files-only delivery — no
> controllers needed; the auth bypass for these paths already exists
> from commit `430e1d1`.

## Intent Description

Slice 10 chiude il primo dei due step ("PWA + deploy") che sbloccano
il rilascio agli utenti reali. L'obiettivo è **rendere ideajar
installabile** sulla home screen di iOS/Android come app standalone
(senza chrome del browser) e farla **caricare istantaneamente da
cache** la prossima volta — così su connessione mobile instabile lo
shell parte subito anche se la WebSocket impiega un attimo a
connettersi.

**Strategy "D2 — cache static assets"** (deciso pre-spec): il
service worker precaching solo gli asset statici **stable-path**
(manifest stesso, 2 PNG icons). I bundle CSS/JS Phoenix hanno
fingerprint nel nome (cache busting) e NON sono inclusi in
`PRECACHE_URLS` per evitare cache stale post-deploy — Plug.Static
serve le versioni fingerprintate fresh ad ogni connection, e il SW
fall-through-to-network funziona naturalmente per loro. Le HTML
pages NON sono cached perché Phoenix LiveView è WebSocket-driven —
cachare il root HTML non aiuta (la connessione WebSocket è il vero
blocking step) e rischia di servire shell stale dopo deploy. NO
offline fallback page, NO HTML precache, NO update prompts UX, NO
Workbox.

**Asset delivery via Plug.Static**: `manifest.json`, `sw.js`, e la
directory `icons/` sono già nei `static_paths/0` di `IdeajarWeb`
(commit `430e1d1` ha riservato i prefissi). Slice 10 popola
`priv/static/manifest.json`, `priv/static/sw.js`,
`priv/static/icons/icon-{192,512}.png`. Plug.Static serve i file con
content-type corretto (manifest → `application/json`, sw → `text/javascript`,
PNG → `image/png`).

**Auth bypass**: il commit `430e1d1` ha già garantito che i path
`/manifest.json`, `/sw.js`, `/icons/*` short-circuitano prima del
router e quindi prima della pipeline `:require_auth`. Slice 10 NON
modifica `lib/ideajar_web.ex` o il router.

**HTML root tags** in `lib/ideajar_web/components/layouts.ex` (root
layout `app/1` o equivalente):
- `<link rel="manifest" href="/manifest.json">`
- `<meta name="theme-color" content="#29d">`
- `<link rel="apple-touch-icon" href="/icons/icon-192.png">`

**SW registration** in `assets/js/app.js` (1 hook addEventListener al
load):
```js
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/sw.js")
  })
}
```

**Manifest content** (canonical):
```json
{
  "name": "Ideajar",
  "short_name": "Ideajar",
  "description": "Idee da fare insieme",
  "lang": "it",
  "dir": "ltr",
  "start_url": "/",
  "scope": "/",
  "display": "standalone",
  "theme_color": "#29d",
  "background_color": "#2299dd",
  "icons": [
    {
      "src": "/icons/icon-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "any maskable"
    },
    {
      "src": "/icons/icon-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any maskable"
    }
  ]
}
```

**Service worker source** (vanilla, no framework, ~40 LOC):
- `install` event: `caches.open(CACHE_NAME).then(cache => cache.addAll(PRECACHE_URLS))` con `self.skipWaiting()` per attivare subito
- `activate` event: cleanup vecchie versioni cache (qualunque non match `CACHE_NAME`) + `self.clients.claim()`
- `fetch` event:
  - Se request method ≠ GET → bypass (no cache)
  - Se URL è in PRECACHE_URLS → cache-first (cached response, fallback to network)
  - Altrimenti (HTML pages, API, WebSocket upgrades) → network-only (no caching, no fallback)
- `CACHE_NAME = "ideajar-static-v1"` — incremento manuale per cache bust

**Icons design**: sfondo solid `#29d`, lettera `I` bianca centrata, font sans-serif bold, occupa ~50% verticalmente (rispetta safe zone Android maskable 80%). Generate via shell script ImageMagick (committato in `priv/scripts/generate_icons.sh`) o equivalent — i PNG finali committati in `priv/static/icons/`. Identical design tra 192 e 512 — solo size differisce.

**Out of scope**:
- Push notifications, Background Sync, Periodic Sync, Web Share Target,
  File Handling, Shortcuts
- Custom splash screen (browser auto-genera da name + bg + icon)
- iOS-specific `apple-mobile-web-app-*` meta tags (apple-touch-icon
  è sufficiente per now)
- HTML shell precache, offline fallback page (D2 strategy)
- Update prompts UX, custom install prompt UX
- Workbox / Vite-plugin-pwa / qualsiasi framework SW
- HTTPS enforcement (production deploy slice 11 lo gestirà via Gigalixir)

## User-Facing Behavior

```gherkin
Feature: Installable Progressive Web App

  Background:
    Given the production server serves Phoenix Plug.Static for /manifest.json, /sw.js, /icons/*
    And the auth bypass for these paths is already in place (commit 430e1d1)

  # ── Static asset delivery ──────────────────────────────────────
  Scenario: GET /manifest.json returns the canonical manifest with HTTP 200
    When the browser requests "/manifest.json"
    Then the response status is 200
    And content-type is "application/json"
    And the body is valid JSON
    And the body contains "name": "Ideajar"
    And the body contains "short_name": "Ideajar"
    And the body contains "start_url": "/"
    And the body contains "scope": "/"
    And the body contains "display": "standalone"
    And the body contains "theme_color": "#29d"
    And the body contains "background_color": "#2299dd"
    And the body contains an icons array with at least 192px and 512px entries
    And both icons declare purpose "any maskable"

  Scenario: GET /sw.js returns the service worker JavaScript with HTTP 200
    When the browser requests "/sw.js"
    Then the response status is 200
    And content-type is "text/javascript" or "application/javascript"
    And the body contains `addEventListener("install"`
    And the body contains `addEventListener("activate"`
    And the body contains `addEventListener("fetch"`
    And the body contains "ideajar-static-v1" (cache version)

  Scenario: GET /icons/icon-192.png returns a PNG with HTTP 200
    When the browser requests "/icons/icon-192.png"
    Then the response status is 200
    And content-type is "image/png"
    And the body starts with the PNG magic bytes (\x89PNG\r\n\x1a\n)

  Scenario: GET /icons/icon-512.png returns a PNG with HTTP 200
    When the browser requests "/icons/icon-512.png"
    Then the response status is 200
    And content-type is "image/png"

  # ── Auth bypass invariance ──────────────────────────────────────
  Scenario: Unauthenticated requests to PWA assets do NOT redirect to /login
    Given no session cookie is present
    When the browser requests /manifest.json or /sw.js or /icons/icon-192.png
    Then the response status is NOT 302
    And no Location header points to /login
    # Already pinned by asset_routing_test.exs from commit 430e1d1.
    # Slice 10 keeps the invariant.

  # ── Root HTML tags ──────────────────────────────────────────────
  Scenario: Root layout includes the PWA discovery tags
    When the server renders any HTML page from the root layout
    Then the HTML head contains <link rel="manifest" href="/manifest.json">
    And it contains <meta name="theme-color" content="#29d">
    And it contains <link rel="apple-touch-icon" href="/icons/icon-192.png">

  # ── SW registration in app.js ───────────────────────────────────
  Scenario: app.js registers the service worker on window load
    When I read assets/js/app.js
    Then it contains a serviceWorker registration block
    And the block calls navigator.serviceWorker.register("/sw.js")
    And the registration is gated by 'if ("serviceWorker" in navigator)'

  # ── SW behavior contract (verified via source-read pins) ────────
  Scenario: SW install event precaches the static asset list
    When I read priv/static/sw.js
    Then the install handler calls caches.open(CACHE_NAME)
    And the handler calls cache.addAll with at least the PRECACHE_URLS array
    And the PRECACHE_URLS array contains "/manifest.json", "/icons/icon-192.png", "/icons/icon-512.png"

  Scenario: SW activate event cleans up obsolete cache versions
    When I read priv/static/sw.js
    Then the activate handler iterates caches.keys()
    And it deletes any cache whose name does not equal CACHE_NAME

  Scenario: SW fetch event uses cache-first for precached URLs, network-only otherwise
    When I read priv/static/sw.js
    Then the fetch handler responds with cached match for precached URLs
    And it falls through to fetch(event.request) for everything else
    And it does NOT intercept WebSocket upgrades (request.method != GET → bypass)

  # ── Maskable icon safe zone ─────────────────────────────────────
  Scenario: Both icons render correctly when masked by Android adaptive shapes
    Given the Android maskable spec requires content within the central 80%
    When the icon is masked into a circle, square, or squircle
    Then the central "I" character remains fully visible
    # Static design pin: the I character is centered and occupies ~50%
    # vertically — well within the 80% safe zone.

  # ── Lighthouse installability checklist ─────────────────────────
  Scenario: Lighthouse PWA audit reports all installability criteria met
    Given the manifest, SW, icons, and root tags are in place
    When I run a Lighthouse PWA audit on the production page
    Then "Installable" is true
    And "Has a registered service worker" is true
    And "Manifest has a maskable icon" is true
    # Manual gate (V2) — run via DevTools or CI Lighthouse action.

  # ── Out-of-scope guard ──────────────────────────────────────────
  Scenario: Slice 10 does NOT add iOS-specific apple-mobile-web-app-* meta tags
    When I read the root layout
    Then no <meta name="apple-mobile-web-app-capable"> tag is present
    And no <meta name="apple-mobile-web-app-status-bar-style"> is present
    # Slice 11+ may add these if iOS PWA UX requires them.

  Scenario: Slice 10 does NOT add an offline fallback page
    When the user goes offline AND requests a non-precached URL
    Then the SW does not return a custom offline page
    And the browser shows its default offline error
    # D2 strategy explicitly excludes offline shell.

  Scenario: Slice 10 does NOT add update-prompt UX
    When a new SW version installs
    Then no banner prompts the user to "reload for new version"
    And the user gets the new shell on their next manual refresh
```

## Architecture Specification

### Components

| Componente | Tipo | Responsabilità |
|---|---|---|
| `priv/static/manifest.json` | Static file | Web App Manifest canonical. Servito via Plug.Static (già reserved in `static_paths/0`). |
| `priv/static/sw.js` | Static file | Vanilla service worker (~40 LOC). Install/activate/fetch handlers + cache version. |
| `priv/static/icons/icon-192.png` | Static file | 192×192 PNG, sfondo `#29d`, "I" bianca, maskable safe zone respected. |
| `priv/static/icons/icon-512.png` | Static file | 512×512 PNG, identical design come 192. |
| `priv/scripts/generate_icons.sh` | Build helper | Shell script ImageMagick (o equiv.) per (re)generare i 2 PNG. Committato per riproducibilità. |
| `lib/ideajar_web/components/layouts.ex` (root layout) | HEEx | Aggiunti 3 tag in `<head>`: link manifest, meta theme-color, apple-touch-icon. |
| `assets/js/app.js` (extended) | JS | Block `if ("serviceWorker" in navigator)` + `navigator.serviceWorker.register("/sw.js")` su window load. |
| `IdeajarWeb` `static_paths/0` | List | Già contiene `manifest.json`, `sw.js`, `icons` (commit 430e1d1). NON cambiare. |
| `test/ideajar_web/asset_routing_test.exs` (extended) | Test | Estesi i 3 path test per asserire content-type + body shape (manifest fields, sw handlers, PNG magic). |
| `test/ideajar_web/pwa_layout_test.exs` (new) | Test | Render root layout integration test asserisce link/meta tags presenti. |

### Interfaces

**No domain API.** PWA è interamente delivery layer — file statici + tag HTML + 1 hook JS.

**HTTP routes** (already covered by Plug.Static, slice 10 just populates the file system):
- `GET /manifest.json` → 200 `application/json` + manifest body
- `GET /sw.js` → 200 `text/javascript` + SW source
- `GET /icons/icon-192.png` → 200 `image/png`
- `GET /icons/icon-512.png` → 200 `image/png`

**Service worker contract** (`priv/static/sw.js`):
```js
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

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return

  event.respondWith(
    caches.match(event.request).then((cached) => {
      return cached || fetch(event.request)
    })
  )
})
```

**Manifest contract** — see `Intent Description` § Manifest content.

**Root layout HEEx contract**:
```heex
<head>
  ...
  <link rel="manifest" href="/manifest.json" />
  <meta name="theme-color" content="#29d" />
  <link rel="apple-touch-icon" href="/icons/icon-192.png" />
  ...
</head>
```

**`assets/js/app.js` SW registration block**:
```js
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/sw.js")
  })
}
```

### Constraints

- **No domain code**: tutta la slice è delivery layer. `Ideajar.*` invariato.
- **No new routes in router.ex**: `Plug.Static` già serve `manifest.json`, `sw.js`, `icons/` via `static_paths/0`.
- **No auth bypass changes**: il bypass è già in `lib/ideajar_web.ex` (commit 430e1d1). Slice 10 non lo modifica.
- **Icons committed binary**: i 2 PNG finali committati in `priv/static/icons/`. La script `priv/scripts/generate_icons.sh` per riproducibilità — NON eseguita a build time, NON aggiunta a `mix.exs` aliases.
- **Maskable safe zone**: contenuto (lettera "I") entro l'80% centrale dell'icon canvas. Sfondo solid riempie 100%.
- **Cache version manuale**: `CACHE_NAME = "ideajar-static-v1"`. Incrementare il suffisso a ogni cambio di asset list o SW logic. NO automazione (couple-2-user, deploy infrequente).
- **No precache HTML**: la fetch handler intercetta solo GET, e per URL non in `PRECACHE_URLS` cade through a `fetch(event.request)` senza intercettazione cache. WebSocket upgrades (non-GET) bypassano completamente.
- **No offline fallback**: se il network fallisce per HTML, il browser mostra il suo errore default. D2 strategy esplicita.
- **Maskable icons `purpose: "any maskable"`**: entrambi i 2 PNG sono dichiarati come `any` (browser default) E `maskable` (Android adaptive shapes). Single declaration with both purposes mantiene il manifest compatto.
- **HEEx auto-escape sui tag**: i 3 tag root sono statici (no user input), no XSS surface.

### Dependencies

- **Nessuna nuova dep Hex.** Plug.Static è already in scope.
- **ImageMagick** (build-time only): per generare i PNG via script. Non è una runtime dependency.

### Out of scope

- Push notifications, Background Sync, Periodic Sync
- Web Share Target API, File Handling API, Shortcuts
- Custom splash screen (browser auto-genera)
- iOS apple-mobile-web-app-* meta tags
- HTML shell precache, offline fallback page
- Update prompts UX (notifying users of new SW)
- Custom install prompt UX (browser native is sufficient)
- Workbox or any heavy SW framework
- HTTPS enforcement (slice 11 deploy via Gigalixir)
- Background SW updates strategy (l'utente refresha manualmente per ricevere nuova versione)
- IndexedDB / persistent client storage
- App badging API
- Multi-language manifest (slice 10 è IT-only)

## Acceptance Criteria

### Static asset delivery

- [ ] **A1** — `priv/static/manifest.json` exists, valid JSON.
- [ ] **A2** — `GET /manifest.json` returns 200 + `application/json` content-type.
- [ ] **A3** — Manifest body contains required fields: `name="Ideajar"`, `short_name="Ideajar"`, `description="Idee da fare insieme"`, `lang="it"`, `dir="ltr"`, `start_url="/"`, `scope="/"`, `display="standalone"`, `theme_color="#29d"`, `background_color="#2299dd"`.
- [ ] **A4** — Manifest icons array contains 2 entries: `/icons/icon-192.png` (192×192) and `/icons/icon-512.png` (512×512), both `image/png`, both `purpose: "any maskable"`.
- [ ] **A5** — `priv/static/sw.js` exists, ASCII text.
- [ ] **A6** — `GET /sw.js` returns 200 + `text/javascript` (or `application/javascript`).
- [ ] **A7** — SW source contains `addEventListener("install"`, `addEventListener("activate"`, `addEventListener("fetch"`, and the literal string `"ideajar-static-v1"`.
- [ ] **A8** — `priv/static/icons/icon-192.png` exists, starts with PNG magic bytes (`\x89PNG\r\n\x1a\n`), is 192×192.
- [ ] **A9** — `priv/static/icons/icon-512.png` exists, PNG magic, 512×512.
- [ ] **A10** — `GET /icons/icon-192.png` and `/icons/icon-512.png` return 200 + `image/png`.

### Auth bypass invariance (regression)

- [ ] **AB1** — All 3 PWA paths (`/manifest.json`, `/sw.js`, `/icons/*`) NOT redirect to `/login` when unauthenticated. Already pinned by `asset_routing_test.exs` from slice 1; slice 10 keeps green.

### Root HTML tags

- [ ] **H1** — Root layout HEEx contains `<link rel="manifest" href="/manifest.json">`.
- [ ] **H2** — Root layout HEEx contains `<meta name="theme-color" content="#29d">`.
- [ ] **H3** — Root layout HEEx contains `<link rel="apple-touch-icon" href="/icons/icon-192.png">`.
- [ ] **H4** — Out-of-scope guard: NO `<meta name="apple-mobile-web-app-*">` tags in root layout (slice 11+ if needed).

### SW registration in app.js

- [ ] **JS1** — `assets/js/app.js` contains `if ("serviceWorker" in navigator)` guard.
- [ ] **JS2** — Inside the guard, `window.addEventListener("load", ...)` registers `/sw.js` via `navigator.serviceWorker.register("/sw.js")`.

### SW behavior pin (source-level)

- [ ] **SW1** — Install handler calls `caches.open(CACHE_NAME)` followed by `cache.addAll(PRECACHE_URLS)`.
- [ ] **SW2** — `PRECACHE_URLS` literal contains `/manifest.json`, `/icons/icon-192.png`, `/icons/icon-512.png`.
- [ ] **SW3** — Activate handler iterates `caches.keys()` and deletes any name `!== CACHE_NAME`.
- [ ] **SW4** — Fetch handler short-circuits non-GET (early return).
- [ ] **SW5** — Fetch handler's `respondWith` does cache-match-first, fetch-fallthrough.
- [ ] **SW6** — `CACHE_NAME = "ideajar-static-v1"` literal present.

### Manifest content validation (programmatic)

- [ ] **M1** — `name === "Ideajar"`, `short_name === "Ideajar"`.
- [ ] **M2** — `description === "Idee da fare insieme"`.
- [ ] **M3** — `start_url === "/"`, `scope === "/"`, `display === "standalone"`.
- [ ] **M4** — `theme_color === "#29d"`, `background_color === "#2299dd"`.
- [ ] **M5** — `lang === "it"`, `dir === "ltr"`.
- [ ] **M6** — `icons` is a list of length 2; one is 192×192, the other 512×512; both have `purpose: "any maskable"`.

### Validation venue

- [ ] **V1** — Lighthouse PWA audit (DevTools): "Installable" criterion green. Manual gate.
- [ ] **V1a** — Lighthouse "Manifest has a maskable icon" green.
- [ ] **V1b** — Lighthouse "Has a registered service worker" green.
- [ ] **V2** — Manual: install prompt visible on Android Chrome desktop in DevTools "Application" tab.
- [ ] **V2a** — Manual: install on Android device, verify standalone display + splash screen + icon on home screen.
- [ ] **V2b** — Manual: install on iOS Safari (Add to Home Screen), verify icon + standalone display.

### Operational / data

- [ ] **O1** — No migration. No domain code changes.
- [ ] **O2** — No new Hex deps.
- [ ] **O3** — `priv/scripts/generate_icons.sh` committed (reproducibility), executable, NOT auto-run.
- [ ] **O4** — Total slice diff < 200 LOC (sw.js ~40 + manifest.json ~30 + script ~40 + tests ~80 + layout 3 lines + app.js 5 lines).

### Documentation

- [ ] **D1** — `docs/conventions.md` UI copy table aggiornata con manifest IT strings (`name`, `description`).
- [ ] **D2** — `CONTEXT.md` Prossimi passi: slice 10 marked implemented; slice 11 (deploy) becomes the next step.
- [ ] **D3** — README or new `docs/pwa.md` brief note on cache version bumping (if cache invalidation needed).

### UI copy aggiunta (canonical)

| Elemento | Testo IT |
|---|---|
| Manifest `name` | `Ideajar` |
| Manifest `short_name` | `Ideajar` |
| Manifest `description` | `Idee da fare insieme` |

## Consistency Gate

- [x] Intent unambiguo — D2 strategy esplicita (cache static only, no offline fallback, no shell precache); 4 file da popolare in `priv/static/`; 3 tag root + 1 SW registration block
- [x] Ogni behavior ha BDD scenario corrispondente (manifest content + SW handlers + icons PNG + auth bypass + root tags + maskable safe zone + Lighthouse + 3 out-of-scope guards)
- [x] Architecture constrains without over-engineering (vanilla SW no framework, static files no controllers, no domain code, ~40 LOC SW)
- [x] Termini consistenti (`PRECACHE_URLS`, `CACHE_NAME`, `ideajar-static-v1`, `purpose: "any maskable"`, `D2 strategy`)
- [x] No contradictions — auth bypass già in place (430e1d1) chiarito esplicitamente; static_paths già reserved chiarito; HTML precache esplicitamente fuori scope per WebSocket-driven LV

**Verdict: PASS** — ready for `/plan`.
