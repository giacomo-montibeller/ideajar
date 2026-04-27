# Spec: Device-level password authentication

> Slice 1 of the ideajar project (see `CONTEXT.md`). Foundation slice: enables a private shared workspace before any feature work begins.

## Intent Description

L'app è raggiungibile su rotta root (`/`). Al primo accesso da un dispositivo, viene mostrato un form che richiede una **password condivisa** unica, configurata a deploy-time tramite env var `WORKSPACE_PASSWORD` (≥12 caratteri, validata a startup; l'app non parte se mancante o troppo corta). Submit corretto → la sessione del browser è marcata come autenticata tramite cookie firmato dal server, con durata **10 anni**. Submit errato → stesso form, messaggio generico "password errata", risposta ritardata di ~500ms.

Da quel momento, ogni accesso successivo dallo stesso browser/PWA bypassa il form e accede direttamente all'app. **Non c'è logout esplicito, non c'è recovery, non c'è rotazione.** La password è una sola, condivisa fuori banda. Se in futuro si volesse cambiarla, sarà una modifica con redeploy che richiederà un nuovo login da ogni dispositivo (fuori scope di questa slice).

Sono pubblici e accessibili senza autenticazione **solo** gli asset necessari all'installabilità PWA: `/manifest.json`, `/sw.js`, le icone. Tutto il resto (rotte funzionali, LiveView, eventuali API) richiede sessione autenticata; le richieste GET non autenticate vengono rediriette a `/login?return_to=<path>` per ripristinare la destinazione originale dopo il login.

## User-Facing Behavior

```gherkin
Feature: Device-level password authentication
  As one of the two users sharing this workspace
  I want to authenticate my device once with a shared password
  So that the app behaves like a private bookmark on subsequent visits

  Background:
    Given the application has been deployed with WORKSPACE_PASSWORD set to "correct horse battery staple"

  # ── First access ────────────────────────────────────────────────────
  Scenario: First visit from a fresh device shows the login form
    Given my browser has no session cookie for this app
    When I visit "/"
    Then I am redirected to "/login"
    And I see a single password input field and a submit button
    And no other workspace content is visible

  Scenario: Successful login grants access and persists across reloads
    Given my browser has no session cookie for this app
    And I am on "/login"
    When I submit the password "correct horse battery staple"
    Then I am redirected to "/"
    And I see the workspace home
    And my browser holds a signed session cookie marking this device as authenticated
    When I close the tab and reopen "/" later
    Then I see the workspace home directly without the login form

  Scenario: Login preserves the originally requested path
    Given my browser has no session cookie for this app
    When I visit "/some/protected/path"
    Then I am redirected to "/login?return_to=%2Fsome%2Fprotected%2Fpath"
    When I submit the correct password
    Then I am redirected to "/some/protected/path"

  Scenario Outline: return_to is rejected when it points outside the app
    Given my browser has no session cookie for this app
    When I visit "/login?return_to=<value>"
    And I submit the correct password
    Then I am redirected to "/"

    Examples:
      | value              |
      | https://evil.com   |
      | //evil.com         |
      | http://evil.com    |

  # ── Wrong password ──────────────────────────────────────────────────
  Scenario: Wrong password shows a generic error and does not authenticate
    Given my browser has no session cookie for this app
    And I am on "/login"
    When I submit the password "wrong"
    Then the response is delayed by at least 500 milliseconds
    And I see a generic error message "password errata"
    And I am still on the login form
    And no session cookie marking authentication is set

  Scenario: Repeated wrong passwords behave identically (no lockout)
    Given my browser has no session cookie for this app
    When I submit a wrong password 10 times in a row
    Then each attempt produces the same generic error
    And no attempt locks me out or rate-limits more strictly than the 500ms delay
    And submitting the correct password on the 11th attempt grants access normally

  Scenario: Empty password submission is treated as a wrong password
    Given I am on "/login"
    When I submit an empty password field
    Then I see the same generic error and 500ms delay as for any wrong password

  # ── Returning device ────────────────────────────────────────────────
  Scenario: Returning device with a valid session skips the login form
    Given my browser holds a valid signed session cookie marking this device as authenticated
    When I visit "/"
    Then I see the workspace home
    And I am not shown the login form

  Scenario: A second device is a separate authentication
    Given device A is authenticated
    And device B has no session cookie for this app
    When device B visits "/"
    Then device B is redirected to "/login"
    And device A's session is unaffected

  Scenario: Already authenticated visit to /login redirects home
    Given my browser holds a valid session cookie marking this device as authenticated
    When I visit "/login"
    Then I am redirected to "/"
    And no second authentication occurs

  # ── POST without session ────────────────────────────────────────────
  Scenario: Unauthenticated POST to a protected route is rejected with 403
    Given my browser has no session cookie for this app
    When I send a POST request to a protected route
    Then I receive a 403 Forbidden response
    And I am not redirected
    And no side effect occurs

  # ── Tampered cookie ─────────────────────────────────────────────────
  Scenario: A tampered or invalid signed cookie is treated as no session
    Given my browser holds a session cookie whose signature does not validate
    When I visit "/"
    Then I am redirected to "/login"
    And no error is leaked to the client about the cookie being invalid

  # ── Sessions survive redeploy ───────────────────────────────────────
  Scenario: Existing sessions survive an application redeploy
    Given device A is authenticated
    And the application is redeployed with the same WORKSPACE_PASSWORD and same secret_key_base
    When device A visits "/"
    Then device A still sees the workspace home without re-authenticating

  # ── Public PWA assets ───────────────────────────────────────────────
  Scenario Outline: PWA assets are reachable without authentication
    Given my browser has no session cookie for this app
    When I request "<path>"
    Then I receive a 200 response
    And no redirect to "/login" occurs

    Examples:
      | path             |
      | /manifest.json   |
      | /sw.js           |
      | /icons/icon.png  |
```

