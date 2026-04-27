# Plan: Slice 1 — Device-level password authentication

**Created**: 2026-04-27
**Approved**: 2026-04-27
**Branch**: (no git repo yet — initialized in Step 1)
**Status**: **approved**
**Spec**: `docs/specs/device-password-auth.md`

## Build conventions (user-confirmed)

- **Strict TDD** — every step follows RED → GREEN → REFACTOR; no production code before a failing test.
- **Git initialized in Step 1** (`git init` as the very first action before `mix phx.new`).
- **Every commit goes through the `commit-message` skill** — no direct `git commit -m "..."`. The skill proposes options; the user chooses; the chosen message is committed. The "draft commit message" listed under each step below is a hint to the skill, not the final text.

## Goal

Implementare la prima vertical slice del progetto ideajar: l'app è raggiungibile su `/`, al primo accesso da un dispositivo viene richiesta una password condivisa (env var `WORKSPACE_PASSWORD`); i submit corretti creano una sessione di 10 anni che bypassa il form sui successivi accessi. La slice include l'inizializzazione del progetto Phoenix (sqlite3 + LiveView), la pipeline di autenticazione (plug + controller HTTP classico con form accessibile), il routing per gli asset PWA (senza ancora i contenuti reali), e la documentazione operativa minima.

## Acceptance Criteria

> Mappatura uno-a-uno con la spec. Codici (F/S/O/P/V/D) preservati per traceability.

### Functional / behavioral
- [ ] **F1** — Tutti gli scenari Gherkin del BDD passano come test ExUnit/Phoenix.ConnTest automatizzati. **Inclusi** scenari di boot validation, cookie hardening, log non-leakage, redeploy survival (vedi tecnica in Step 6).
- [ ] **F2** — `return_to`: accettato solo se inizia con `/` e non con `//`. Test esplicito su `https://evil.com`, `//evil.com`, `%2F%2Fevil.com`, `javascript:alert(1)`.
- [ ] **F3** — Cookie di sessione con `HttpOnly=true`, `SameSite=Lax`, `Secure=true` in `:prod`, `Max-Age=315360000`.

### Security
- [ ] **S1** — Confronto password con `Plug.Crypto.secure_compare/2`. Verificato via test sul comportamento di `Ideajar.Auth.authenticate/1` + check Credo statico.
- [ ] **S2** — Password mai loggata. Verificato con test che usa `ExUnit.CaptureLog` su POST con sentinella nota e `refute log =~ sentinel`.
- [ ] **S3** — `secret_key_base` ≥64 byte; app rifiuta startup altrimenti.
- [ ] **S4** — Cookie con firma invalida → trattato come "no cookie", redirect a `/login`, nessun errore al client. Test forge cookie tampered.

### Operational / configuration
- [ ] **O1** — Boot fallisce con `raise` se `WORKSPACE_PASSWORD` mancante o `<12` char; HTTP listener non si apre.
- [ ] **O2** — Boot fallisce con `raise` se `SECRET_KEY_BASE` mancante o `<64` byte.
- [ ] **O3a** — Env var documentate nel README (Step 8).
- [ ] **O3b** — Env var configurate su Gigalixir prima del primo deploy → **deploy-time gate, fuori scope di questa slice** (slice ∞ deploy).
- [ ] **O4** — Sessioni esistenti sopravvivono al riavvio dell'endpoint con stesso `SECRET_KEY_BASE` + stesso `WORKSPACE_PASSWORD`. **Automatizzato** via test che restart-a `IdeajarWeb.Endpoint` con la stessa secret e verifica che un cookie firmato precedentemente sia ancora accettato (Step 6).

### Performance / UX
- [ ] **P1** — Submit errato risponde in **[500ms, 1500ms]** (upper bound generoso per CI runner). Verificato in test dedicato `async: false` con override del delay.
- [ ] **P2** — Submit corretto: budget di design <200ms in produzione. **Post-deploy check** (`curl -w "%{time_total}"` documentato nel README); non Pre-PR gate.
- [ ] **P3** — Render del form di login senza accesso a DB. Verificato strutturalmente: `LoginController.new` non chiama `Repo.*`; test che sostituisce il Repo con un modulo che `raise` su qualunque chiamata e verifica che GET `/login` ritorni 200.

### Validation venue
- [ ] **V1** — Tre schermate user-facing (login vuoto, login con errore, post-login home) validate in DevTools mobile viewport (iPhone 13 + Pixel 7); 3 screenshot allegati alla PR. **Solo gli scenari visivi**, non scenari API/cookie.
- [ ] **V1a** — Lighthouse a11y score ≥95 su `/login` (target 100, soglia 95 per accomodare warning falsi-positivi su contrast nel placeholder).
- [ ] **V1b** — Walkthrough keyboard-only: Tab → field password → digita → Enter → submit. Documentato come "passa".
- [ ] **V2** — Validazione su dispositivo fisico mobile rinviata a slice 9 (PWA), post-deploy.

