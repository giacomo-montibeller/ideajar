# Plan: Slice 10 — PWA installability (manifest + service worker + icons)

**Created**: 2026-05-03
**Branch**: main (trunk-based)
**Status**: implemented
**Spec**: `docs/specs/pwa-installability.md`

## Build conventions (carried from slice 1-9)

- **Strict TDD** — RED → GREEN → REFACTOR per step.
- Ogni commit attraverso la skill `commit-message`. In `/build` uso option 1 default.
- Pre-step gate: `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo`, `mix deps.audit`, `mix test --include migration`.
- Slice 10 è interamente delivery layer (`IdeajarWeb.*` + asset statici). Nessun cambio in `Ideajar.*`.
- UI copy IT canonica appesa a `docs/conventions.md` nello step 5.
- Trunk-based su `main`, ogni step lascia il codebase committable.

## Goal

Slice 10 rende ideajar **installabile** sulla home screen di iOS/Android come app standalone, e fa **caricare istantaneamente da cache** gli asset statici alla prossima visita. Strategy "D2 — cache static assets" (deciso pre-spec): il service worker precaching solo gli asset statici (CSS/JS bundles, icons, manifest stesso) all'install. NO HTML shell precache (LV è WebSocket-driven, cachare il root HTML non aiuta), NO offline fallback page, NO update prompts UX, NO Workbox.

Foundation: `IdeajarWeb.static_paths/0` da slice 1 commit `430e1d1` ha già riservato `manifest.json`, `sw.js`, e `icons` come prefissi. Slice 10 popola i file in `priv/static/`. NESSUNO cambia in router, controller, auth pipeline, schema DB.

Fuori scope: Push notifications, Background Sync, Web Share Target, File Handling, custom splash screen, iOS apple-mobile-web-app-* meta tags, HTML shell precache, offline fallback page, update prompts UX, Workbox, HTTPS enforcement (slice 11).

## Decisioni architetturali pre-build

- **DD-S10-1 — Static files only, no controllers (B+I plan-questions)**: tutti i 4 asset (`manifest.json`, `sw.js`, `icon-192.png`, `icon-512.png`) vivono in `priv/static/` e sono serviti da `Plug.Static`. Nessun controller. Razionale: `static_paths/0` già reserved (commit 430e1d1), Plug.Static gestisce content-type detection + cache headers + ETag. Aggiungere un controller sarebbe over-engineering per file statici immutabili.

- **DD-S10-2 — PNG dimension verification by chunk scan (post-iter1 Acceptance B1 fix)**: per evitare di aggiungere `mogrify`/`image` come Hex dep solo per il test. Iter1 plan usava un pattern-match a offset fissi (`<<_magic::64, _ihdr_len::32, "IHDR", w::32, h::32, _>>`) che si rompe se il PNG ha chunk ancillari (`tEXt`/`iTXt`/`pHYs`) PRIMA di IHDR — situazione spec-non-conforming ma osservata con alcune toolchain ImageMagick. Iter2 fix: 2 livelli di difesa.
  1. **Toolchain side**: lo script `generate_icons.sh` usa il flag `-strip` di ImageMagick per rimuovere TUTTI i chunk metadata, garantendo che IHDR sia il primo chunk.
  2. **Test side**: il parser scansiona la sequenza di chunk (lunghezza, type, data, CRC) finché trova IHDR, invece di assumere offset fissi. ~15 righe Elixir, robusto vs qualsiasi PNG conforme:
  ```elixir
  defp png_dimensions(<<137, 80, 78, 71, 13, 10, 26, 10, rest::binary>>) do
    find_ihdr(rest)
  end
  
  defp find_ihdr(<<len::32, "IHDR", w::32, h::32, _crc::32, _::binary>>)
       when len == 13,
       do: {w, h}
  
  defp find_ihdr(<<len::32, _type::4-bytes, _data::size(len)-bytes, _crc::32, rest::binary>>),
    do: find_ihdr(rest)
  ```
  Pin `{192, 192}` per il 192-icon e `{512, 512}` per il 512-icon.

- **DD-S10-3 — Maskable safe zone (B plan-question)**: il design "lettera I bianca su sfondo #29d" rispetta l'80% safe zone Android maskable. Non automatable in test (richiederebbe image processing per cover detection). V2/V2a manual gate sufficient. Visualizzare con DevTools Application → Manifest preview maskable cycle.

