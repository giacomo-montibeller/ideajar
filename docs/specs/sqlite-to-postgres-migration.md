# Spec: SQLite → Postgres migration (slice 11a)

> Slice 11a. Replaces `ecto_sqlite3` (+ `exqlite`) with `postgrex` and
> swaps the `Ideajar.Repo` adapter from `Ecto.Adapters.SQLite3` to
> `Ecto.Adapters.Postgres`. Local dev + test environments only — the
> Gigalixir production deploy is slice 11b. Migration history is
> rewritten (collapsed into one consolidated initial migration plus
> the seed_categories data migration) since the project has not yet
> shipped to production. Adds a committed `docker-compose.yml` so
> contributors get Postgres locally with a single command. Updates CI
> to provision Postgres as a service container. SQL emission pins
> across slices 4/5/6/7b/8/9 are updated to the Postgres `$N`
> placeholder syntax. `async: false` directives that were SQLite-
> specific can be re-enabled where Postgres makes them unnecessary.

## Intent Description

Slice 11a chiude il primo dei due step deploy-related ("Postgres
migration + Gigalixir deploy") che sbloccano il rilascio agli utenti
reali. L'obiettivo è **portare dev + test environments su Postgres**,
così che slice 11b possa concentrarsi solo su release config, secrets,
e meccanica deploy senza dover ALSO gestire il Repo adapter switch.

**Migration history rewrite**: il progetto non è ancora deployato in
production, quindi non esiste storia di migration su DB esistenti da
preservare. Le 8 migration esistenti (`20260427000001_create_ideas`,
`20260428000001_create_categories`, ..., `20260430000001_add_location_to_ideas`)
vengono **collassate in un singolo `initial_schema` migration** che
crea le 3 tabelle finali con tutti i campi attuali. La data migration
`seed_categories` resta ma con timestamp aggiornato. Le 8 migration
vecchie (più la `wipe_slice2_dev_ideas` che era una pulizia dev one-
shot) vengono **cancellate**. Razionale: 8 migration distinte hanno
senso per "story" o per re-run su DB esistenti, neither apply qui.

**Docker Compose committato**: `docker-compose.yml` al root del repo
con un singolo service `postgres:16-alpine` (matching la versione che
useremo su Gigalixir slice 11b). Volume named `ideajar_postgres_data`
per persistence locale tra restart. User/password/DB hardcoded a
valori dev (`ideajar/ideajar/ideajar_dev`). README sez. Setup
aggiornata: `docker-compose up -d` come prima cosa, poi
`mix ecto.create && mix ecto.migrate`.

**SQL emission pin update**: slice 4/5/6/7b/8/9 hanno test che asseriscono
`{sql, _params} = Repo.to_sql(:all, query)` + regex tipo
`~r/WHERE "estimated_cost" <= \?/i`. Postgres usa `$1, $2, ...`
placeholders. Update a `~r/WHERE "estimated_cost" <= \$\d+/`. Search
+ replace mirata, no logica cambiata.

**`async: false` review**: vari test slice 1-9 usano `use Ideajar.DataCase, async: false`
con commenti tipo "SQLite Sandbox :auto race". Postgres Sandbox
gestisce concurrent transactions correttamente. Riabilitare
`async: true` dove il commento attribuiva la disabilitazione SOLO a
SQLite specifics. Lasciare `async: false` se c'è altro motivo (shared
mutable state, file system, etc.).

**Test suite preservation**: 830 test esistenti devono passare su
Postgres. Lavoro reale qui:
- SQL emission pins update (~5-10 test files toccati)
- Migration test riscritto from scratch — single consolidated migration
- `async: false` re-evaluation
- NULL ordering edge case verification (Postgres default NULLS LAST con DESC vs SQLite NULLS FIRST)
- FK enforcement (Postgres enforced di default, SQLite no — qualsiasi violazione che SQLite ignorava ora si rompe esplicitamente)

**CI update**: `.github/workflows/ci.yml` aggiunge service Postgres
container, env vars per la connection, step `mix ecto.create &&
mix ecto.migrate` prima di `mix test`.

**Out of scope**:
- Production deploy (slice 11b)
- `mix release` config
- HTTPS/SSL, Phoenix endpoint host/port
- V1/V2 manual gates slice 10 (richiedono deployed env)
- Backup strategy per Postgres dev
- Performance tuning oltre indexes esistenti
- Multi-tenant separation
- Connection pooling tuning oltre i defaults

