# Spec: Gigalixir production deploy (slice 11b)

> Slice 11b. Gets ideajar onto a public HTTPS URL via Gigalixir's
> Docker-based deploy path. Generates a Phoenix release + Dockerfile
> via the canonical `mix phx.gen.release --docker`, adds an
> `Ideajar.Release` module for post-deploy migrations, fills in the
> `config/runtime.exs` prod block (SECRET_KEY_BASE, PHX_HOST, PORT,
> DATABASE_URL, WORKSPACE_PASSWORD), exposes `/health` for Gigalixir's
> HTTP health probe, and ships a `docs/deploy.md` runbook covering
> the manual signup + app create + Postgres addon + first push.
> The default `ideajar.gigalixirapp.com` subdomain is the launch URL —
> custom domain is deferred. Slice 10's V1/V2 manual gates (Lighthouse
> PWA + install prompt) become reachable here for the first time
> because the env now serves over HTTPS.

## Intent Description

Slice 11b chiude la roadmap pre-launch portando ideajar su un URL
pubblico HTTPS che la coppia possa usare quotidianamente dal telefono.
La scelta è **Gigalixir + Docker** (deciso pre-spec): più controllo
del buildpack flow, Dockerfile canonical generato da
`mix phx.gen.release --docker`. La piattaforma offre Postgres free
tier (slice 11a già su Postgres → no DB migration ulteriori) + Let's
Encrypt SSL automatico sul subdomain `*.gigalixirapp.com`.

**Default domain**: `ideajar.gigalixirapp.com`. Se il name è già
preso, fallback documentato nel runbook (`ideajar-app`,
`ideajar-prod`). Custom domain è deferred — non c'è in scope.

**Manual one-time setup** (in `docs/deploy.md`):
1. `gigalixir signup` (e-mail, payment method per il free tier — la
   carta è richiesta ma non addebitata fino al threshold)
2. `gigalixir create -n ideajar` (claim del nome)
3. `gigalixir pg:create --free` (Postgres addon, configura
   automaticamente `DATABASE_URL` env var)
4. Aggiungere il git remote `gigalixir`
5. Set delle env var: `SECRET_KEY_BASE` (generato via `mix phx.gen.secret`),
   `WORKSPACE_PASSWORD` (utente sceglie il valore), `PHX_HOST`
6. `git push gigalixir main` → Gigalixir build via Dockerfile +
   deploy
7. `gigalixir run -- bin/ideajar eval "Ideajar.Release.migrate"`
   per applicare le 2 migration al primo deploy
8. Visit `https://ideajar.gigalixirapp.com` → vede pagina di login

**Code changes** (in scope):
- `Dockerfile` (gen via `mix phx.gen.release --docker`)
- `lib/ideajar/release.ex` — `migrate/0` + `rollback/0` post-deploy hooks
- `mix.exs` — `releases:` config block
- `config/runtime.exs` — prod env vars filled in (DATABASE_URL già
  da slice 11a; aggiungere PHX_HOST, PORT, force_ssl wiring)
- `config/prod.exs` — `cache_static_manifest`, `server: true`
- `IdeajarWeb.Router` — public route `GET /health` returning 200
- `IdeajarWeb.HealthController` (or function-based router action) —
  body `{"status":"ok"}` JSON
- `.dockerignore` — exclude deps, _build, node_modules, etc.
- `docs/deploy.md` — operational runbook (signup, deploy, env vars,
  rollback, log access, Postgres restore)

**Out of scope**:
- Custom domain + DNS + Let's Encrypt CNAME
- Continuous deploy (auto-deploy on push) — manual `git push gigalixir`
- Backup automation oltre Gigalixir's free tier (single nightly)
- Monitoring beyond Gigalixir's logs/metrics dashboard
- Multi-region or HA setup (couple-2-user app, single region è ok)
- Docker image registry beyond Gigalixir's internal registry
- CI auto-trigger di gigalixir push
- Session store (cookie-based already in slice 1)