### Documentation / handoff
- [ ] **D1** — README con env var, comando `mix phx.gen.secret`, procedura di rotazione password. **Verifica automatica**: test che legge `README.md` e asserisce contiene `WORKSPACE_PASSWORD`, `SECRET_KEY_BASE`, `mix phx.gen.secret`.
- [ ] **D2** — `docs/conventions.md` con vincolo "lingua UI = italiano" e sezione "UI copy" con stringhe canoniche per slice 1.

### UI copy (canonical, da riusare in slice future)
| Elemento | Testo IT |
|----------|----------|
| Page `<title>` login | "ideajar — accesso" |
| Heading login | "ideajar" |
| Helper text login | "Inserisci la password condivisa per questo dispositivo." |
| Label password | "Password" |
| Submit button | "Entra" |
| Error generico | "Password errata" |
| Heading home placeholder | "Workspace privato" |

## User-Facing Behavior

> Scenari verbatim da `docs/specs/device-password-auth.md` **+ aggiunte** per coprire boot validation, cookie hardening, log non-leakage, return_to URL-encoded.

```gherkin
Feature: Device-level password authentication

  Background:
    Given the application has been deployed with WORKSPACE_PASSWORD set to "correct horse battery staple"

  # ── First access ────────────────────────────────────────────────────
  Scenario: First visit from a fresh device shows the login form
    Given my browser has no session cookie for this app
    When I visit "/"
    Then I am redirected to "/login"
    And I see a single password input field with label "Password"
    And I see a submit button labelled "Entra"
    And I see the helper text "Inserisci la password condivisa per questo dispositivo."
    And no other workspace content is visible

  Scenario: Successful login grants access and persists across reloads
    Given my browser has no session cookie for this app
    And I am on "/login"
    When I submit the password "correct horse battery staple"
    Then I am redirected to "/"
    And I see the workspace home
    And on subsequent visits within the same browser I am not asked for the password again

  Scenario: Login preserves the originally requested path
    Given my browser has no session cookie for this app
    When I visit "/some/protected/path"
    Then I am redirected to "/login?return_to=%2Fsome%2Fprotected%2Fpath"
    And the login form contains a hidden input "return_to" with value "/some/protected/path"
    When I submit the correct password
    Then I am redirected to "/some/protected/path"

  Scenario Outline: return_to is rejected when it points outside the app
    Given my browser has no session cookie for this app
    When I visit "/login?return_to=<value>"
    And I submit the correct password
    Then I am redirected to "/"

    Examples:
      | value                  |
      | https://evil.com       |
      | //evil.com             |
      | http://evil.com        |
      | %2F%2Fevil.com         |
      | javascript:alert(1)    |
      |                        |

  # ── Wrong password ──────────────────────────────────────────────────
  Scenario: Wrong password shows a generic error and does not authenticate
    Given my browser has no session cookie for this app
    And I am on "/login"
    When I submit the password "wrong"
    Then the response is delayed by at least 500 milliseconds and at most 1500 milliseconds
    And I see a generic error message "Password errata"
    And the error message has role "alert"
    And the password input has autofocus
    And I am still on the login form
    And no session cookie marking authentication is set

  Scenario: Repeated wrong passwords behave consistently
    Given my browser has no session cookie for this app
    When I submit a wrong password 10 times in a row
    Then each response is delayed by at least 500 milliseconds and at most 1500 milliseconds
    And each response shows the same generic error
    When I submit the correct password
    Then I am redirected to "/"

  Scenario: Empty password submission is treated as a wrong password
    Given my browser has no session cookie for this app
    And I am on "/login"
    When I submit an empty password field
    Then I see the same generic error and 500ms delay as for any wrong password

  Scenario: Wrong password is never written to logs
    Given my browser has no session cookie for this app
    When I submit the password "sentinel-leakage-canary-xyz"
    Then the captured application logs do not contain "sentinel-leakage-canary-xyz"

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
    When I send a POST request to "/" (or any route under :require_auth)
    Then I receive a 403 Forbidden response
    And I am not redirected
    And no side effect occurs

  # ── Tampered cookie ─────────────────────────────────────────────────
  Scenario: A tampered or invalid signed cookie is treated as no session
    Given my browser holds a session cookie whose signature does not validate
    When I visit "/"
    Then I am redirected to "/login"
    And the response status is 302 (not 500)

  # ── Sessions survive endpoint restart (= redeploy with same secret) ─
  Scenario: Existing sessions survive an endpoint restart with the same secret_key_base
    Given device A holds a signed session cookie produced with secret_key_base S
    When IdeajarWeb.Endpoint is stopped and restarted with the same S and same WORKSPACE_PASSWORD
    Then device A's next request to "/" returns 200 without showing the login form

  # ── Boot validation ─────────────────────────────────────────────────
  Scenario Outline: Boot fails on invalid WORKSPACE_PASSWORD
    Given the application starts with WORKSPACE_PASSWORD = <value>
    When runtime.exs is evaluated
    Then it raises with a message naming WORKSPACE_PASSWORD
    And the HTTP listener is not started

    Examples:
      | value         |
      |               |
      | shortpwd      |
      | 11charssss    |

  Scenario Outline: Boot fails on invalid SECRET_KEY_BASE
    Given the application starts with SECRET_KEY_BASE = <value>
    When runtime.exs is evaluated
    Then it raises with a message naming SECRET_KEY_BASE
    And the HTTP listener is not started

    Examples:
      | value                                  |
      |                                        |
      | only-32-bytes-long-aaaaaaaaaaaaaaa     |

  # ── Cookie hardening ────────────────────────────────────────────────
  Scenario: Session cookie has hardening attributes in :prod
    Given the application is configured for :prod environment
    When a successful login occurs
    Then the Set-Cookie response header contains "HttpOnly"
    And it contains "SameSite=Lax"
    And it contains "Secure"
    And it contains "Max-Age=315360000"

  # ── Public PWA assets routing ───────────────────────────────────────
  Scenario Outline: PWA asset paths are not gated by authentication
    Given my browser has no session cookie for this app
    When I request "<path>"
    Then the response is either 200 or 404
    And no redirect to "/login" occurs

    Examples:
      | path             |
      | /manifest.json   |
      | /sw.js           |
      | /icons/icon.png  |

  # ── Login form accessibility (UI contract) ──────────────────────────
  Scenario: Login form is accessible and password-manager-friendly
    Given my browser has no session cookie for this app
    When I visit "/login"
    Then the rendered HTML contains a <label> associated with the password input
    And the password input has autocomplete="current-password"
    And the password input has autofocus
    And the form posts to "/login" with a valid CSRF token
    And the error region is announceable (role="alert")
```

