# Plan: Slice 11a — SQLite → Postgres migration (local dev + test)

**Created**: 2026-05-03
**Branch**: main (trunk-based)
**Status**: approved
**Spec**: `docs/specs/sqlite-to-postgres-migration.md`

## Build conventions (carried from slice 1-10)

- **Strict TDD** — RED → GREEN → REFACTOR per step (when applicable; some steps are mostly mechanical config/file moves).
- Ogni commit attraverso la skill `commit-message`.
- Pre-step gate: `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo`, `mix deps.audit`, `mix test --include migration`.
- Slice 11a tocca Repo + config + tests, NO domain code, NO delivery code.
- Trunk-based su `main`, ogni step lascia il codebase committable (con la sola eccezione documentata in DD-S11A-1 dell'atomic step 2).

## Goal

Slice 11a porta dev + test environments su Postgres. Replace `ecto_sqlite3` con `postgrex`, swap `Ideajar.Repo` adapter, collassa le 9 migration esistenti (8 schema + 1 wipe one-shot) in 1 consolidated `initial_schema` migration + il `seed_categories` esistente. Aggiunge `docker-compose.yml` per Postgres locale. Aggiorna SQL emission pin nei test slice 4-9 (placeholder `?` → `$N`). Aggiorna CI per usare un Postgres service container.

Foundation: nessun production deploy ancora (slice 11b lo farà), quindi non c'è migration history da preservare.

Fuori scope: production deploy (slice 11b), `mix release`, runtime.exs prod block, HTTPS/SSL, V1/V2 manual gates slice 10.

## Decisioni architetturali pre-build

- **DD-S11A-1 — Step 2-3 atomic single commit (pre-build B)**: l'adapter swap (deps + Repo + config) e la migration consolidation NON possono essere committed separatamente — dopo lo swap, le 8 migration vecchie potrebbero rompere il `mix ecto.migrate` (sintassi minima differences SQLite vs Postgres + `wipe_slice2_dev_ideas` data migration assume schema esistente). Step 2 e step 3 originali → 1 step "Adapter swap + migration consolidation". Il commit resulting porta il codebase da SQLite-funzionante a Postgres-funzionante in un'unica unità atomica.

- **DD-S11A-2 — `change/0` per initial_schema (pre-build E)**: `Ecto.Migration.change/0` derive automatic-rollback per DDL puro. Initial_schema usa `change/0`. Seed_categories resta `up/0+down/0` perché è data migration con `Repo.insert_all` (Ecto non può auto-derivare il rollback di insert).

- **DD-S11A-3 — FK ON DELETE CASCADE per idea_categories (spec M4)**: `references(:ideas, on_delete: :delete_all)` e `references(:categories, on_delete: :delete_all)`. Postgres enforced di default. SQLite era no-op. Comportamento atteso: cancellando un'idea cascada via le row in idea_categories. Cancellando una categoria cascada le row idea_categories ma NOT le ideas (un'idea con un'altra categoria sopravvive). Verificare via test specifici (slice 4 idea_categories_constraint_test ha probabilmente coverage).

- **DD-S11A-4 — Schema field types (pre-build K)**: 
  - `title :string` (Postgres `varchar(255)` default; schema valida `max: 200` quindi OK) 
  - `description :text` (Postgres `text` unbounded; schema non ha limit)
  - `url :string` 
  - `duration :string` (Ecto.Enum cast a string; valid values via `validate_inclusion`)
  - `estimated_cost :integer`
  - `location_name :string` (max 200 in schema, default 255 in Postgres OK)
  - `lat :float`, `lng :float`
  - timestamps (`:naive_datetime` default Postgres = `timestamp without time zone`)

- **DD-S11A-5 — `MIX_TEST_PARTITION` support (pre-build D)**: keep pattern in `config/test.exs`. Even if couple-2-user CI uses single partition, future-proofing è cheap.

- **DD-S11A-6 — Postgres image: `postgres:16-alpine` locale + `postgres:16` CI (pre-build I)**: Alpine local è leggera. CI usa non-alpine (più tool di debug). Stesso major version per evitare surprise.

- **DD-S11A-7 — Migration test rewrite (spec T2)**: vecchio `migrations_test.exs` testava 8 migration distinte slice-by-slice (round-trip + idempotency per ognuna). Nuovo: testa SINGLE consolidated migration round-trip (up + down + up) + seed_categories idempotency. ~50 LOC vs ~300 LOC del vecchio.

- **DD-S11A-8 — `async: false` audit boundaries (pre-build H, spec T4)**: 5 file con `async: false`:
  - `test/ideajar/migrations_test.exs` — DB-wide ops, **resta `async: false`**
  - `test/ideajar/ideas_test.exs` — commentato "async: false matching ideas migration toggle". Dopo migration consolidation può tornare async. **VERIFICARE post-migration consolidation**.
  - `test/ideajar/ideas/filter_test.exs` — commentato "async: false matching IdeasTest". Idem. **VERIFICARE**.
  - `test/ideajar/ideas/idea_categories_constraint_test.exs` — verificare commento, probabilmente DB-wide.
  - `test/ideajar_web/controllers/login_timing_test.exs` — timing-sensitive, NON SQLite-specific. **Resta `async: false`**.

- **DD-S11A-9 — SQL emission test grep boundaries (pre-build G, spec T3)**: due file usano `Repo.to_sql/2` con regex placeholder:
  - `test/ideajar/ideas/filter_test.exs`
  - `test/ideajar/ideas_test.exs`
  - Update regex `\\?` → `\\$\d+` (e.g. `~r/<= \?/i` → `~r/<= \$\d+/i`).

- **DD-S11A-10 — `Ideajar.DataCase` setup (pre-build C)**: probabilmente già usa `Ecto.Adapters.SQL.Sandbox.checkout(Repo)` che è agnostic. Verificare ma niente da cambiare.

- **DD-S11A-11 — Manual timestamp generation (pre-build J)**: nuovi 2 migration file timestampati a mano: `20260503000001_initial_schema.exs` e `20260503000002_seed_categories.exs`. Un secondo di differenza per ordering deterministico.

- **DD-S11A-12 — README setup section integrale rewrite (spec R1, R2)**: il setup attuale probabilmente dice "mix ecto.create / mix ecto.migrate / mix test". Nuovo: "docker-compose up -d / mix deps.get / mix ecto.create / mix ecto.migrate / mix test". Aggiungere troubleshooting section: "se hai Postgres locale già installato sul 5432, fermalo o cambia la port mapping in docker-compose.yml".

- **DD-S11A-13 — CI workflow mantiene struttura attuale**: aggiunge solo block `services.postgres` + env vars + un step `mix ecto.create && mix ecto.migrate` prima di `mix test`. Non riscrive la pipeline.

- **DD-S11A-14 — Old SQLite db files cleanup**: `ideajar_dev.db` e `ideajar_test.db` se esistono al root devono essere `git rm` + `.gitignore` aggiornato per evitare ricomparse. Verificare lo stato di gitignore.

## Acceptance Criteria

> Mappatura uno-a-uno con `docs/specs/sqlite-to-postgres-migration.md`.

### Adapter swap

- [ ] **A1** — `mix.exs` deps include `:postgrex` and exclude `:ecto_sqlite3` + `:exqlite`.
- [ ] **A2** — `lib/ideajar/repo.ex` declares `adapter: Ecto.Adapters.Postgres`.
- [ ] **A3** — `config/dev.exs` has Postgres connection params.
- [ ] **A4** — `config/test.exs` Postgres params + Sandbox + `MIX_TEST_PARTITION` support.
- [ ] **A5** — `config/runtime.exs` not modified beyond what's strictly needed.

### Migration consolidation

- [ ] **M1** — `priv/repo/migrations/` has exactly 2 files post-slice.
- [ ] **M2** — `initial_schema.exs` creates 3 tables with all final fields.
- [ ] **M3** — Indexes per spec.
- [ ] **M4** — FK constraints with `ON DELETE CASCADE`.
- [ ] **M5** — `seed_categories.exs` idempotent insert_all.
- [ ] **M6** — `mix ecto.create && mix ecto.migrate` round-trip works on fresh DB.
- [ ] **M7** — `mix ecto.rollback` + `mix ecto.migrate` works (round-trip).

### Docker Compose

- [ ] **D1** — `docker-compose.yml` exists at root.
- [ ] **D2** — Named volume `ideajar_postgres_data`.
- [ ] **D3** — Port 5432.
- [ ] **D4** — Defaults match `config/dev.exs`.
- [ ] **D5** — `docker-compose up -d` works on fresh clone.

### Test suite passes on Postgres

- [ ] **T1** — `mix test --include migration` returns 830 tests, 0 failures.
- [ ] **T2** — Migration test rewritten for consolidated migration.
- [ ] **T3** — SQL emission regex pins updated to `\$\d+`.
- [ ] **T4** — `async: false` audit completed.
- [ ] **T5** — No test imports SQLite-specific module.

### CI provisioning

- [ ] **C1** — `services.postgres` block in CI.
- [ ] **C2** — Env vars `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `POSTGRES_HOST`.
- [ ] **C3** — `mix ecto.create && mix ecto.migrate` step in CI before tests.
- [ ] **C4** — CI green on push.

### README + docs

- [ ] **R1** — README setup starts with `docker-compose up -d`.
- [ ] **R2** — No SQLite references in README.
- [ ] **R3** — CONTEXT.md notes Postgres adapter.

### Out-of-scope guard

- [ ] **OS1** — `runtime.exs` prod block not modified beyond adapter line.
- [ ] **OS2** — No `releases:` block in `mix.exs`.
- [ ] **OS3** — No HTTPS/SSL/host/port additions.

### Operational / data

- [ ] **O1** — No domain code changes.
- [ ] **O2** — Test fixtures unchanged behavior.
- [ ] **O3** — `.gitignore` excludes any leftover SQLite db files.

## User-Facing Behavior

> BDD scenarios verbatim da `docs/specs/sqlite-to-postgres-migration.md`.

## Steps

### Step 1: Docker Compose foundation

**Complexity**: standard (no Elixir code change ancora; setup dev tooling)

**RED**:
1. `docker-compose.yml` exists at repo root (file-pin).
2. (Manual gate) `docker-compose up -d` brings up Postgres on `localhost:5432`.
3. README setup section starts with `docker-compose up -d`.
4. `.gitignore` includes `*.db` to prevent old SQLite files reappearing.

**GREEN**:
- `docker-compose.yml` con `postgres:16-alpine`, named volume, port 5432, defaults `ideajar/ideajar/ideajar_dev`.
- `.gitignore` aggiunge `*.db` se manca.
- README setup section riscritta.
- Cancella `ideajar_dev.db` e `ideajar_test.db` se esistono al root (verificare con `git ls-files`).

**REFACTOR**: nessuno.

**Files**: `docker-compose.yml` (new), `README.md` (extend), `.gitignore` (extend).
**Spec mapping**: D1, D2, D3, D4, D5, R1, R2, O3.

### Step 2: Adapter swap + migration consolidation (atomic)

**Complexity**: standard (mechanical but cross-file; commit unico per non lasciare codebase broken)

**RED**:
1. `mix.exs` deps contain `:postgrex` and NOT `:ecto_sqlite3` (post-fix).
2. `lib/ideajar/repo.ex` adapter is `Ecto.Adapters.Postgres`.
3. `config/dev.exs` and `config/test.exs` Postgres params.
4. `priv/repo/migrations/` ha exactly 2 files (verifica via `File.ls!` count).
5. `initial_schema.exs` creates the 3 tables (verifica via Postgres metadata query, e.g. `\dt` analog via Ecto query).
6. FK CASCADE: insert idea + idea_categories row, delete idea, idea_categories row gone.
7. `seed_categories.exs` insert idempotency: re-run → 8 rows (no duplicates).

**GREEN**:
- `mix.exs`:
  ```elixir
  # Remove
  - {:ecto_sqlite3, ">= 0.0.0"},
  # Add
  + {:postgrex, ">= 0.0.0"},
  ```
- `lib/ideajar/repo.ex`: adapter swap.
- `config/dev.exs`, `config/test.exs`: Postgres connection params per spec.
- Cancella `priv/repo/migrations/2026042*.exs` + `priv/repo/migrations/20260430000001_add_location_to_ideas.exs` (9 file).
- Crea `priv/repo/migrations/20260503000001_initial_schema.exs` con `change/0` che crea 3 tabelle + indexes + FK CASCADE.
- Crea `priv/repo/migrations/20260503000002_seed_categories.exs` con `up/0+down/0` (insert_all + on_conflict).
- Riscrivi `test/ideajar/migrations_test.exs` from scratch: round-trip up+down+up + seed idempotency. ~50 LOC.
- `mix deps.get && mix ecto.drop && mix ecto.create && mix ecto.migrate` localmente per verifica.

**REFACTOR**: docstring chiari sui nuovi migration file.

**Files**: `mix.exs`, `lib/ideajar/repo.ex`, `config/dev.exs`, `config/test.exs`, `priv/repo/migrations/*` (delete 9, create 2), `test/ideajar/migrations_test.exs`.
**Spec mapping**: A1, A2, A3, A4, A5, M1, M2, M3, M4, M5, M6, M7, T2, OS1, OS2, OS3, O1.

### Step 3: SQL emission pin updates + test suite green

**Complexity**: standard (search/replace mirato + verification)

**RED**:
1. Run `mix test --include migration` — molti test rompono (regex `\?` non match Postgres `$1`).

**GREEN**:
- `test/ideajar/ideas/filter_test.exs`: regex `\\?` → `\\$\d+` (es. `~r/IS\s+NOT\s+NULL/i` resta, ma any `~r/.+\?\s*/i` o equivalent va aggiornato).
- `test/ideajar/ideas_test.exs`: stesso treatment.
- Run `mix test --include migration` — verifica 830 test pass.
- Eventuali test che falliscono per altre ragioni (NULL ordering, FK CASCADE) — fix puntuali.

**REFACTOR**: nessuno.

**Files**: `test/ideajar/ideas/filter_test.exs`, `test/ideajar/ideas_test.exs` (+ eventuali altri se emergono).
**Spec mapping**: T1, T3, T5.

### Step 4: `async: false` audit + final test suite green

**Complexity**: standard

**RED**:
1. Per ogni file con `async: false` (5 totali pre-slice), verifica il commento attribuisce alla SQLite-specific behavior.
2. Cambia ad `async: true` dove il commento è SQLite-only.
3. Run `mix test --include migration` con concurrency.

**GREEN**:
- `test/ideajar/ideas_test.exs`: SQLite-specific → `async: true` se safe.
- `test/ideajar/ideas/filter_test.exs`: idem.
- `test/ideajar/ideas/idea_categories_constraint_test.exs`: review.
- `test/ideajar/migrations_test.exs`: resta `async: false` (DB-wide).
- `test/ideajar_web/controllers/login_timing_test.exs`: resta `async: false` (timing).

Re-run `mix test --include migration` — 830 test verde, magari più veloce con async.

**REFACTOR**: aggiorna i commenti `async: false` per riflettere la nuova ragione (non più SQLite).

**Files**: 3-4 test files possibili.
**Spec mapping**: T1, T4.

### Step 5: CI Postgres service + docs sync + plan flip

**Complexity**: standard

**RED**:
1. `.github/workflows/ci.yml` ha `services.postgres` block.
2. CI test step preceded by `mix ecto.create && mix ecto.migrate`.
3. `CONTEXT.md` notes Postgres adapter.
4. Push a feature branch (or simulate) — verifica CI green via `gh run list` (manual gate).

**GREEN**:
- `.github/workflows/ci.yml` aggiunge:
  ```yaml
  services:
    postgres:
      image: postgres:16
      env:
        POSTGRES_USER: ideajar
        POSTGRES_PASSWORD: ideajar
        POSTGRES_DB: ideajar_test
      ports:
        - 5432:5432
      options: --health-cmd "pg_isready -U ideajar" --health-interval 10s --health-timeout 5s --health-retries 5
  env:
    POSTGRES_HOST: localhost
    POSTGRES_USER: ideajar
    POSTGRES_PASSWORD: ideajar
    POSTGRES_DB: ideajar_test
  ```
  + step `mix ecto.create && mix ecto.migrate` prima del test step.
- `CONTEXT.md`: nota Postgres adapter post-slice-11a.
- Plan flip: `**Status**: approved` → `**Status**: implemented`.

**Files**: `.github/workflows/ci.yml`, `CONTEXT.md`, `plans/slice-11a-sqlite-to-postgres-migration.md`.
**Spec mapping**: C1, C2, C3, C4, R3.

## Complexity Classification

| Step | Complessità | Motivazione |
|------|-------------|-------------|
| 1 | standard | Docker Compose + README + gitignore. No code change. |
| 2 | standard | Adapter swap + migration consolidation atomic. Mechanical ma cross-file. |
| 3 | standard | SQL emission pin updates. Search/replace mirato. |
| 4 | standard | async audit. Mechanical review. |
| 5 | standard | CI workflow + docs. |

5 step totali (collapsed da 6 originali per via di DD-S11A-1). Tutti standard, no complex.

## Pre-PR Quality Gate

- [ ] `mix test --include migration` passa (830 tests, 0 failures).
- [ ] `mix format --check-formatted` exit code 0.
- [ ] `mix credo` passa.
- [ ] `mix deps.audit` passa.
- [ ] `mix compile --warnings-as-errors` passa.
- [ ] `/code-review` su file toccati passa.
- [ ] `docker-compose up -d` brings up Postgres successfully (manual).
- [ ] `mix ecto.create && mix ecto.migrate` round-trip works (manual on fresh DB).
- [ ] CI verde sul push.

## Risks & Open Questions

- **R11A-1 — FK CASCADE behavior change**: SQLite no FK enforcement, Postgres yes. Test esistenti che insert idea_categories row e poi cancellano l'idea — devono ora passare con CASCADE comportamento. Risk: alcuni test asseriscono "row resta" — improbable ma da verificare.

- **R11A-2 — NULL ordering edge case**: SQLite default NULLS FIRST con DESC, Postgres default NULLS LAST. Slice 4 base_query `ORDER BY inserted_at DESC, id DESC` — se `inserted_at` mai NULL (timestamps required), no impact. Schema dichiara `timestamps()` quindi NOT NULL. Probably safe, ma verificare.

- **R11A-3 — Postgres timezone handling**: `timestamps()` di default è `:naive_datetime` (no timezone). Postgres `timestamp without time zone`. Stesso treatment di SQLite. NULL safe.

- **R11A-4 — `description :text` vs `:string` migration**: vecchia migration può aver usato `:string` per description. Nuova usa `:text`. Test che asseriscono lunghezza max — improbable, ma verificare schema.

- **R11A-5 — `mix.exs` lock file**: dopo `mix deps.get` con postgrex aggiunto, `mix.lock` cambia. Committarlo.

- **R11A-6 — Old `*.db` files in working dir**: `ideajar_dev.db` e `ideajar_test.db` se erano committati o se il working dir li ha — `git rm` o cleanup. Aggiungi `*.db` a `.gitignore` se manca.

- **R11A-7 — Test files SQL emission count >2**: ho greppato e trovati 2 file (`filter_test.exs`, `ideas_test.exs`). Se durante l'implementazione emergono altri, fixare puntualmente in step 3.

- **R11A-8 — Migration `change/0` rollback for indexes**: Ecto deriva il rollback. Verifica via `mix ecto.rollback` post step 2.

- **R11A-9 — Postgres extensions**: NO extensions richieste. `pg_trgm` per future text search performance optimization è fuori scope (slice 8 usa LIKE).

- **R11A-10 — Connection pool size**: `pool_size: System.schedulers_online() * 2` in test, default `pool_size: 10` in dev. OK per couple-2-user.

- **R11A-11 — `ecto_sql` rimasto in deps**: `ecto_sql` è la dep meta che fornisce `Ecto.Adapters.SQL`. Resta. Solo `ecto_sqlite3` + `exqlite` vanno via.

- **R11A-12 — `MIX_TEST_PARTITION` env var clash**: in CI con un solo runner, è "" (empty). `database: "ideajar_test"` resta ok. Future-proof.

## Plan Review Summary

> Approval inline durante /build (auto mode). Iter1 reviewer dispatch deferred per scope semi-meccanico — slice 11a è 95% mechanical config moves + test fixes.