## Architecture Specification

### Components

| Componente | Tipo | Responsabilità |
|---|---|---|
| `IdeajarWeb.Endpoint` | Phoenix endpoint (esistente) | `Plug.Session` con cookie store firmato; `secret_key_base` da env var, stabile tra deploy |
| `IdeajarWeb.RequireAuth` | Plug custom | Legge `:authenticated` dalla session; se assente/falso → su GET redirect `/login?return_to=…`, su POST `send_resp(403)` e halt |
| `IdeajarWeb.LoginController` | Phoenix Controller (no LiveView) | `GET /login` → render form con flash error opzionale; `POST /login` → confronto costante-tempo, su match `put_session(:authenticated, true)` + redirect a `return_to` o `/`, su miss `Process.sleep(500)` + render con errore generico |
| `IdeajarWeb.Router` | Pipeline routing | 3 pipeline: `:browser` (base), `:public_browser` (browser + nessun auth check, per asset PWA + login), `:authenticated_browser` (browser + `RequireAuth`) |
| `Ideajar.Application` | Boot check | All'avvio legge `WORKSPACE_PASSWORD`, fallisce con `raise` se assente o `< 12` char prima di avviare l'endpoint |

### Interfaces

- **Session cookie**: `Plug.Session` firmato; chiavi minime `:authenticated => true`. Attribute: `http_only: true`, `same_site: "Lax"`, `secure: true` in prod, `max_age: 315_360_000` (10 anni).
- **Routes**:
  - `GET /login` → `LoginController.new`
  - `POST /login` → `LoginController.create`
  - `GET /` → (slice 2+) sotto `:authenticated_browser`
  - `GET /manifest.json`, `GET /sw.js`, `GET /icons/*` → sotto `:public_browser` (slice 9 li implementerà; per la slice 1 non esistono ancora, ma le pipeline sono già strutturate per supportarli)
- **Configurazione runtime** (`config/runtime.exs`):
  - `WORKSPACE_PASSWORD` — string, ≥12 char, required
  - `SECRET_KEY_BASE` — string ≥64 byte, required, stabile tra deploy (Gigalixir env var)

### Dependencies

- Solo libreria: `Plug.Crypto.secure_compare/2` per il match password (già in Phoenix). Nessuna nuova dipendenza.

### Constraints

- Password confrontata in **constant time**.
- Password **non loggata mai**, nemmeno troncata; nessun campo di telemetria deve riferirsi a essa.
- `secret_key_base` **non** ruotato fra deploy — altrimenti tutte le sessioni invalidate.
- `return_to` accettato solo se inizia con `/` e non con `//`; altri valori → ignorati, redirect post-login a `/`.
- 500ms delay implementato come `Process.sleep/1` (accettabile: scala = una coppia, nessun rischio di starvation del pool).
- LiveView **non** usato per il login form: form HTTP classico via Controller. Le slice successive useranno LiveView dietro la pipeline `:authenticated_browser`.