## Steps

### Step 1: Initialize Phoenix project ✅ DONE 2026-04-27

**Complexity**: standard
**RED**: ✅ `mix test` → `** (Mix) Could not find a Mix.Project`.
**GREEN**: ✅ `git init` + asdf toolchain (Erlang 26.2.5.20, Elixir 1.16.3-otp-26) + `mix archive.install hex phx_new` (1.8.5) + `yes | mix phx.new . --app ideajar --module Ideajar --database sqlite3 --no-mailer --no-dashboard --no-gettext --no-agents-md --install` + `mix ecto.create` + `mix test` → 5 tests, 0 failures.
**REFACTOR**: ✅ rimossi `lib/ideajar_web/controllers/page_controller.ex`, `page_html.ex`, `page_html/`, `test/.../page_controller_test.exs` (ripristinati in Step 5); rimossa rotta `get "/", PageController, :home` da router; aggiunto `{:credo, "~> 1.7", only: [:dev, :test], runtime: false}` a `mix.exs`; generato `.credo.exs`. Tests: 4 passed; format clean; credo (default) clean.
**Build deviations**:
- Phoenix 1.8.5 invece di 1.7+ (ultima stable disponibile, retrocompatibile per i nostri bisogni)
- `mix phx.new .` con `--app ideajar` invece di nested `mix phx.new ideajar` (cartella già contiene CONTEXT.md/docs/plans/.git, scaffold flat preferito)
- `--no-agents-md` aggiunto (non parte del piano originale ma allineato a "no doc files unless asked")
- Credo `--strict` → `default mode` (vedi nota in pre-PR gate)
**Files**: scaffold Phoenix completo + `mix.exs` con Credo + `.credo.exs` + `.tool-versions` (asdf).
**Commit**: via skill `commit-message`.
**Spec mapping**: prerequisito tecnico per tutti gli scenari.

### Step 2: Boot-time configuration validation in runtime.exs ✅ DONE 2026-04-27

**Implementato:** `Ideajar.Config.validate!/1` (signature `/1` con opts esplicite, deviazione minore dal piano: evita race "Application.get_env mid-runtime.exs evaluation"). 7 unit test boundary-aware (12-char, 64-byte). Integration smoke verificata manualmente: `WORKSPACE_PASSWORD=short mix run --no-start -e ":ok"` → `** (RuntimeError) WORKSPACE_PASSWORD is too short` con stacktrace che termina in `runtime.exs:41`. Defaults dev/test in `config/dev.exs` e `config/test.exs` (test password = "correct horse battery staple" da BDD Background; `wrong_password_delay_ms: 0` in test). 11 tests, 0 failures; format + credo clean. Fix criteria gate flag O1: nessun `:econnrefused` test, sostituito da smoke run + composition trust (validate! is line 41 of runtime.exs, before `config :ideajar, IdeajarWeb.Endpoint, secret_key_base: ...`).