## User-Facing Behavior

```gherkin
Feature: Local dev + test run on Postgres

  Background:
    Given Docker is installed on the developer machine
    And the repo contains docker-compose.yml at the root

  # ── Local dev setup ─────────────────────────────────────────────
  Scenario: First-time dev brings up Postgres + creates dev DB
    Given a fresh clone of the repo
    When the developer runs `docker-compose up -d`
    Then a Postgres 16 container starts on localhost:5432
    And the named volume `ideajar_postgres_data` is created
    When the developer runs `mix ecto.create && mix ecto.migrate`
    Then `ideajar_dev` database exists on the Postgres container
    And the schema contains tables `ideas`, `categories`, `idea_categories`
    And the categories table is seeded with the 8 canonical names

  Scenario: Restarting the Postgres container preserves the dev DB
    Given the dev DB has data
    When the developer runs `docker-compose down && docker-compose up -d`
    Then the data is still there (volume persistence)

  Scenario: README setup section is up to date
    When the developer reads README
    Then the setup section says to run `docker-compose up -d` first
    And it says to run `mix ecto.create && mix ecto.migrate` second
    And it does NOT say to install SQLite

  # ── Test run on Postgres ────────────────────────────────────────
  Scenario: Test suite passes on Postgres
    Given Postgres is up and `ideajar_test` database exists
    When the developer runs `mix test --include migration`
    Then all 830 tests pass
    And no test references SQLite-specific behavior
    And SQL emission pins use Postgres `$N` placeholder syntax

  Scenario: Test sandbox is Ecto.Adapters.SQL.Sandbox in :manual mode
    Given a test process checks out a connection
    When two async tests run concurrently
    Then they each see their own transaction (no cross-test pollution)
    And neither blocks the other

  # ── Migration consolidation ─────────────────────────────────────
  Scenario: priv/repo/migrations contains 2 files (initial + seed)
    When the developer lists priv/repo/migrations
    Then exactly 2 files exist:
      - <new_timestamp>_initial_schema.exs
      - <new_timestamp+1>_seed_categories.exs
    And no file matches the old slice-1..7 timestamps (20260427* through 20260430*)

  Scenario: initial_schema migration creates the final schema
    Given a fresh empty database
    When `mix ecto.migrate` runs
    Then the `ideas` table has columns: id, title, description, url,
         duration, estimated_cost, location_name, lat, lng, inserted_at, updated_at
    And the `categories` table has columns: id, name (unique), display_order,
         inserted_at, updated_at
    And the `idea_categories` join table has columns: id, idea_id, category_id,
         inserted_at, updated_at
    And FKs `idea_categories.idea_id → ideas.id` and `idea_categories.category_id → categories.id`
        are enforced
    And the appropriate indexes exist (categories.name unique, idea_categories.idea_id,
        idea_categories.category_id, etc.)

  Scenario: seed_categories migration inserts the 8 canonical categories idempotently
    Given the schema is migrated
    When the seed migration runs (or re-runs)
    Then the 8 canonical category names exist exactly once
    And re-running does NOT create duplicates (on_conflict: :nothing)

  Scenario: Migration round-trip up + down + up restores the schema
    Given the schema is migrated
    When the consolidated migration's down/0 is invoked
    Then the 3 tables are dropped
    When up/0 is invoked again
    Then the schema is recreated

  # ── Adapter swap ────────────────────────────────────────────────
  Scenario: mix.exs lists postgrex and not ecto_sqlite3
    When I read mix.exs
    Then the deps include `:postgrex`
    And they do NOT include `:ecto_sqlite3` or `:exqlite`

  Scenario: Ideajar.Repo uses the Postgres adapter
    When I read lib/ideajar/repo.ex
    Then it declares `adapter: Ecto.Adapters.Postgres`
    And NOT `Ecto.Adapters.SQLite3`

  Scenario: dev/test config use Postgres connection params
    When I read config/dev.exs
    Then it has hostname/username/password/database for Postgres
    And it does NOT have a SQLite database file path
    Same for config/test.exs

  # ── SQL emission pins (slice 4-9 regression) ────────────────────
  Scenario: slice 4 max_cost SQL emission pin uses Postgres placeholder
    When I read the test that asserts `WHERE "estimated_cost" <=` regex
    Then the regex accepts `$N` (e.g. `\$\d+`) instead of `?`

  Scenario: slice 5 durations IN clause SQL emission pin uses Postgres array
    When I read the test that asserts `IN ($1, $2, ...)` style emission
    Then the regex matches the Postgres syntax

  Scenario: slice 6 max_cost NULL-exclude pin
    When I read the test that asserts `IS NOT NULL` predicate
    Then the regex still matches (Postgres + SQLite emit identical for IS NOT NULL)

  Scenario: slice 8 text_search LIKE ESCAPE pin
    When I read the test that asserts `LOWER(...) LIKE LOWER(...) ESCAPE '\'`
    Then the regex still matches (Postgres + SQLite emit identical ESCAPE clauses)

  # ── async: false review ─────────────────────────────────────────
  Scenario: Tests previously async: false ONLY for SQLite reasons re-enabled to async: true
    When I review test files using `use Ideajar.DataCase, async: false`
    Then any case file whose comment cites SQLite-specific concurrency is async: true
    And cases with non-SQLite reasons remain async: false

  # ── CI provisioning ─────────────────────────────────────────────
  Scenario: CI workflow runs against Postgres service container
    When I read .github/workflows/ci.yml
    Then it has a `services.postgres` block with image `postgres:16` (or similar)
    And it has env vars for the connection (POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB)
    And the test step is preceded by `mix ecto.create && mix ecto.migrate`

  # ── Out-of-scope guard ──────────────────────────────────────────
  Scenario: Slice 11a does NOT add production runtime config
    When I read config/runtime.exs
    Then the `if config_env() == :prod do ... end` block is unchanged from pre-slice-11a
    OR if changed, only updates the database adapter line; no SECRET_KEY_BASE,
       PORT, host, scheme additions
    # Slice 11b deploy will add those.

  Scenario: Slice 11a does NOT add a mix release config
    When I read mix.exs
    Then no `releases:` block is added
    # Slice 11b deploy will.

  # ── Migration test rewrite ──────────────────────────────────────
  Scenario: migrations_test.exs tests the consolidated migration
    When I read test/ideajar/migrations_test.exs
    Then it tests up + down + up round-trip on the single initial_schema migration
    And it tests the seed_categories idempotency (insert_all on_conflict)
    And it does NOT reference the old slice-by-slice migration modules

  # ── README + docs sync ──────────────────────────────────────────
  Scenario: README setup section reflects Postgres + docker-compose
    When I read README.md
    Then the setup section starts with `docker-compose up -d`
    And it does not reference SQLite

  Scenario: CONTEXT.md or similar updated for the adapter change
    When I read CONTEXT.md
    Then it notes the Postgres adapter (slice 11a) where appropriate