## User-Facing Behavior

```gherkin
Feature: Production deploy on Gigalixir

  Background:
    Given the developer has run `gigalixir signup` + created an `ideajar` app
    And `gigalixir pg:create --free` has been run
    And SECRET_KEY_BASE, WORKSPACE_PASSWORD, PHX_HOST env vars are set on Gigalixir

  # ── First deploy ────────────────────────────────────────────────
  Scenario: git push gigalixir main triggers a Docker build + release
    Given the developer is on `main` with the slice 11b code committed
    When the developer runs `git push gigalixir main`
    Then Gigalixir builds the Docker image using the project Dockerfile
    And the build succeeds (logs show the release artifact created)
    And the release container starts
    And the OTP application boots without raising

  Scenario: Migrations are applied via the Release module post-deploy
    Given the build is complete and the container is up
    When the developer runs `gigalixir run -- bin/ideajar eval "Ideajar.Release.migrate"`
    Then both migrations (initial_schema + seed_categories) are applied
    And the `categories` table has 8 canonical rows
    And `mix ecto.migrate` is NOT used in production (no Mix at runtime)

  # ── Production HTTP behavior ────────────────────────────────────
  Scenario: GET https://ideajar.gigalixirapp.com/ on first visit redirects to /login
    Given no session cookie
    When the browser visits "https://ideajar.gigalixirapp.com/"
    Then the response status is 302
    And the Location header is "/login"

  Scenario: HTTP requests are upgraded to HTTPS
    When the browser issues a GET on "http://ideajar.gigalixirapp.com/"
    Then the response is a 301/302 to https://...
    # Phoenix `force_ssl` directive in the prod endpoint config.

  Scenario: GET /health returns 200 with a JSON body
    When the browser requests "https://ideajar.gigalixirapp.com/health"
    Then the response status is 200
    And the body is JSON containing `"status":"ok"`
    And the route does NOT require authentication

  # ── Slice 10 PWA gates finally testable ─────────────────────────
  Scenario: Lighthouse PWA "Installable" audit passes against the deployed URL
    Given the app is deployed at https://ideajar.gigalixirapp.com
    When the developer runs Lighthouse PWA audit in DevTools
    Then "Installable" is green
    And "Has a registered service worker" is green
    And "Manifest has a maskable icon" is green
    # V1/V1a/V1b from slice 10, deferred to here.

  Scenario: Install prompt appears on Android Chrome
    Given the app is deployed at https://ideajar.gigalixirapp.com
    When the user visits the URL on Android Chrome
    Then the install prompt appears in the address bar (or Chrome menu)
    And tapping install adds the app to the home screen with the maskable icon
    # V2/V2a from slice 10.

  Scenario: Add to Home Screen works on iOS Safari
    Given the app is deployed at https://ideajar.gigalixirapp.com
    When the user visits the URL on iOS Safari + uses Share → Add to Home Screen
    Then the icon-192 PNG appears on the home screen
    And tapping it opens the app in standalone display
    # V2b from slice 10.

  # ── Env var contract ────────────────────────────────────────────
  Scenario: Missing SECRET_KEY_BASE on prod boot raises a startup error
    Given config/runtime.exs requires SECRET_KEY_BASE
    When the container starts without it set
    Then the OTP app fails to start
    And the error message instructs the operator to set the env var

  Scenario: Missing WORKSPACE_PASSWORD on prod boot raises a startup error
    Same shape — Ideajar.Config from slice 1 already enforces a
    minimum length; in prod the env var is the only source.

  Scenario: Missing DATABASE_URL on prod boot raises a startup error
    Same shape — runtime.exs raises with a helpful message.

  Scenario: Missing PHX_HOST on prod boot raises a startup error
    Same shape — required for cookie domain + URL generation.

  # ── Release module ──────────────────────────────────────────────
  Scenario: Ideajar.Release.migrate runs all pending migrations
    When the Release.migrate/0 function is invoked
    Then it loads the application without starting it
    And invokes Ecto.Migrator.run/4 for every Repo
    And exits cleanly when done

  Scenario: Ideajar.Release.rollback rolls back to a target version
    When the Release.rollback/2 function is invoked with a Repo and a target version
    Then it rolls back any migrations newer than the target
    And exits cleanly

  # ── Out-of-scope guard ──────────────────────────────────────────
  Scenario: Slice 11b does NOT introduce a custom domain
    When I read mix.exs / runtime.exs / Dockerfile
    Then no custom domain is hardcoded
    And the URL generation defaults to PHX_HOST env var

  Scenario: Slice 11b does NOT add CI auto-deploy
    When I read .github/workflows/ci.yml
    Then no `git push gigalixir` step exists
    # Manual deploy only — slice 12+ if/when CD becomes desirable.

  # ── Docker image hygiene ────────────────────────────────────────
  Scenario: Dockerfile produces a multi-stage release build
    When I read the Dockerfile
    Then it has a builder stage (mix deps + assets + release)
    And a runtime stage (minimal Alpine or Debian slim, no Erlang/Elixir build tools)
    And the final image does NOT include source code beyond _build/prod/rel/

  Scenario: .dockerignore excludes the typical noise
    When I read .dockerignore
    Then it excludes _build, deps, node_modules, .git, .elixir_ls, .vscode, *.db
```