**Complexity**: complex (security gate operativo)
**RED**: `test/ideajar/config_test.exs`:
1. `Ideajar.Config.validate!/0` con `WORKSPACE_PASSWORD` letto da `Application.get_env(:ideajar, :workspace_password)` mancante → `raise RuntimeError` con messaggio che cita `WORKSPACE_PASSWORD` e indica il valore minimo;
2. idem per `WORKSPACE_PASSWORD` `<12` char;
3. idem per `SECRET_KEY_BASE` `<64` byte (testato via `Application.get_env(:ideajar, IdeajarWeb.Endpoint)[:secret_key_base]`);
4. con env validi → ritorna `:ok`;
5. **integration test endpoint-binding**: avvia un task `Task.async/1` che chiama `Application.ensure_all_started(:ideajar)` con env mancante via `System.put_env`/`Application.put_env` setup → asserisce che il processo riceve `{:error, _}` e `:gen_tcp.connect/3` su porta endpoint fallisce con `:econnrefused`.
**GREEN**: `Ideajar.Config.validate!/0` (pure function); chiamata in cima a `config/runtime.exs` dopo aver letto le env var, **prima** della config dell'Endpoint. Niente validazione in `Application.start/2` (canonico Phoenix: `runtime.exs` raise = supervisore mai parte).
**REFACTOR**: messaggi di errore con istruzioni operative; costanti `@min_password_length 12`, `@min_secret_key_length 64` documentate.
**Files**: `lib/ideajar/config.ex`, `config/runtime.exs`, `test/ideajar/config_test.exs`.
**Commit**: `feat: validate WORKSPACE_PASSWORD and SECRET_KEY_BASE in runtime.exs`
**Spec mapping**: O1, O2, S3 + scenari "Boot fails on invalid …".

### Step 3: Login form rendering (GET /login) — accessible HTML ✅ DONE 2026-04-27

**Implementato:** `IdeajarWeb.LoginController.new/2` + `IdeajarWeb.LoginHTML` + template `login_html/new.html.heex` minimale e a11y-completo (label associato, autocomplete=current-password, autofocus, required, aria-describedby, role=alert sul container errore, hidden CSRF + return_to). Pipeline `:require_auth` definita vuota in router (verrà popolata Step 5). 4 test ConnTest: rendering completo con regex per ogni attributo, preservazione return_to da query, redirect a `/` se già autenticato, P3 no-DB-hit verificato via `:telemetry.attach` su `[:ideajar, :repo, :query]` + `refute_received`. Layout root: `lang="en"` → `lang="it"`, suffix `" · Phoenix Framework"` rimosso (slice è IT-only, no framework branding). Inline JS submit-disable mai aggiunto (YAGNI per design review). 15 tests passing total; format + credo clean.

**Complexity**: standard
**RED**: `test/ideajar_web/controllers/login_controller_test.exs`:
1. GET `/login` senza sessione → 200; HTML contiene:
   - `<title>ideajar — accesso</title>`,
   - `<h1>ideajar</h1>` (o ruolo equivalente),
   - testo "Inserisci la password condivisa per questo dispositivo.",
   - `<label for="password">Password</label>`,
   - `<input id="password" name="password" type="password" autocomplete="current-password" autofocus required aria-describedby="login-error">`,
   - `<button type="submit">Entra</button>`,
   - hidden CSRF token (`<input type="hidden" name="_csrf_token">`),
   - hidden `<input type="hidden" name="return_to" value="">` (vuoto se nessun query param);
2. GET `/login?return_to=/x` → hidden input `return_to` ha value `/x`;
3. GET `/login` con sessione `:authenticated => true` → 302 a `/`;
4. **Test P3**: GET `/login` con `Repo` sostituito da modulo che `raise` → ritorna 200 (no DB hit).
**GREEN**: pipeline `:browser` (scaffold) + nuova pipeline `:require_auth` (singolo plug `IdeajarWeb.RequireAuth`, definito in Step 5). Rotta `get "/login", LoginController, :new` sotto `:browser` (no `:require_auth`). `LoginController.new/2` con check sessione + lettura `return_to` da query. Template `login_html/new.html.heex` con HTML completo e a11y.
**REFACTOR**: estrarre helper `pending_button_attrs` per disabilitare submit on click via attributo HTML standard `<button form="..." onsubmit="this.disabled=true">` o uso di `phx-disable-with` se LiveView wrap (per ora plain form: tiny inline JS `onsubmit="this.querySelector('button').disabled=true"`).
**Files**: `lib/ideajar_web/router.ex`, `lib/ideajar_web/controllers/login_controller.ex`, `lib/ideajar_web/controllers/login_html.ex`, `lib/ideajar_web/controllers/login_html/new.html.heex`, test.
**Commit**: `feat: render accessible login form with autofocus and password autocomplete`
**Spec mapping**: scenari "First visit", "Already authenticated visit to /login redirects home", "Login form is accessible". Acceptance P3, V1a, V1b.