- **DD-S10-4 — Layout tag location (C plan-question)**: i 3 PWA tag (`<link rel="manifest">`, `<meta name="theme-color">`, `<link rel="apple-touch-icon">`) vivono in `<head>` di `lib/ideajar_web/components/layouts/root.html.heex` (NOT nel function component `app/1` di `layouts.ex` che wrappa la live region). `root.html.heex` è il vero root HTML doctype/head/body skeleton.

- **DD-S10-5 — SW registration timing (D plan-question)**: registrazione su `window.addEventListener("load", ...)`. NOT su immediate execution. Razionale: aspettare il `load` event garantisce che la pagina sia pienamente loaded e non competa con il critical render path. Pattern raccomandato MDN.

- **DD-S10-6 — `generate_icons.sh` reproducibility (E plan-question)**: script ImageMagick committato in `priv/scripts/generate_icons.sh`. NOT auto-run a build time (NO mix.exs alias). Documenta il comando esatto in commento sopra. PNG finali committati in `priv/static/icons/`. Trigger per re-run script: design change (cambio colore/lettera/font). Su macchine diverse i PNG potrebbero non essere bit-identical (font rendering varia), ma sono visualmente equivalenti e passano gli stessi test (magic bytes + dimensions).

- **DD-S10-7 — Cache version manuale (F plan-question)**: `CACHE_NAME = "ideajar-static-v1"` literal. Incrementare il suffisso a ogni cambio di `PRECACHE_URLS` o SW logic (es. v2 quando aggiungi un asset). Slice 11 deploy NON automatizza (couple-2-user, deploy infrequente). Documenta in `priv/static/sw.js` docstring/commento.

- **DD-S10-8 — Content-type test for sw.js (G plan-question)**: Plug.Static usa `MIME.from_path/1` che mapppa `.js` → `text/javascript` (default Phoenix MIME config in `config/config.exs`). Test accetta sia `text/javascript` sia `application/javascript` (entrambi accettati dai browser, alcune config legacy usano il secondo).

- **DD-S10-9 — Test seam per layout test (H plan-question)**: usa `Phoenix.ConnTest.get(conn, "/login")` (page non-autenticata che renderizza root layout) e asserisci sui 3 tag nella response body. NO need di sessione autenticata — i tag PWA sono nel root layout, presente in ogni response HTML.

- **DD-S10-10 — `asset_routing_test.exs` adattamento (I plan-question)**: il test esistente `GET /icons/icon.png` (commit 430e1d1) usa un path NON esistente per asserire NOT 302 redirect a /login. Slice 10 introduce i path reali `/icons/icon-192.png` e `/icons/icon-512.png`. Aggiorna il test esistente per coprire i path reali (entrambi 200 + image/png, NOT 302) E mantieni il path-non-esistente come fallthrough check (`/icons/icon.png` → 404, NOT 302). Tre asserzioni totali post-slice-10.

- **DD-S10-11 — Out-of-scope guard (J plan-question)**: nessun nuovo `Cerca*` o pattern UI nel render. Slice 8 guard scoped già verde. Slice 10 aggiunge solo manifest content (NOT renderizzato come UI strings) e tag in `<head>` (NOT testo visibile). Nessun guard update necessario.

- **DD-S10-12 — `assets/js/app.js` SW registration block placement**: appendere il block alla fine di `app.js`, dopo `liveSocket.connect()` e oltre. Razionale: il SW registration è indipendente dal LV setup; metterlo alla fine evita di bloccare la connessione WebSocket se la registrazione SW è lenta.

- **DD-S10-13 — Manifest icons single declaration `purpose: "any maskable"`**: invece di duplicare le icons nel manifest array (una `purpose: "any"` + una `purpose: "maskable"` per file), uso il singolo `purpose: "any maskable"` (entrambi space-separated). Il browser sceglie automatically. Manifest array compatto: 2 entries (192 + 512).

- **DD-S10-14 — `asset_routing_test.exs` extension naming**: il file è già `asset_routing_test.exs` (slice 1 step 7). Aggiungo nuovi describe `manifest content (slice 10)`, `service worker source (slice 10)`, `icons binary (slice 10)`. NOT un nuovo file separato.