## Architecture Specification

### Components

| Componente | Tipo | Responsabilità |
|---|---|---|
| `Dockerfile` | Build artifact | Multi-stage: builder (Erlang/Elixir + deps + assets + release) → runtime (slim image with the release binary). Generated from `mix phx.gen.release --docker` template + minor tweaks. |
| `.dockerignore` | Build hygiene | Exclude deps/, _build/, node_modules/, .git/, IDE files. |
| `lib/ideajar/release.ex` | Phoenix release module | `migrate/0` + `rollback/2` for post-deploy DB ops; `load_app/0` helper. Canonical Phoenix pattern. |
| `mix.exs` | Build config | New `releases:` config block with the `:ideajar` release definition. |
| `config/runtime.exs` (prod block) | Runtime config | Require + parse `SECRET_KEY_BASE`, `DATABASE_URL`, `PHX_HOST`, `PORT`, `WORKSPACE_PASSWORD` env vars. Configure endpoint URL, force_ssl, http port. |
| `config/prod.exs` | Compile-time prod config | `cache_static_manifest`, `server: true` on the endpoint, structured logger. |
| `IdeajarWeb.Router` | Routing | `GET /health` plug — public, no auth. |
| `IdeajarWeb.HealthController` | Controller | Returns `{:ok, %{status: "ok"}}` JSON. |
| `lib/ideajar_web.ex` `static_paths/0` | Static paths | NO change — slice 1/10 already in place. |
| `docs/deploy.md` | Ops runbook | Manual steps from signup to first push, env var checklist, log access, rollback procedure, Postgres restore from Gigalixir backup. |

### Interfaces

**`Ideajar.Release` module** (canonical Phoenix pattern):
```elixir
defmodule Ideajar.Release do
  @moduledoc """
  Tasks invoked from the release at deploy time. Mix is NOT available
  in the release, so `mix ecto.migrate` does not work — call these
  via `bin/ideajar eval "Ideajar.Release.migrate"`.
  """
  @app :ideajar

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
```

**`config/runtime.exs` prod block** (fully wired):
```elixir
if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "environment variable DATABASE_URL is missing.\nFor example: ecto://USER:PASS@HOST/DATABASE"

  config :ideajar, Ideajar.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6(System.get_env("ECTO_IPV6"))

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "environment variable SECRET_KEY_BASE is missing.\nGenerate one via: mix phx.gen.secret"

  host =
    System.get_env("PHX_HOST") ||
      raise "environment variable PHX_HOST is missing.\nFor example: ideajar.gigalixirapp.com"

  port = String.to_integer(System.get_env("PORT") || "4000")

  config :ideajar, IdeajarWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    server: true,
    force_ssl: [hsts: true, rewrite_on: [:x_forwarded_proto]]

  workspace_password =
    System.get_env("WORKSPACE_PASSWORD") ||
      raise "environment variable WORKSPACE_PASSWORD is missing"

  config :ideajar, :workspace_password, workspace_password
end
```