### Step 4: Password verification on POST /login (constant-time, no leakage)

**Complexity**: complex (security-critical)
**RED**: `test/ideajar/auth_test.exs` (puro):
1. `Ideajar.Auth.authenticate("correct horse battery staple")` → `:ok` (la password configurata viene letta da `Application.get_env`);
2. `Ideajar.Auth.authenticate("wrong")` → `:error`;
3. `Ideajar.Auth.authenticate("")` → `:error`;
4. **delay parametrizzato**: `Ideajar.Auth.authenticate("wrong", wrong_password_delay_ms: 50)` ritorna `:error` in ~50ms (test rapido); `Ideajar.Auth.authenticate("wrong", wrong_password_delay_ms: 0)` ritorna `:error` in <10ms.

`test/ideajar_web/controllers/login_controller_test.exs` (`async: true` con delay = 0 da `config/test.exs`):
1. POST con password corretta → 302; `get_session(conn, :authenticated) == true`;
2. POST con password errata → 200; body contiene "Password errata"; `role="alert"` sul container errore; password input mantiene `autofocus`; nessuna sessione settata; **valore della password NON ripopolato nel `value` attribute**;
3. POST con password vuota → identico al caso "errata";
4. POST con `return_to=/x` (hidden input) → redirect a `/x`;
5. POST con `return_to=https://evil.com` → redirect a `/` (sanitization via `IdeajarWeb.SafeRedirect.normalize/1`);
6. **Log non-leakage**: usando `ExUnit.CaptureLog`, POST con password "sentinel-leakage-xyz" → `refute log =~ "sentinel-leakage-xyz"`;
7. POST 10 volte con password errata + 1 volta con corretta → tutti i 10 falliscono con stesso errore, l'11esimo ha successo.

`test/ideajar_web/controllers/login_timing_test.exs` (**`async: false`**, file separato):
1. setup: `Application.put_env(:ideajar, :wrong_password_delay_ms, 500)` + `on_exit` reset;
2. POST con password errata → durata via `:timer.tc/1` `>= 500_000` µs e `<= 1_500_000` µs.

**GREEN**:
- `Ideajar.Auth.authenticate(submitted, opts \\ [])`: legge `Application.get_env(:ideajar, :workspace_password)`, fa `Plug.Crypto.secure_compare/2`, applica `Process.sleep(Keyword.get(opts, :wrong_password_delay_ms, default_delay()))` su miss prima di tornare `:error`. La password configurata **non lascia mai** questo modulo. Default `default_delay/0` legge da `Application.get_env(:ideajar, :wrong_password_delay_ms, 500)`.
- `LoginController.create/2`: chiama `Ideajar.Auth.authenticate(params["password"])`; on `:ok` → `put_session(:authenticated, true)` + `redirect(to: IdeajarWeb.SafeRedirect.normalize(params["return_to"]))`; on `:error` → render con flash error, no echo della password.
- `IdeajarWeb.SafeRedirect.normalize/1`: ritorna path se inizia con `/` e non con `//`, altrimenti `/`.

**REFACTOR**: aggiungere modulo `IdeajarWeb.SafeRedirect` (web layer, non `Ideajar.*`); test correlato `test/ideajar_web/safe_redirect_test.exs`. `config/test.exs` setta `wrong_password_delay_ms: 0` di default.
**Files**: `lib/ideajar/auth.ex`, `lib/ideajar_web/controllers/login_controller.ex`, `lib/ideajar_web/safe_redirect.ex`, `lib/ideajar_web/controllers/login_html/new.html.heex` (slot errore + role=alert), `config/test.exs`, test.
**Commit**: `feat: authenticate login with constant-time compare, no leakage, configurable delay`
**Spec mapping**: scenari "Successful login", "Wrong password", "Repeated wrong passwords", "Empty password", "Login preserves return_to", "return_to outside app", "Wrong password is never logged". Acceptance F1, F2, S1, S2, P1.

### Step 5: RequireAuth plug + protected home page (merged)