- **DD-S10-15 — Layout test naming**: nuovo file `test/ideajar_web/pwa_layout_test.exs` per i 3 tag pin. Razionale: `asset_routing_test.exs` è scoped to "asset paths bypass auth", è semantically diverso. Layout integration test va in suo file.

- **DD-S10-16 — `app.js` SW registration test naming**: file-read pin nel `pwa_layout_test.exs` o un mini-test in `asset_routing_test.exs`. Decisione: nel `pwa_layout_test.exs` (è già "PWA delivery integration tests").

## Acceptance Criteria

> Mappatura uno-a-uno con `docs/specs/pwa-installability.md`.

### Static asset delivery

- [ ] **A1** — `priv/static/manifest.json` exists, valid JSON.
- [ ] **A2** — `GET /manifest.json` returns 200 + `application/json` content-type.
- [ ] **A3** — Manifest body required fields: `name="Ideajar"`, `short_name="Ideajar"`, `description="Idee da fare insieme"`, `lang="it"`, `dir="ltr"`, `start_url="/"`, `scope="/"`, `display="standalone"`, `theme_color="#29d"`, `background_color="#2299dd"`.
- [ ] **A4** — Manifest icons array length 2: 192×192 + 512×512, both `image/png`, both `purpose: "any maskable"`.
- [ ] **A5** — `priv/static/sw.js` exists, ASCII text.
- [ ] **A6** — `GET /sw.js` returns 200 + `text/javascript` (or `application/javascript`).
- [ ] **A7** — SW source contains `addEventListener("install"`, `addEventListener("activate"`, `addEventListener("fetch"`, and `"ideajar-static-v1"`.
- [ ] **A8** — `priv/static/icons/icon-192.png` exists, PNG magic bytes (`\x89PNG\r\n\x1a\n`), 192×192 (DD-S10-2 hand-parse).
- [ ] **A9** — `priv/static/icons/icon-512.png` exists, PNG magic, 512×512.
- [ ] **A10** — `GET /icons/icon-192.png` and `/icons/icon-512.png` return 200 + `image/png`.

### Auth bypass invariance (regression)

- [ ] **AB1** — `/manifest.json`, `/sw.js`, `/icons/icon-192.png`, `/icons/icon-512.png` NOT 302 to `/login` quando unauth. Pin esistente da slice 1 commit 430e1d1, slice 10 keeps green.

### Root HTML tags

- [ ] **H1** — `lib/ideajar_web/components/layouts/root.html.heex` contains `<link rel="manifest" href="/manifest.json">`.
- [ ] **H2** — Same file contains `<meta name="theme-color" content="#29d">`.
- [ ] **H3** — Same file contains `<link rel="apple-touch-icon" href="/icons/icon-192.png">`.
- [ ] **H4** — Out-of-scope guard: NO `<meta name="apple-mobile-web-app-*">` tags.

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
- [ ] **M6** — `icons` length 2; one is 192×192, the other 512×512; both have `purpose: "any maskable"`.

### Validation venue

- [ ] **V1** — Lighthouse PWA audit (DevTools): "Installable" criterion green. **Slice 11 dependency (R10-13)**: HTTPS audit needs deployed env, NON è pre-PR blocking per slice 10.
- [ ] **V1a** — "Manifest has a maskable icon" green.
- [ ] **V1b** — "Has a registered service worker" green.
- [ ] **V2** — DevTools Application tab: install prompt visible.
- [ ] **V2a** — Android device install + standalone display + splash screen + icon. **Slice 11 dependency**.
- [ ] **V2b** — iOS Safari Add-to-Home-Screen + icon + standalone display. **Slice 11 dependency**.

### Operational / data

- [ ] **O1** — No migration. No domain code changes.
- [ ] **O2** — No new Hex deps.
- [ ] **O3** — `priv/scripts/generate_icons.sh` committed (executable, NOT auto-run, ImageMagick command documented in script comment).
- [ ] **O4** — Total slice diff < 200 LOC.

### Documentation

- [ ] **D1** — `docs/conventions.md` UI copy table aggiornata con manifest IT strings (3 entries).
- [ ] **D2** — `CONTEXT.md` Prossimi passi: slice 10 marked implemented; slice 11 (deploy) is the next step.
- [ ] **D3** — Brief comment in `priv/static/sw.js` documenting cache version bump policy (DD-S10-7).