**`/health` endpoint**:
```elixir
# router.ex (public scope, no auth)
scope "/", IdeajarWeb do
  pipe_through :browser

  get "/health", HealthController, :show
end

# health_controller.ex
defmodule IdeajarWeb.HealthController do
  use IdeajarWeb, :controller

  def show(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end
end
```

### Constraints

- **No new domain code** — only delivery + ops.
- **`mix phx.gen.release --docker`** generates the Dockerfile; we tweak only if necessary.
- **Multi-stage Dockerfile**: builder stage has Erlang+Elixir+Node, runtime stage is `debian:bookworm-slim` (or `alpine:3.18` if Phoenix release works there) with only OpenSSL + libstdc++ + the release binary.
- **`Ideajar.Release.migrate`** invoked manually post-first-deploy. NOT auto in entrypoint (avoid race during multi-instance deploys; couple-2-user is single instance but pattern stays canonical).
- **`force_ssl` with `rewrite_on: [:x_forwarded_proto]`**: Gigalixir terminates SSL at the edge, so the Phoenix endpoint sees HTTP — the `X-Forwarded-Proto` header tells us the original scheme.
- **`PORT` env var**: Gigalixir provides this; the endpoint binds on it.
- **`DATABASE_URL` env var**: auto-set by `gigalixir pg:create --free`.
- **All env vars required at boot**: missing → raise with a helpful error message. No silent defaults in prod.
- **`/health` public**: NOT gated by `:require_auth`. Pinned via test.
- **Image registry**: Gigalixir's internal — no Docker Hub push needed.
- **No build-time secrets**: SECRET_KEY_BASE / WORKSPACE_PASSWORD / DATABASE_URL only at runtime.

### Dependencies

- **Erlang/OTP + Elixir versions** matching `.tool-versions` (set in Dockerfile builder stage).
- **Node** (in builder stage only) for `mix assets.deploy`.
- **No new Hex deps** — Phoenix releases ship with all needed runtime tooling.
- **Gigalixir CLI** (developer machine, install via `pip install gigalixir` or `brew install gigalixir`).

### Out of scope

- Custom domain
- Continuous deploy (auto-deploy on git push to main)
- Auto-migration on container start (manual `gigalixir run` instead)
- Backup automation beyond Gigalixir's free tier
- Monitoring beyond Gigalixir's built-in dashboard
- Multi-region / HA
- Session store change (stays cookie-based)
- WebSocket scaling considerations (single instance, no Phoenix.PubSub clustering needed)

## Acceptance Criteria

### Release config

- [ ] **R1** — `mix.exs` has a `releases:` block defining `:ideajar`.
- [ ] **R2** — `lib/ideajar/release.ex` exports `migrate/0`, `rollback/2`, `load_app/0`.
- [ ] **R3** — `mix release` succeeds locally (verifies the build works without Docker).
- [ ] **R4** — `Ideajar.Release.migrate/0` invokes `Ecto.Migrator.run/4` (test pin).

### Runtime config

- [ ] **RC1** — `config/runtime.exs` prod block requires `SECRET_KEY_BASE`, `DATABASE_URL`, `PHX_HOST`, `WORKSPACE_PASSWORD`.
- [ ] **RC2** — Each missing env var raises with a helpful error message.
- [ ] **RC3** — Endpoint configured with `url[host: host, port: 443, scheme: "https"]`.
- [ ] **RC4** — `force_ssl` with `rewrite_on: [:x_forwarded_proto]`.
- [ ] **RC5** — `server: true` on the endpoint (release runs the server).