**Complexity**: complex (security boundary + integration di pipeline reale)
**RED**: `test/ideajar_web/controllers/page_controller_test.exs`:
1. GET `/` senza sessione → 302 a `/login?return_to=%2F`;
2. GET `/` autenticato (sessione `:authenticated => true`) → 200, body contiene "Workspace privato";
3. POST `/` senza sessione → 403 (Phoenix risponderà 405 di default su POST a una rotta GET-only — rispondere 403 esplicitamente dal plug `RequireAuth`);
4. cookie firmato manomesso (vedi tecnica sotto) → redirect a `/login`, status 302 (non 500).

**Tecnica per cookie tampered**: in setup, esegui un login completo per ottenere un cookie firmato valido; poi `String.replace_suffix(cookie, last_4_chars, "XXXX")` per romperne la firma; reinjection via `Plug.Conn.put_req_cookie/3`; assert risposta 302 a `/login`.

**GREEN**: `IdeajarWeb.RequireAuth` plug (`init/1`, `call/2`). Logica: legge `get_session(conn, :authenticated)`; se `true` → pass; se `nil`/`false` → su GET redirect a `/login?return_to=<encoded conn.request_path>`, su altri verbi `send_resp(403, "")` + `halt`. La `safe_return_to` per costruire l'URL di redirect è privata al plug (helper interno, non riusato altrove perché LoginController usa `SafeRedirect.normalize/1` su input client). Pipeline `:require_auth` aggiunta a router. Rotta `get "/", PageController, :home` sotto `pipe_through [:browser, :require_auth]`. PageController.home + template HEEx minimale con heading "Workspace privato".
**REFACTOR**: nessuno significativo; commenti di intent sul plug.
**Files**: `lib/ideajar_web/plugs/require_auth.ex`, `lib/ideajar_web/controllers/page_controller.ex`, `lib/ideajar_web/controllers/page_html.ex`, `lib/ideajar_web/controllers/page_html/home.html.heex`, `lib/ideajar_web/router.ex`, test.
**Commit**: `feat: add RequireAuth plug and protected home page`
**Spec mapping**: scenari "Returning device", "Second device separate", "Unauthenticated POST 403", "Tampered cookie", "Successful login grants access", "Login preserves return_to". Acceptance F1, S4.

### Step 6: Session cookie hardening + redeploy survival

**Complexity**: complex (configurazione di sicurezza con verifica multi-environment)
**RED**:
1. Test su `IdeajarWeb.Endpoint.session_options/0` (helper estratto): asserisce che il keyword list contiene `http_only: true`, `same_site: "Lax"`, `max_age: 315_360_000`;
2. Test che simula prod: caricamento di `config/prod.exs` via `Mix.Config.read!/1` o helper dedicato → asserisce `secure: true` nelle session_options di prod;
3. Test "redeploy survival": setup → login completo, salva il cookie ricevuto; `IdeajarWeb.Endpoint.stop()` + `IdeajarWeb.Endpoint.start_link()` con stesso `secret_key_base`; nuova `Plug.Conn` con il cookie salvato → GET `/` ritorna 200.

**GREEN**: estrarre `IdeajarWeb.Endpoint.session_options/0` come funzione che ritorna le opzioni di sessione (configurabili per env); aggiornare `Plug.Session` config in endpoint a usare l'helper. `config/prod.exs` aggiunge `secure: true` (override puntuale).
**REFACTOR**: commento sul perché `Max-Age=315360000` (10 anni, UX "login una volta"); commento sul perché `same_site: "Lax"` (no CSRF cross-origin ma form submit interno OK).
**Files**: `lib/ideajar_web/endpoint.ex`, `config/prod.exs`, `test/ideajar_web/endpoint_test.exs`.
**Commit**: `feat: harden session cookie (HttpOnly, SameSite=Lax, Secure in prod, 10y) + redeploy survival test`
**Spec mapping**: F3, O4, scenari "Session cookie has hardening attributes", "Existing sessions survive an endpoint restart".

### Step 7: Public asset routing scaffold (no placeholder files)

**Complexity**: standard
**RED**: `test/ideajar_web/asset_routing_test.exs`:
1. GET `/manifest.json` senza sessione → status `200` (se file esiste) o `404` (se non esiste); **mai 302 a `/login`**;
2. idem per `/sw.js`, `/icons/icon.png`;
3. asserzione esplicita: nessuno di questi path passa attraverso `RequireAuth`.

**GREEN**: in `IdeajarWeb.Endpoint`, estendere il `Plug.Static` `only:` list per includere i path PWA futuri (`~w(assets fonts images favicon.ico robots.txt manifest.json sw.js icons)`). `Plug.Static` short-circuita prima del router → automaticamente non passa per `:require_auth`. **Nessun file placeholder creato**: i file saranno aggiunti in slice 9. Commento in `endpoint.ex` che lista i path riservati per evitare collisioni con future rotte routed.
**REFACTOR**: nessuno.
**Files**: `lib/ideajar_web/endpoint.ex`, test.
**Commit**: `feat: reserve PWA asset paths in Plug.Static, bypass auth pipeline`
**Spec mapping**: scenario "PWA asset paths are not gated by authentication".