### UI copy aggiunta (canonical)

| Elemento | Testo IT |
|---|---|
| Manifest `name` | `Ideajar` |
| Manifest `short_name` | `Ideajar` |
| Manifest `description` | `Idee da fare insieme` |

## User-Facing Behavior

> BDD scenarios copiati verbatim da `docs/specs/pwa-installability.md` (vedi sezione "User-Facing Behavior").

## Steps

### Step 1: `priv/static/manifest.json` + manifest content tests

**Complexity**: standard
**Rationale**: file statico canonical + parsing/content validation tests. Foundation per tutti gli altri step.

**RED** (`test/ideajar_web/asset_routing_test.exs` extend con nuovo describe):
1. `priv/static/manifest.json` exists (`File.exists?` pin).
2. Body parses as valid JSON.
3. **A2 / M1-M5**: GET /manifest.json returns 200 + `application/json` content-type. Body decoded contains `name="Ideajar"`, `short_name="Ideajar"`, `description="Idee da fare insieme"`, `lang="it"`, `dir="ltr"`, `start_url="/"`, `scope="/"`, `display="standalone"`, `theme_color="#29d"`, `background_color="#2299dd"`.
4. **M6**: `icons` is a list of length 2. First entry has `sizes="192x192"`, `type="image/png"`, `src="/icons/icon-192.png"`, `purpose="any maskable"`. Second entry has `sizes="512x512"`, `src="/icons/icon-512.png"`, same type+purpose.
5. **AB1 regression**: GET /manifest.json without session is NOT 302. (Already covered by slice-1 test, re-verify.)