### `/health` endpoint

- [ ] **H1** — `GET /health` returns 200 + JSON `{"status":"ok"}`.
- [ ] **H2** — `/health` does NOT require auth (regression pin parallel to slice 1 manifest/sw bypass).
- [ ] **H3** — `static_paths/0` does NOT need to include "health" (it's a router route, not a static asset).

### Dockerfile + image hygiene

- [ ] **D1** — `Dockerfile` exists at repo root, multi-stage.
- [ ] **D2** — Builder stage installs Erlang+Elixir matching `.tool-versions`, runs `mix deps.get --only prod` + `mix assets.deploy` + `mix release`.
- [ ] **D3** — Runtime stage is a slim base image (debian-slim or alpine), copies only the release artifact + minimal runtime deps.
- [ ] **D4** — `.dockerignore` excludes `_build/`, `deps/`, `node_modules/`, `.git/`, `*.db`, `priv/static/assets/` (regenerated at build).
- [ ] **D5** — Final image size reasonable (< 200 MB target, but no hard pin).
- [ ] **D6** — `docker build .` succeeds locally.

### Deploy runbook

- [ ] **RB1** — `docs/deploy.md` covers Gigalixir signup steps.
- [ ] **RB2** — `gigalixir create -n ideajar` (with fallback `ideajar-app` if name taken).
- [ ] **RB3** — `gigalixir pg:create --free`.
- [ ] **RB4** — `gigalixir config:set SECRET_KEY_BASE=$(mix phx.gen.secret)` + `WORKSPACE_PASSWORD=…` + `PHX_HOST=ideajar.gigalixirapp.com`.
- [ ] **RB5** — `git push gigalixir main` first deploy.
- [ ] **RB6** — `gigalixir run -- bin/ideajar eval "Ideajar.Release.migrate"` post-first-deploy.
- [ ] **RB7** — Rollback procedure (Gigalixir release rollback + DB rollback via `Release.rollback`).
- [ ] **RB8** — Log access (`gigalixir logs`) + Postgres restore (`gigalixir pg:backups`).

### Slice 10 V1/V2 manual gates (now reachable)

- [ ] **V1** — Lighthouse PWA audit Installable green on `https://ideajar.gigalixirapp.com`.
- [ ] **V1a** — Maskable icon green.
- [ ] **V1b** — Service worker green.
- [ ] **V2a** — Android device install + standalone display + splash + icon.
- [ ] **V2b** — iOS Safari Add-to-Home-Screen + standalone.

### Out-of-scope guard

- [ ] **OS1** — No custom domain hardcoded anywhere.
- [ ] **OS2** — `.github/workflows/ci.yml` does NOT add a `gigalixir push` step.
- [ ] **OS3** — No `Dockerfile.entrypoint` auto-runs migrations on container start.

### Operational / data

- [ ] **O1** — No new Hex deps.
- [ ] **O2** — No domain code changes.
- [ ] **O3** — Existing 820 tests stay green (no test logic depends on adapter or release config change).
- [ ] **O4** — `mix release` produces a working binary that boots and connects to dev DB locally (with PROD-like env vars in a quick smoke test).

## Consistency Gate

- [x] Intent unambiguo — Docker deploy via Gigalixir + manual ops runbook + V1/V2 gates from slice 10
- [x] Ogni behavior ha BDD scenario (deploy, migrate, /health, force_ssl, env var failures, Lighthouse, install prompts, out-of-scope guards)
- [x] Architecture senza over-engineering (canonical phx.gen.release, no auto-migrate-on-boot, no CD)
- [x] Termini consistenti (`Ideajar.Release`, `bin/ideajar eval`, `force_ssl rewrite_on x_forwarded_proto`, `gigalixirapp.com`)
- [x] No contradictions — manual deploy esplicito, custom domain esplicitamente fuori scope, slice 11a Postgres adapter prerequisite chiaramente assunto

**Verdict: PASS** — ready for `/plan`.
