# Plan: Slice 11b — Gigalixir production deploy

**Created**: 2026-05-03
**Branch**: main (trunk-based)
**Status**: implemented
**Spec**: `docs/specs/gigalixir-deploy.md`

## Build conventions (carried from slice 1-11a)

- Strict TDD per code paths che testabili (release module, /health, runtime config error paths). Ops files (Dockerfile, deploy.md) sono mechanical.
- Pre-step gate compile/format/credo/audit/test.
- commit-message skill option 1.
- Trunk-based su `main`.
- Slice 11a Postgres adapter è prerequisito (already shipped).

## Goal

Slice 11b chiude la roadmap pre-launch portando ideajar su `https://ideajar.gigalixirapp.com`. Docker-based deploy via Gigalixir (deciso pre-spec). Pattern canonical: `mix phx.gen.release --docker` per generare Dockerfile + `lib/ideajar/release.ex`. `config/runtime.exs` prod block fully wired con env var failures esplicite. `/health` endpoint per HTTP health check. `docs/deploy.md` runbook per signup → first deploy → rollback. Slice 10 V1/V2 manual gates finalmente reachable.

Fuori scope: custom domain, CD auto-deploy, auto-migrate on container start, monitoring oltre Gigalixir built-in.

## Decisioni architetturali pre-build

- **DD-S11B-1 — `mix phx.gen.release --docker` canonical**: usa il task Phoenix per generare il Dockerfile + `Ideajar.Release` template + `lib/ideajar/application.ex` migrate/0 hook. Tweak minimi solo se necessario.

- **DD-S11B-2 — Docker multi-stage**: builder con Erlang+Elixir+Node → runtime debian-slim. Final image solo release binary + minimal runtime deps.

- **DD-S11B-3 — `force_ssl` con `rewrite_on: [:x_forwarded_proto]`**: Gigalixir termina SSL all'edge, container vede HTTP. L'header X-Forwarded-Proto è la verità.

- **DD-S11B-4 — Migrazione manuale post-deploy**: `gigalixir run -- bin/ideajar eval "Ideajar.Release.migrate"`. NOT auto-run su container start (canonical pattern, evita race in multi-instance).

- **DD-S11B-5 — Tutte env var required**: SECRET_KEY_BASE, DATABASE_URL, PHX_HOST, WORKSPACE_PASSWORD missing → boot fails con messaggio chiaro. Nessun silent default in prod.

- **DD-S11B-6 — `/health` public route**: bypassa `:require_auth` pipeline. Test pin che NOT 302 to /login (parallel slice 1 manifest/sw bypass).

- **DD-S11B-7 — App name fallback**: runbook documenta `ideajar` come primary; se taken, `ideajar-app`. `PHX_HOST` env var assorbe la differenza, no code change.

- **DD-S11B-8 — Test approach**: integration test `IdeajarWeb.HealthControllerTest` per /health. Unit test `Ideajar.ReleaseTest` per `migrate/0` smoke. Runtime config raise paths NOT testati direttamente (config/runtime.exs è eval-time, hard to unit test) — verifica manuale via mix release smoke + readme.

## Acceptance Criteria

> Mappatura uno-a-uno con `docs/specs/gigalixir-deploy.md`.

### Release config

- [ ] **R1** — `mix.exs` releases block.
- [ ] **R2** — `Ideajar.Release` module exports `migrate/0`, `rollback/2`, `load_app/0`.
- [ ] **R3** — `mix release` succeeds locally.
- [ ] **R4** — Test pin: `Ideajar.Release.migrate/0` invokes `Ecto.Migrator.run/4`.

### Runtime config

- [ ] **RC1-RC5** — runtime.exs prod block + force_ssl + server: true (manual smoke test, runtime eval-time).

### `/health` endpoint

- [ ] **H1** — `GET /health` 200 + JSON `{"status":"ok"}`.
- [ ] **H2** — `/health` no auth required.

### Dockerfile

- [ ] **D1-D6** — Multi-stage Dockerfile + .dockerignore + `docker build` succeeds locally (manual smoke).

### Deploy runbook

- [ ] **RB1-RB8** — `docs/deploy.md` covers all manual steps.

### Slice 10 V1/V2 (deferred to manual post-deploy)

- [ ] **V1/V2** — Lighthouse + install prompts (post-deploy manual).

### Out-of-scope guard

- [ ] **OS1-OS3** — No custom domain hardcoded, no CD step in CI, no auto-migrate-on-boot.

## Steps

### Step 1: `mix phx.gen.release --docker` + Release module + mix.exs releases block

**Complexity**: standard