### Step 8: Documentation handoff (with automated checks)

**Complexity**: standard (passa da trivial a standard per via dei test automatici)
**RED**: `test/ideajar/docs_test.exs`:
1. legge `README.md` → asserisce contiene le stringhe `WORKSPACE_PASSWORD`, `SECRET_KEY_BASE`, `mix phx.gen.secret`, "rotazione password";
2. legge `docs/conventions.md` → asserisce contiene "lingua UI" o "UI language" e una sezione "UI copy" con almeno la stringa "Entra" (button label).
**GREEN**: scrivere `README.md` (sezioni: Prerequisiti, Env vars richieste, Generazione secret, Rotazione password, Procedura deploy Gigalixir — placeholder per slice ∞); scrivere `docs/conventions.md` (UI = IT, tabella copy canonica, riferimento a `docs/specs/` per i contratti).
**REFACTOR**: n/a.
**Files**: `README.md`, `docs/conventions.md`, `test/ideajar/docs_test.exs`.
**Commit**: `docs: README env vars + IT UI conventions with automated checks`
**Spec mapping**: D1, D2, O3a.

## Complexity Classification

| Step | Complessità | Motivazione |
|------|-------------|-------------|
| 1 | standard | scaffolding multi-file ben rodato |
| 2 | **complex** | gate operativo, fail-fast su misconfig, integration test endpoint binding |
| 3 | standard | controller + template HEEx, ma con contratto a11y dettagliato |
| 4 | **complex** | constant-time, no leakage, delay parametrizzato, `ExUnit.CaptureLog` |
| 5 | **complex** | security boundary + 403 vs redirect + tampered cookie test |
| 6 | **complex** | endpoint restart in test, multi-environment cookie attributes |
| 7 | standard | solo routing/config, zero contenuto |
| 8 | standard | doc + test che leggono i file |

## Pre-PR Quality Gate

- [ ] `mix test` passa (incluso `login_timing_test.exs` async:false e `docs_test.exs`).
- [ ] `mix format --check-formatted` passa.
- [ ] `mix credo` (default mode) passa. *Build deviation: il piano originale richiedeva `--strict`, ma il Phoenix 1.8 scaffold ha 5 issue [D]/[R] in codice template (DataCase, CoreComponents, ideajar_web.ex, application.ex). Default mode copre tutti gli errori di priorità senza combattere il template; le issue --strict sono stilistiche, non difetti.*
- [ ] `/code-review` su file toccati passa.
- [ ] **F1 traceability**: ogni `Scenario:` Gherkin presente nel BDD ha almeno un test ExUnit che lo cita per nome (commento `# Scenario: …` sopra il `test "…" do`). Verifica via grep nella PR description.
- [ ] **V1**: 3 screenshot mobile-viewport (login vuoto, login errore, post-login home) allegati alla PR.
- [ ] **V1a**: Lighthouse a11y score ≥95 su `/login` (output allegato alla PR).
- [ ] **V1b**: keyboard-only walkthrough verbalmente confermato passa.
- [ ] README aggiornato (Step 8) e `docs_test.exs` verde.
- [ ] Acceptance Criteria della spec tutti spuntati.

## Risks & Open Questions

- **R1 — Async test race risolto**: il delay è ora un argomento opzionale di `Ideajar.Auth.authenticate/2` con default da config. I test rapidi passano `0`, il `login_timing_test.exs` (`async: false`) usa `put_env` + `on_exit`. Nessuna mutazione di stato globale durante test paralleli.
- **R2 — `secret_key_base` in dev**: `mix phx.gen.secret` genera 64 byte, supera la validazione.
- **R3 — LiveView socket session**: slice 2+ dovrà passare `:authenticated` da conn a socket via `:session` opzione del LiveView mount. Fuori scope qui, ma flaggato.
- **R4 — `mix archive.install hex phx_new`**: prerequisito locale, documentato in README Step 8.
- **R5 — Step 5+7 mergiati**: niente più test-router in `test/support/`. La rotta `/` reale è il caso di test del plug `RequireAuth`.
- **R6 — `Plug.Static` collision**: i path riservati in `only:` mascherano future rotte routed con stesso nome. Commento in `endpoint.ex` con la lista reserved per visibilità.
- **R7 — Test redeploy survival**: stop+start `IdeajarWeb.Endpoint` in test condivide la stessa `Application` env con `secret_key_base` invariato. Il test richiede ordine specifico (single-test execution) — usare tag `@tag :endpoint_restart` e file `async: false` se serve.
- **Q1 — gettext escluso**: confermato (UI=IT-only). Riaggiungere è fattibile ma non triviale per template esistenti.
- **Q2 — V1 venue**: DevTools desktop perde quirk Safari mobile. Accettato consapevolmente fino al deploy reale (slice 9).
- **Q3 — Lighthouse a11y target ≥95**: soglia conservativa (target 100). Se non raggiunta, il warning va indagato in /code-review prima del merge.