```

## Architecture Specification

### Components

| Componente | Tipo | Responsabilità |
|---|---|---|
| `mix.exs` | Build config | Replace `:ecto_sqlite3` with `:postgrex` in deps. |
| `lib/ideajar/repo.ex` | Ecto Repo | Switch `adapter: Ecto.Adapters.SQLite3` → `Ecto.Adapters.Postgres`. |
| `config/dev.exs` | Phoenix config | Postgres connection params (hostname/username/password/database). |
| `config/test.exs` | Phoenix config | Same shape, `database: "ideajar_test"`, `pool: Ecto.Adapters.SQL.Sandbox`. |
| `config/runtime.exs` | Phoenix config | NO production change (slice 11b). Keep dev/test overrides if needed. |
| `priv/repo/migrations/<NEW_TS1>_initial_schema.exs` | Ecto migration | Crea 3 tabelle finali con TUTTI i campi. Replaces 7 vecchi migration di schema. |
| `priv/repo/migrations/<NEW_TS2>_seed_categories.exs` | Ecto data migration | Insert_all 8 categorie con `on_conflict: :nothing, conflict_target: :name`. |
| `priv/repo/migrations/2026*_*.exs` (8 files) | DELETED | Rimosse insieme allo `wipe_slice2_dev_ideas`. |
| `docker-compose.yml` | Dev tooling | Single `postgres:16-alpine` service, named volume `ideajar_postgres_data`, port 5432. |
| `.github/workflows/ci.yml` | CI | Aggiunto Postgres service container + env vars + ecto.create/migrate step. |
| `README.md` | Docs | Setup section riscritta per Docker + Postgres. |
| `test/ideajar/migrations_test.exs` | Test | Riscritto from scratch: round-trip + idempotency su single consolidated migration. |
| Slice 4/5/6/7b/8 SQL emission tests | Test | Regex update da `\?` a `\$\d+`. |
| Various `use Ideajar.DataCase` files | Test | `async: false` → `async: true` dove SQLite-specific. |

### Interfaces

**No new domain API.** Slice 11a è Repo adapter swap + config + migration consolidation + test updates.

**`mix.exs` deps diff** (canonical):
```elixir
# Removed:
- {:ecto_sqlite3, ">= 0.0.0"},