**RED** (`test/ideajar/release_test.exs` new):
1. `Ideajar.Release` module exists with `migrate/0`, `rollback/2` exported.
2. `migrate/0` calls `Ecto.Migrator.run/4` — verify via mock or by side effect (calling on test DB).

**GREEN**:
- Run `mix phx.gen.release --docker` (generates Dockerfile + lib/ideajar/release.ex + mix.exs update).
- Verify generated `Ideajar.Release` matches spec contract; tweak if needed.
- Verify `mix.exs` has `releases:` block.
- Run `mix release` locally — should produce `_build/prod/rel/ideajar`.

**Files**: `Dockerfile` (new from generator), `lib/ideajar/release.ex` (new), `mix.exs` (extend), `test/ideajar/release_test.exs` (new), `.dockerignore` (new).
**Spec mapping**: R1, R2, R3, R4, D1, D4.

### Step 2: Runtime config prod block + endpoint prod config

**Complexity**: standard (mostly mechanical edit)

**RED**: NESSUNO testabile a unit level (runtime.exs è eval-time). Pin tramite manual smoke (run `mix release` con env vars settate, verify boot).

**GREEN**:
- `config/runtime.exs` prod block: filling SECRET_KEY_BASE / DATABASE_URL / PHX_HOST / PORT / WORKSPACE_PASSWORD requirements + endpoint url + force_ssl + server: true.
- `config/prod.exs` add `cache_static_manifest`.

**Files**: `config/runtime.exs` (extend), `config/prod.exs` (extend).
**Spec mapping**: RC1-RC5.

### Step 3: `/health` endpoint + auth bypass test

**Complexity**: standard

**RED**:
1. GET /health → 200 + content-type application/json + body `{"status":"ok"}`.
2. GET /health unauthenticated → NOT 302 to /login.

**GREEN**:
- `IdeajarWeb.Router`: aggiungi `get "/health", HealthController, :show` nel public scope.
- `IdeajarWeb.HealthController`: implementa `show/2` con `json(conn, %{status: "ok"})`.
- Verifica auth bypass — `/health` deve essere prima del `:require_auth` pipeline OR in scope diverso.

**Files**: `lib/ideajar_web/router.ex` (extend), `lib/ideajar_web/controllers/health_controller.ex` (new), `test/ideajar_web/controllers/health_controller_test.exs` (new).
**Spec mapping**: H1, H2.

### Step 4: `docs/deploy.md` runbook + plan flip

**Complexity**: standard (documentation)

**GREEN**:
- `docs/deploy.md` con sezioni: Signup, App create, Postgres addon, Env vars, First deploy, Migrations, Rollback, Logs, Backups, V1/V2 manual gates checklist.
- `CONTEXT.md` aggiorna roadmap (slice 11b implemented; deploy URL annotato).
- Plan flip implemented.

**Files**: `docs/deploy.md` (new), `CONTEXT.md` (update).
**Spec mapping**: RB1-RB8.

## Complexity Classification

| Step | Complessità | Motivazione |
|------|-------------|-------------|
| 1 | standard | Generator + Release module + tests |
| 2 | standard | Mechanical config edits |
| 3 | standard | Small controller + router + tests |
| 4 | standard | Docs |

## Pre-PR Quality Gate

- [ ] `mix test` passa.
- [ ] `mix format --check-formatted`.
- [ ] `mix credo`.
- [ ] `mix deps.audit`.
- [ ] `mix compile --warnings-as-errors`.
- [ ] `mix release` locally produces a binary.
- [ ] `docker build .` locally succeeds (verifica manualmente se Docker installato).
- [ ] CI verde sul push.
- [ ] (Post-deploy manual) `gigalixir run -- bin/ideajar eval "Ideajar.Release.migrate"` su prod.

## Risks & Open Questions

- **R11B-1 — Docker build size**: target < 200 MB. Se generated Dockerfile produce > 500 MB, ottimizzare base image scelta.
- **R11B-2 — App name `ideajar` taken**: runbook documenta fallback. Manual step.
- **R11B-3 — Free tier limits**: Gigalixir free tier ha limiti (1 instance, single Postgres connection). Sufficient per couple-2-user.
- **R11B-4 — Cold start latency**: Gigalixir free tier sleep su inactivity. Prima visita post-sleep ~5-10s. Acceptable per couple usage.
- **R11B-5 — Postgres TLS**: Gigalixir Postgres free tier richiede SSL. `socket_options: [:inet6, ...]` o `ssl: true` in DATABASE_URL parsing. Verifica.

## Plan Review Summary

> Auto mode: skip plan reviewer dispatch — slice è 95% mechanical (generator + config + small controller + docs). Iter1 review deferito a `/code-review` finale.