### Out of scope

- Recovery, reset, rotazione, audit log, multi-utente, lockout/rate limit, OAuth, SSO, account.

## Acceptance Criteria

### Functional / behavioral

- [ ] **F1** — Tutti gli scenari Gherkin del BDD passano come test ExUnit/Phoenix.ConnTest automatizzati.
- [ ] **F2** — Validazione `return_to`: accettato solo se inizia con `/` e non con `//`. Test esplicito: `?return_to=https://evil.com` e `?return_to=//evil.com` sono ignorati e l'utente è rediretto a `/` post-login.
- [ ] **F3** — Cookie di sessione ha attributi `HttpOnly=true`, `SameSite=Lax`, `Secure=true` (in env `:prod`), `Max-Age=315360000`. Verificabile con un test `Plug.Conn` che ispeziona la response.

### Security

- [ ] **S1** — Confronto password fatto con `Plug.Crypto.secure_compare/2` (constant-time). Verifica via grep statico nella code review.
- [ ] **S2** — La password non compare mai in log, telemetry, error reporters, o in alcuna response al client. Verifica: log di un tentativo errato non contiene il valore inviato; nessuna `inspect` o `Logger.*` con la variabile password.
- [ ] **S3** — Cookie firmato con `secret_key_base` ≥64 byte. App rifiuta lo startup se `SECRET_KEY_BASE` è più corta o assente.
- [ ] **S4** — Tampering del cookie produce stesso comportamento di "nessun cookie" (redirect a `/login`), nessun messaggio di errore esposto al client.

### Operational / configuration

- [ ] **O1** — All'avvio, `Ideajar.Application.start/2` valida `WORKSPACE_PASSWORD`: assente o `< 12` char → `raise` con messaggio chiaro nei log e l'HTTP listener non si apre. Verificabile via test che avvia l'app con env mancante.
- [ ] **O2** — All'avvio, validazione analoga per `SECRET_KEY_BASE` (≥64 byte).
- [ ] **O3** — `WORKSPACE_PASSWORD` e `SECRET_KEY_BASE` configurati come env var su Gigalixir prima del primo deploy. Documentato nel README della slice.
- [ ] **O4** — Sessioni esistenti sopravvivono a un redeploy con stesso `SECRET_KEY_BASE` e stesso `WORKSPACE_PASSWORD`. Verificabile manualmente in staging: login → redeploy → reload → ancora autenticato.

### Performance / UX

- [ ] **P1** — Submit con password errata risponde dopo ≥500ms e <800ms. Verificabile via test cronometrato.
- [ ] **P2** — Submit con password corretta risponde in <200ms in produzione (Gigalixir EU region, latenza desktop).
- [ ] **P3** — Form di login renderizza in <100ms su prima visita (HTML statico-equivalente, no DB hit).

### Validation venue

- [ ] **V1** — Tutti gli scenari BDD validati in browser desktop con DevTools in mobile viewport mode (iPhone 13 + Pixel 7) prima di considerare la slice completata. Screenshot delle 3 schermate chiave (login vuoto, login con errore, post-login) catturati.
- [ ] **V2** — Validazione su dispositivo fisico mobile rinviata alla slice 9 (PWA) post-deploy su Gigalixir, perché la fiducia del cookie a 10 anni e l'esperienza "login una volta sola" sono semanticamente identiche desktop ↔ mobile a livello di slice 1.

### Documentation / handoff

- [ ] **D1** — README della slice elenca: env var richieste, comando per generare un `SECRET_KEY_BASE` valido (`mix phx.gen.secret`), procedura di rotazione password (= redeploy con nuovo valore + comunicazione fuori banda).
- [ ] **D2** — Constraint "lingua UI = italiano" tracciato in un file di progetto (es. `docs/conventions.md`) perché si applica a tutte le slice future, non solo questa.

## Consistency Gate

- [x] Intent is unambiguous
- [x] Every behavior has a corresponding BDD scenario
- [x] Architecture constrains without over-engineering
- [x] Terminology consistent across artifacts
- [x] No contradictions between artifacts

**Verdict: PASS** — ready for `/plan`.