# Added:
+ {:postgrex, ">= 0.0.0"},
```

**`lib/ideajar/repo.ex` diff**:
```elixir
defmodule Ideajar.Repo do
  use Ecto.Repo,
    otp_app: :ideajar,
-   adapter: Ecto.Adapters.SQLite3
+   adapter: Ecto.Adapters.Postgres
end
```

**`config/dev.exs` diff** (canonical):
```elixir
config :ideajar, Ideajar.Repo,
- database: Path.expand("../ideajar_dev.db", __DIR__),
- pool_size: 5,
- show_sensitive_data_on_connection_error: true
+ username: System.get_env("POSTGRES_USER", "ideajar"),
+ password: System.get_env("POSTGRES_PASSWORD", "ideajar"),
+ hostname: System.get_env("POSTGRES_HOST", "localhost"),
+ database: System.get_env("POSTGRES_DB", "ideajar_dev"),
+ port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
+ pool_size: 10,
+ show_sensitive_data_on_connection_error: true
```

**`config/test.exs` diff** (canonical):
```elixir
config :ideajar, Ideajar.Repo,
- database: Path.expand("../ideajar_test.db#\{System.get_env(\"MIX_TEST_PARTITION\")\}", __DIR__),
- pool: Ecto.Adapters.SQL.Sandbox,
- pool_size: 5
+ username: System.get_env("POSTGRES_USER", "ideajar"),
+ password: System.get_env("POSTGRES_PASSWORD", "ideajar"),
+ hostname: System.get_env("POSTGRES_HOST", "localhost"),
+ database: "ideajar_test#\{System.get_env(\"MIX_TEST_PARTITION\")\}",
+ port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
+ pool: Ecto.Adapters.SQL.Sandbox,
+ pool_size: System.schedulers_online() * 2
```

**`docker-compose.yml`** (canonical):
```yaml
version: "3.9"
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: ideajar
      POSTGRES_PASSWORD: ideajar
      POSTGRES_DB: ideajar_dev
    ports:
      - "5432:5432"
    volumes:
      - ideajar_postgres_data:/var/lib/postgresql/data
volumes:
  ideajar_postgres_data:
```

**`priv/repo/migrations/<NEW_TS>_initial_schema.exs`** (canonical schema):
```elixir
defmodule Ideajar.Repo.Migrations.InitialSchema do
  use Ecto.Migration

  def change do
    create table(:categories) do
      add :name, :string, null: false
      add :display_order, :integer, null: false
      timestamps()
    end

    create unique_index(:categories, [:name])
    create index(:categories, [:display_order])

    create table(:ideas) do
      add :title, :string, null: false
      add :description, :text
      add :url, :string
      add :duration, :string  # Ecto.Enum casts at the schema layer
      add :estimated_cost, :integer
      add :location_name, :string
      add :lat, :float
      add :lng, :float
      timestamps()
    end

    create index(:ideas, [:inserted_at])

    create table(:idea_categories) do
      add :idea_id, references(:ideas, on_delete: :delete_all), null: false
      add :category_id, references(:categories, on_delete: :delete_all), null: false
      timestamps()
    end

    create index(:idea_categories, [:idea_id])
    create index(:idea_categories, [:category_id])
    create unique_index(:idea_categories, [:idea_id, :category_id])
  end