## Plan Review Summary

> Iter 2 review verdicts: **acceptance approve · design approve · UX approve · strategic approve**. All prior blockers resolved (F1↔O4 contradiction, login template a11y). Below: warnings to carry into implementation, plus the positive observations from each reviewer.

### Warnings to track during /build

**Acceptance (4 warnings):**
- Step 6 OTP-level endpoint restart mechanics underspecified — alternative: prove the property at the cookie layer via `Plug.Crypto.MessageVerifier` round-trip with same `secret_key_base` (less invasive, equally diagnostic).
- "Repeated wrong passwords" Gherkin asserts per-attempt timing [500,1500ms] but Step 4 RED #7 runs with `delay=0` — move 10x test into `login_timing_test.exs` (`async: false`, real delay) or weaken the Gherkin to error parity only.
- Tampered cookie test asserts only status 302 — add explicit `refute response_body =~ ~r/cookie|signature|invalid/i` to fully cover S4 "no error leaked" clause.
- "Successful login persists across reloads" needs a cross-request test: reuse the Set-Cookie from login response on a fresh `Plug.Conn`, assert GET `/` 200 — the spec's "close tab and reopen" claim isn't verified by `get_session/2` on the same conn.
- Boot-validation and redeploy-survival Gherkin scenarios still leak module names (`runtime.exs`, `IdeajarWeb.Endpoint`) — minor wording cleanup.

**Design (4 warnings):**
- Step 6 uses deprecated `Mix.Config.read!/1` — switch to `Config.Reader.read!/1` or extract `IdeajarWeb.Endpoint.session_options(env)` and call directly with `:prod` in test (preferred: no file-system coupling).
- Step 4 needs explicit `config/test.exs` line setting `:workspace_password` to a known fixture (e.g., `"test-password-12chars"`) and tests should reference via `Application.fetch_env!/2`, not hardcoded literals.
- Step 3 inline JS `onsubmit=` for submit-disable is a YAGNI/CSP smell — drop it (no AC requires it) or move to `assets/js/app.js` keyed off `data-disable-on-submit`.
- Step 6 endpoint stop/restart is fragile under OTP supervision — prefer `start_supervised(IdeajarWeb.Endpoint, ...)` in an isolated process, or fall back to the cookie-layer round-trip alternative above.

**UX (2 warnings):**
- No-JS fallback for submit-pending state is thin — accept JS-required for PWA (document it) or add a CSS `:active` style for tactile feedback.
- Document explicitly that `required` attribute on the password input triggers native browser validation for empty submissions, sparing users the 500ms server delay on accidental empty submits (currently implicit).

**Strategic (4 warnings, plan already approved):**
- Step 7 (PWA scaffold) already simplified to no-placeholder-files in iter 2 — strategic concern resolved.
- Step 5+7 merge already done in iter 2 — strategic concern resolved.
- F1 traceability via `# Scenario:` grep checklist now in pre-PR gate — resolved.
- Async test race resolved via delay-as-argument pattern — resolved.

### Reviewer observations (preserved for context)

- **Acceptance**: thorough scenario coverage; binary verifiability now strong on all functional/security criteria.
- **Design**: password access centralized in `Ideajar.Auth` (single audit site); `SafeRedirect` correctly placed in web layer; `runtime.exs` validation is canonical Phoenix; merging Step 5+7 eliminates test-only routing infra; explicit comment on `Plug.Static only:` collision risk pays compound interest.
- **UX**: a11y contract testable not aspirational (label, autocomplete, autofocus, role=alert all asserted); IT copy table prevents drift across future slices; password-not-echoed is a nice subtle security/UX touch; Lighthouse + keyboard walkthrough are first-class gates.
- **Strategic**: slice boundary correctly chosen as foundation; rollback story is excellent (greenfield, no migrations, `git revert` + redeploy); R3 (LiveView session forwarding) correctly flagged as forward-warning for slice 2 not smuggled here; out-of-scope items respected (no recovery, lockout, multi-user).

### Net assessment

The plan is implementation-ready. The 10 warnings above are tracked for handling during `/build` (RED phase tests should incorporate the precise assertions; REFACTOR phase should clean up deprecated APIs and inline JS). None require structural revision before starting.