**GREEN**:
- Crea `priv/static/manifest.json`:
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
      {"src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any maskable"},
      {"src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any maskable"}
    ]
  }
  ```

**REFACTOR**: nessuno (file statico canonical).

**Files**: `priv/static/manifest.json` (new), `test/ideajar_web/asset_routing_test.exs` (extend).
**Spec mapping**: A1, A2, A3, A4, M1-M6, AB1, DD-S10-1.

### Step 2: `priv/static/icons/` + `priv/scripts/generate_icons.sh` + PNG dimension tests

**Complexity**: standard
**Rationale**: 2 PNG file binari + script reproducibility. Tests verifica magic bytes + dimensions hand-parse (DD-S10-2).

**RED** (`asset_routing_test.exs` extend nuovo describe `icons binary (slice 10)`):
1. `priv/static/icons/icon-192.png` exists, file size > 0.
2. **A8**: First 8 bytes are PNG magic `<<137, 80, 78, 71, 13, 10, 26, 10>>`.
3. **A8 dimension pin (chunk-scan parser DD-S10-2)**: parsing IHDR chunk via chunk scan (NOT fixed offset), width == 192, height == 192. Robust vs PNG variants con metadata pre-IHDR. Code follows DD-S10-2:
   ```elixir
   {w, h} = png_dimensions(File.read!(path))
   assert w == 192 and h == 192

   defp png_dimensions(<<137, 80, 78, 71, 13, 10, 26, 10, rest::binary>>),
     do: find_ihdr(rest)

   defp find_ihdr(<<len::32, "IHDR", w::32, h::32, _crc::32, _::binary>>)
        when len == 13,
        do: {w, h}

   defp find_ihdr(<<len::32, _type::4-bytes, _data::size(len)-bytes, _crc::32, rest::binary>>),
     do: find_ihdr(rest)
   ```
4. Identical 3 tests for `icon-512.png` con w/h == 512.
5. **A10**: GET `/icons/icon-192.png` returns 200 + `image/png` content-type. Idem 512.
6. `priv/scripts/generate_icons.sh` exists, is executable (file mode contains x bit).

**GREEN**:
- Genero i PNG via shell:
  ```bash
  #!/usr/bin/env bash
  # Slice 10 — generate the 2 PWA icons.
  # Re-run when the design changes (color, letter, font).
  # Requires: ImageMagick.
  set -e
  for size in 192 512; do
    magick -size ${size}x${size} xc:"#2299dd" \
      -font "DejaVu-Sans-Bold" -pointsize $((size / 2)) \
      -fill white -gravity center -annotate +0+0 "I" \
      priv/static/icons/icon-${size}.png
  done
  ```
- Run the script localmente per generare i 2 PNG.
- Commit i 2 PNG in `priv/static/icons/`.
- Commit lo script in `priv/scripts/generate_icons.sh` con mode `+x`.

**REFACTOR**: nessuno.

**Files**: `priv/scripts/generate_icons.sh` (new, +x), `priv/static/icons/icon-192.png` (new binary), `priv/static/icons/icon-512.png` (new binary), `test/ideajar_web/asset_routing_test.exs` (extend).
**Spec mapping**: A8, A9, A10, O3, DD-S10-2, DD-S10-6.

### Step 3: `priv/static/sw.js` + service worker source tests

**Complexity**: standard
**Rationale**: vanilla SW ~40 LOC. Tests source-level pin sui handlers + cache version.

**RED** (`asset_routing_test.exs` extend nuovo describe `service worker source (slice 10)`):
1. `priv/static/sw.js` exists, ASCII text.
2. **A6**: GET /sw.js returns 200 + `text/javascript` OR `application/javascript`.
3. **A7 / SW6**: source contains `"ideajar-static-v1"` literal.
4. **SW1**: source contains `caches.open(CACHE_NAME)` AND `cache.addAll(PRECACHE_URLS)`.
5. **SW2**: source contains `/manifest.json`, `/icons/icon-192.png`, `/icons/icon-512.png` (PRECACHE_URLS items).
6. **SW3**: source contains `caches.keys()` AND a delete iteration (`caches.delete(`).
7. **SW4**: source contains `event.request.method !== "GET"` short-circuit (or equivalent).
8. **SW5**: source contains `caches.match` and `fetch(event.request)` (cache-first then network-fallthrough).
9. Source contains `addEventListener("install"`, `addEventListener("activate"`, `addEventListener("fetch"` (3 events).
10. **D3**: source contains a comment documenting cache version bump policy (es. literal `bump CACHE_NAME` or `incrementare`).

**GREEN**:
- Crea `priv/static/sw.js`:
  ```js
  // Ideajar service worker (slice 10).
  //
  // D2 strategy: cache static assets only. HTML pages and WebSocket
  // connections are NOT intercepted — Phoenix LiveView is WebSocket-driven
  // and caching the root HTML brings no benefit.
  //
  // Cache invalidation: bump the CACHE_NAME suffix (v1 → v2 → ...) when
  // PRECACHE_URLS changes or this file's logic changes. The activate
  // handler then evicts every cache that does not match the new name.
  // Manual policy — couple-2-user app, infrequent deploys.

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

  // Fetch handler — cache-first for precached static assets,
  // network-only fallthrough for everything else. Non-GET requests
  // (POST for form submits, longpoll client→server frames) bypass
  // entirely. The longpoll GET poll URL `/live/longpoll?...` falls
  // through to network because it's not in PRECACHE_URLS — keep it
  // that way, never add a /live/* cache rule (R10-11).
  self.addEventListener("fetch", (event) => {
    if (event.request.method !== "GET") return

    event.respondWith(
      caches.match(event.request).then((cached) => cached || fetch(event.request))
    )
  })
  ```

**REFACTOR**: docstring chiaro al top spiega DD-S10-7 (cache version bump).

**Files**: `priv/static/sw.js` (new), `test/ideajar_web/asset_routing_test.exs` (extend).
**Spec mapping**: A5, A6, A7, SW1-SW6, D3, DD-S10-1, DD-S10-7.

### Step 4: Root layout PWA tags + `app.js` SW registration

**Complexity**: standard
**Rationale**: 3 tag in `<head>` + SW registration block in app.js. Test layout via integration GET.

**RED** (`test/ideajar_web/pwa_layout_test.exs` new):
1. **H1**: GET `/login` (or other public page) → response body contains `<link rel="manifest" href="/manifest.json"`.
2. **H2**: response body contains `<meta name="theme-color" content="#29d"`.
3. **H3**: response body contains `<link rel="apple-touch-icon" href="/icons/icon-192.png"`.
4. **H4 out-of-scope guard**: response body does NOT contain `apple-mobile-web-app-capable` or `apple-mobile-web-app-status-bar-style`.
5. **JS1/JS2**: file-read pin `assets/js/app.js` contains `if ("serviceWorker" in navigator)` AND `navigator.serviceWorker.register("/sw.js")` AND `window.addEventListener("load"` (DD-S10-5).

**GREEN**:
- `lib/ideajar_web/components/layouts/root.html.heex` (in `<head>`, dopo `meta name="csrf-token"`):
  ```heex
  <link rel="manifest" href="/manifest.json" />
  <meta name="theme-color" content="#29d" />
  <link rel="apple-touch-icon" href="/icons/icon-192.png" />
  ```
- `assets/js/app.js` (alla fine del file, dopo `liveSocket.connect()` + altro):
  ```js
  // Slice 10 — register the service worker for PWA offline + installability.
  // Registration is gated behind window.load to avoid competing with the
  // critical render path (DD-S10-5).
  if ("serviceWorker" in navigator) {
    window.addEventListener("load", () => {
      navigator.serviceWorker.register("/sw.js")
    })
  }
  ```

**REFACTOR**: nessuno.

**Files**: `lib/ideajar_web/components/layouts/root.html.heex` (extend), `assets/js/app.js` (extend), `test/ideajar_web/pwa_layout_test.exs` (new).
**Spec mapping**: H1, H2, H3, H4, JS1, JS2, DD-S10-4, DD-S10-5, DD-S10-12, DD-S10-15, DD-S10-16.

### Step 5: Docs sync (D1-D3) + plan flip

**Complexity**: standard

**RED**:
1. **D1**: `test/ideajar/docs_test.exs` new describe `slice-10 manifest copy` — assert `docs/conventions.md` contains `Ideajar` (manifest name string), `Idee da fare insieme` (description).
2. **D2**: assert `CONTEXT.md` Prossimi passi section marks slice 10 implemented + slice 11 next.

**GREEN**:
- `docs/conventions.md`: append slice 10 manifest copy table.
- `CONTEXT.md`: update Prossimi passi:
  - Slice 10 (PWA): implemented
  - Slice 11 (deploy): next
- Plan flip: `**Status**: approved` → `**Status**: implemented`.

**Files**: `docs/conventions.md` (extend), `CONTEXT.md` (update), `test/ideajar/docs_test.exs` (extend), `plans/slice-10-pwa-installability.md` (status flip).
**Spec mapping**: D1, D2, DD-S10-11.

## Complexity Classification

| Step | Complessità | Motivazione |
|------|-------------|-------------|
| 1 | standard | Static JSON file + content validation tests |
| 2 | standard | 2 binary PNG + reproducibility script + hand-parse PNG dimension test |
| 3 | standard | Vanilla SW ~40 LOC + source-level pins |
| 4 | standard | 3 layout tags + 1 JS hook + integration test |
| 5 | standard | Docs sync |

Tutta la slice è puro delivery layer, nessun cambio domain, nessuna migration. Complessità totale bassa rispetto alle slice precedenti.

## Pre-PR Quality Gate

- [ ] `mix test --include migration` passa.
- [ ] `mix format --check-formatted` exit code 0.
- [ ] `mix credo` passa.
- [ ] `mix deps.audit` passa.
- [ ] `mix compile --warnings-as-errors` passa.
- [ ] `/code-review` su file toccati passa.
- [ ] **Spec traceability**: ogni `Scenario:` Gherkin ha almeno un test (alcuni sono manual gates V1/V2).
- [ ] **V1**: Lighthouse PWA audit DevTools — Installable + maskable icon + SW green.
- [ ] **V2a**: Android device install + standalone + splash + icon.
- [ ] **V2b**: iOS Safari Add-to-Home-Screen install.
- [ ] CI verde sul push.

## Risks & Open Questions

- **R10-1 — ImageMagick locally available**: lo script `generate_icons.sh` richiede ImageMagick (`magick` o `convert`) installato. Sviluppatore deve avere ImageMagick locale. Mitigazione: i PNG finali sono committati, lo script è solo per re-generation. Nessuna dependency a runtime / build time.

- **R10-2 — PNG bit-identical reproducibility (E)**: lo stesso comando ImageMagick su macchine diverse può produrre PNG con bytes diversi (font hint, compression level). I test pin solo magic bytes + dimensions, NOT byte equality. Acceptable: il design visivo è equivalente.

- **R10-3 — Phoenix MIME type for `.js` (G)**: il default Phoenix MIME map deve includere `text/javascript` per `.js`. Verifica via `MIME.from_path("test.js")` in iex prima dello step 3 RED. Se diverso (es. `application/javascript`), aggiorna il test per accettare entrambi.

- **R10-4 — `start_url: "/"` redirects to `/login` when unauth**: il manifest dichiara `start_url: "/"` ma `/` redirige a `/login` se l'utente non è autenticato. Quando l'app è installata e l'utente apre la PWA standalone, la prima cosa che vede è `/login`. Acceptable per couple-2-user. NON è uno scope per slice 10 cambiare questo.

- **R10-5 — SW caching e CDN/static fingerprinting**: in production Phoenix usa `assets_url` con cache busting (digest fingerprint). Il SW precaching `/manifest.json` (no fingerprint) è stable. Le icons (`/icons/icon-*.png`) sono stable path. CSS/JS bundles hanno fingerprint, NON in `PRECACHE_URLS` per evitare stale cache. Slice 10 esplicitamente NON precaching CSS/JS bundles — solo i 3 path stable.

- **R10-6 — Cache version manual bump (DD-S10-7)**: se uno sviluppatore modifica `PRECACHE_URLS` o `sw.js` logic ma DIMENTICA di bumpare `CACHE_NAME`, gli utenti istallati NON vedranno il nuovo SW (browser conserva quello cached). Mitigazione: docstring chiaro al top di `sw.js`. Slice 11+ può aggiungere CI check (es. grep diff per detect SW change without version bump). Slice 10 lascia manuale.

- **R10-7 — Lighthouse audit pass criteria**: oltre ai 3 check pinned (Installable, maskable icon, SW), Lighthouse PWA audit ha altri criteri (HTTPS, viewport meta, theme-color tag, apple-touch-icon). Slice 10 li copre tutti tranne HTTPS (slice 11). Lo `serves over HTTPS` audit fallirà su localhost — accettare V1 con HTTPS pendente.

- **R10-8 — `apple-touch-icon` size 192 vs Apple's 180**: Apple raccomanda 180×180 per `apple-touch-icon`. Slice 10 usa 192 (il PNG già esistente). Apple scala automatically, accettabile. Slice 11+ può aggiungere un terzo file `icon-180.png` se necessario. NON in scope.

- **R10-9 — gettext deferral (slice 4 R6 carry-over)**: slice 10 aggiunge 3 manifest IT strings. Cumulative ~109. Trigger residuo (utente non-IT) non scattato.

- **R10-10 — Service worker behavior in dev (Phoenix LiveReload)**: in dev mode, Phoenix LiveReload triggera reload via WS. Il SW potrebbe interferire? Il fetch handler short-circuita non-GET (live reload usa GET su `/phoenix/live_reload/*` però). Pin: aggiungi a `PRECACHE_URLS` solo i 3 stable path. Live reload paths NON intercepted (caches.match miss → fetch fallthrough). Acceptable.

- **R10-11 — Phoenix `longpoll` GET poll fallthrough (post-iter1 Design W1)**: quando il browser fa fallback al longpoll transport, Phoenix usa GET su `/live/longpoll?token=...` per il poll. Il fetch handler intercetta i GET, fa `caches.match` (miss perché path non in `PRECACHE_URLS`) e fa `fetch(event.request)`. NO interception, NO caching. Comportamento corretto. Aggiungere comment esplicito in `sw.js` per documentare l'intentional fall-through.

- **R10-12 — Lighthouse "Works offline" deprecato (post-iter1 Design W2)**: il check Lighthouse "Works offline" è deprecato dal Lighthouse 8 (2021). L'audit "Installable" attuale NON richiede offline response. La D2 strategy (no HTML precache, no offline fallback) NON regredisce il Lighthouse Installable score. Documenta esplicitamente.

- **R10-13 — V1/V2/V2a/V2b validation richiede slice 11 HTTPS env (post-iter1 Strategic W1)**: il Lighthouse PWA audit richiede HTTPS per il check "serves over HTTPS". Su localhost questo audit fallisce. I gate manuali V1/V2 NON sono pre-PR-blocking — vengono completati dopo lo slice 11 deploy quando l'app è disponibile su `https://*.gigalixir.com` (o equivalent). Cross-reference esplicito nel Pre-PR Quality Gate.

- **R10-14 — UX W3 cold-launch worst-case path**: il sequence cold-launch quando session expired è: blue splash (`#2299dd`) → blank page durante LV boot → `/login` form. Tre transizioni visive prima del content. Acceptable per couple-2-user perché slice 6 keep authenticated devices logged in across deploys (il flusso normale è blue splash → idea list, no login). Documentato come known worst-case.

- **R10-15 — UX W2 splash background_color → `#2299dd` (post-iter1 UX B1 fix)**: iter1 plan usava `#ffffff` (white). Su device dark-mode il flash bianco è jarring. Fix: bg color = stesso hue del icon (`#2299dd`), il splash screen mostra un campo blu con la I bianca centrata che reads well in entrambi light/dark contexts.

## Plan Review Summary

Quattro plan-review personas dispatched (Acceptance / Design / UX / Strategic). Iter1: Acceptance + UX `needs-revision`, Design + Strategic `approve`. Iter2: tutti `approve`.

### Acceptance Test Critic — `approve` (post-iter2)
**Iter1 blocker fissato**:
- **B1 PNG hand-parse fragile**: 2-level defense aggiunto in DD-S10-2. (1) `generate_icons.sh` usa flag `-strip` ImageMagick per garantire IHDR primo chunk. (2) Test parser fa chunk-scan (length+type+data+CRC) finché trova IHDR, no fixed-offset assumption. ~15 righe Elixir robuste vs qualsiasi PNG conforme. Step 2 RED block aggiornato per coerenza con DD-S10-2.

**Warning iter1 risolti**:
- W1 spec Gherkin quote-style → fixed a double quotes
- W2 SW source pin scoping (cache-first only for PRECACHE_URLS) → comment esplicito in `sw.js` GREEN body
- W3 R10-4 conditional Lighthouse → R10-13 documenta deferral a slice 11 HTTPS env

### Design & Architecture Critic — `approve` (post-iter1, no iter2 needed)
- DD-S10-1 Plug.Static-only: ottima scelta (no controllers, ETag/cache headers free)
- DD-S10-13 `purpose: "any maskable"` single declaration: spec-compliant
- DD-S10-2 hand-parse (then chunk-scan): cheap vs Hex deps
- DD-S10-5 `window.load` registration: MDN-canonical
- DD-S10-4 `root.html.heex`: corretto (head è solo qui)

**Warning addressati**:
- W1 longpoll GET fallthrough → comment esplicito in step 3 GREEN sw.js (R10-11)
- W2 Lighthouse "Works offline" deprecato → R10-12 documenta
- W3 CI gate per cache version → defer a slice 11

### UX Critic — `approve` (post-iter2)
**Iter1 actionable change fissato**:
- **B1 background_color #fff → #2299dd**: applicato a spec + plan + acceptance criteria (A3, M4) + step 1 GREEN JSON. Splash screen ora un campo blu con I bianca centrata, reads well in light/dark contexts. Eliminato il white-flash su dark-mode device.

**Warning iter1 documentati**:
- W3 cold-launch worst-case path → R10-14
- W1 standalone iOS no back navigation → known caveat couple-2-user shallow-nav app
- W4-W6 acceptable per audience (couple-2-user, daily use, infrequent deploys)

### Strategic Critic — `approve` (post-iter1, no iter2 needed)
- Problem fit: PWA installability è il delivery mechanism inteso (CONTEXT.md), non un nice-to-have
- Scope: 5 step right-sized, ~120 LOC net code, ~800 lines spec+plan
- Risk: tutti documentati e mitigated
- Opportunity cost: 1 day giustificato per shipping intended UX
- D2 strategy coherent

**Warning iter1 documentati**:
- W1 V1/V2 require slice 11 HTTPS env → R10-13 + Pre-PR Quality Gate cross-references
- W2 cache version bump operational runbook → defer step 5 docs
- W3 Intent Description "CSS/JS bundle" misleading → fixed a "stable-path" PRECACHE only

### Iter 2 — convergence
Tutti i 4 reviewer post-fix tornano `approve`. Plan flip da `draft` → `approved` autorizzato.