end
```

**Note**: il `change/0` invece di `up/0` + `down/0` permette ad Ecto di derivare automaticamente il rollback. Round-trip test gratuito.

**`priv/repo/migrations/<NEW_TS+1>_seed_categories.exs`** (invariato logicamente):
```elixir
defmodule Ideajar.Repo.Migrations.SeedCategories do
  use Ecto.Migration

  import Ecto.Query, only: [from: 2]

  @seed_categories [
    {1, "passeggiata"}, {2, "mare"}, {3, "museo"}, {4, "ristorante"},
    {5, "sport"}, {6, "cultura"}, {7, "cinema"}, {8, "viaggio"}
  ]

  def up do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(@seed_categories, fn {order, name} ->
        %{name: name, display_order: order, inserted_at: now, updated_at: now}
      end)

    repo().insert_all("categories", rows, on_conflict: :nothing, conflict_target: :name)
  end

  def down do
    names = Enum.map(@seed_categories, fn {_order, name} -> name end)
    repo().delete_all(from(c in "categories", where: c.name in ^names))
  end
end
```

### Constraints

- **No domain code change** in `lib/ideajar/`. Schema files (`Idea`, `Category`) are adapter-agnostic; field types stay the same.
- **No new Hex deps** beyond `postgrex`. Specifically: NO Litestream, NO `decimal` library, NO Postgrex extensions.
- **Migration file naming**: timestamps regenerati alla data corrente (es. `20260503000001_initial_schema.exs`). NOT preservare i vecchi.
- **`change/0` invece di `up/0`+`down/0`** per la consolidated migration: Ecto deriva il rollback. Pattern standard.
- **FK on_delete: :delete_all**: cascade per `idea_categories` quando una idea o categoria viene cancellata.
- **`unique_index([:idea_id, :category_id])`**: previene duplicate associations (es. doppio click su chip).
- **NO async: false re-disabilitati** se la ragione era SQLite-specific.
- **NO test logic change**: solo regex updates per SQL emission pins. Behavior assertions invariate.
- **Docker-compose port 5432** stesso del Postgres default: i contributor che hanno Postgres locale già installato vedranno conflitto. Documenta in README come fixarlo.
- **Postgres version `16-alpine`**: matching la versione Gigalixir slice 11b. Se Gigalixir supporta solo 17, pivottare entrambi.
- **`MIX_TEST_PARTITION` support** in `database`: per `mix test --partitions N` con `MIX_TEST_PARTITION=1..N` env var. Pattern standard Phoenix.

### Dependencies

- **Postgrex** Hex dep (NEW): `~> 0.17` o latest stable.
- **Docker** (developer machine): Docker Engine + Docker Compose. Documentato in README.
- **Postgres 16** (CI service container + Gigalixir slice 11b prerequisite).
- **No new Elixir version requirement**.

### Out of scope

- Production deploy (slice 11b)
- `mix release` config in `mix.exs`
- `config/runtime.exs` production block update (slice 11b will)
- HTTPS/SSL / Phoenix endpoint host/port (slice 11b)
- V1/V2 manual gates slice 10 (require deployed env)
- Backup strategy per Postgres dev
- Performance tuning oltre indexes
- Multi-tenant separation
- Connection pooling tuning oltre defaults
- Any UI changes
- Any new domain functionality
- Postgres extensions (postgis, pg_trgm, etc.)

## Acceptance Criteria

### Adapter swap

- [ ] **A1** — `mix.exs` deps include `:postgrex` and exclude `:ecto_sqlite3` + `:exqlite`.
- [ ] **A2** — `lib/ideajar/repo.ex` declares `adapter: Ecto.Adapters.Postgres`.
- [ ] **A3** — `config/dev.exs` has Postgres connection params (hostname/username/password/database/port) with sensible defaults.
- [ ] **A4** — `config/test.exs` same shape + Sandbox + `MIX_TEST_PARTITION` support.
- [ ] **A5** — `config/runtime.exs` not touched (or only adapter-line change in dev/test branches).

### Migration consolidation

- [ ] **M1** — `priv/repo/migrations/` contains exactly 2 files post-slice-11a: `<TS>_initial_schema.exs` + `<TS+1>_seed_categories.exs`. The 9 old files (8 schema + 1 wipe) are deleted.
- [ ] **M2** — `initial_schema.exs` creates 3 tables (`categories`, `ideas`, `idea_categories`) with all final fields per Architecture spec.
- [ ] **M3** — `initial_schema.exs` creates indexes: `categories.name unique`, `categories.display_order`, `ideas.inserted_at`, `idea_categories.idea_id`, `idea_categories.category_id`, `idea_categories.idea_id+category_id unique`.
- [ ] **M4** — FK constraints `idea_categories.idea_id → ideas.id ON DELETE CASCADE` and `.category_id → categories.id ON DELETE CASCADE`.
- [ ] **M5** — `seed_categories.exs` insert_all 8 canonical categories with on_conflict: :nothing.
- [ ] **M6** — `mix ecto.create && mix ecto.migrate` round-trip works on a fresh database.
- [ ] **M7** — `mix ecto.rollback` followed by `mix ecto.migrate` works (migration round-trip).

### Docker Compose

- [ ] **D1** — `docker-compose.yml` exists at repo root with single `postgres:16-alpine` service.
- [ ] **D2** — Named volume `ideajar_postgres_data` for persistence.
- [ ] **D3** — Port 5432 exposed.
- [ ] **D4** — Defaults `ideajar/ideajar/ideajar_dev` matching `config/dev.exs`.
- [ ] **D5** — `docker-compose up -d` starts Postgres successfully on a fresh repo clone.
- [ ] **D6** — `docker-compose down && docker-compose up -d` preserves data (volume).

### Test suite passes on Postgres

- [ ] **T1** — `mix test --include migration` returns 830 tests, 0 failures.
- [ ] **T2** — Migration test (`migrations_test.exs`) is rewritten for consolidated migration: tests up/down/up round-trip + seed idempotency. NO references to old slice-by-slice migration modules.
- [ ] **T3** — SQL emission regex pins (slice 4/5/6/7b/8) updated to `\$\d+` instead of `\?`.
- [ ] **T4** — `async: false` audit completed: cases SQLite-specific re-enabled to `async: true`. Cases with other reasons stay `async: false`.
- [ ] **T5** — No test imports `Ecto.Adapters.SQLite3` or any SQLite-specific module.

### CI provisioning

- [ ] **C1** — `.github/workflows/ci.yml` has `services.postgres` block with `postgres:16` image + healthcheck.
- [ ] **C2** — Env vars: `POSTGRES_USER=ideajar`, `POSTGRES_PASSWORD=ideajar`, `POSTGRES_DB=ideajar_test`, `POSTGRES_HOST=localhost`.
- [ ] **C3** — Test step preceded by `mix ecto.create && mix ecto.migrate`.
- [ ] **C4** — CI run green on push (verifica via `gh run list` post-push).

### README + docs

- [ ] **R1** — README setup section starts with `docker-compose up -d`.
- [ ] **R2** — README NO references to SQLite installation.
- [ ] **R3** — CONTEXT.md notes Postgres adapter post-slice-11a.

### Out-of-scope guard

- [ ] **OS1** — `config/runtime.exs` `if config_env() == :prod` block NOT modified beyond adapter line.
- [ ] **OS2** — `mix.exs` does NOT contain `releases:` config.
- [ ] **OS3** — No new HTTPS/SSL/host/port config.

### Operational / data

- [ ] **O1** — No domain code changes (`lib/ideajar/` schema modules + business logic invariati).
- [ ] **O2** — No data loss in tests (test seeds work identically on Postgres).
- [ ] **O3** — Total slice diff: ~50 LOC config/Repo/mix + ~80 LOC migrations + ~30 LOC docker-compose + ~50 LOC ci.yml + ~10-30 test fixes (regex updates + async toggles) + ~50 LOC migrations_test rewrite. Total est. ~250-300 LOC.

## Consistency Gate

- [x] Intent unambiguo — adapter swap + migration consolidation + dev tooling + test fixes; production deploy esplicitamente fuori scope (slice 11b)
- [x] Ogni behavior ha BDD scenario corrispondente (setup, test run, migration consolidation, adapter swap, SQL emission, async review, CI, README, out-of-scope guards, migration test rewrite)
- [x] Architecture constrains without over-engineering (no Litestream, no Postgrex extensions, no domain code change, no test logic change beyond regex)
- [x] Termini consistenti (`Postgres 16`, `ideajar_dev/test`, `Sandbox :manual`, `change/0` migration, `on_conflict: :nothing`)
- [x] No contradictions — migration history rewrite chiarito (no production data); slice 11b deploy esplicitamente fuori scope; test count 830 invariato post-migration

**Verdict: PASS** — ready for `/plan`.
