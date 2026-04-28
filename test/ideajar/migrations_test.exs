defmodule Ideajar.MigrationsTest do
  @moduledoc """
  All migration round-trip and idempotency tests live here.

  Migrations bypass the Ecto sandbox because they apply DDL outside any
  transaction. Each non-trivial migration test toggles the sandbox into
  `:auto` mode globally, which means having multiple `async: false`
  migration test modules race on the global pool state — drops become
  invisible to the migrator's connection, sandbox-aware non-migration
  tests stop seeing transactional isolation, and the suite becomes
  flaky.

  Consolidating every migration test into this single module keeps the
  ordering and the `:auto`/`:manual` mode toggle deterministic. On exit
  we restore both the schema and the `:manual` mode so subsequent
  sandbox-aware tests recover cleanly.
  """

  use ExUnit.Case, async: false

  @moduletag :migration

  alias Ecto.Adapters.SQL
  alias Ideajar.Repo

  # ── Migration version metadata ──────────────────────────────────────

  @ideas_migration Ideajar.Repo.Migrations.CreateIdeas
  @ideas_version 20_260_427_000_001
  @ideas_path Path.expand(
                "../../priv/repo/migrations/20260427000001_create_ideas.exs",
                __DIR__
              )

  @categories_migration Ideajar.Repo.Migrations.CreateCategories
  @categories_version 20_260_428_000_001
  @categories_path Path.expand(
                     "../../priv/repo/migrations/20260428000001_create_categories.exs",
                     __DIR__
                   )

  @seed_categories_migration Ideajar.Repo.Migrations.SeedCategories
  @seed_categories_version 20_260_428_000_002
  @seed_categories_path Path.expand(
                          "../../priv/repo/migrations/20260428000002_seed_categories.exs",
                          __DIR__
                        )

  @wipe_ideas_migration Ideajar.Repo.Migrations.WipeSlice2DevIdeas
  @wipe_ideas_version 20_260_428_000_003
  @wipe_ideas_path Path.expand(
                     "../../priv/repo/migrations/20260428000003_wipe_slice2_dev_ideas.exs",
                     __DIR__
                   )

  @idea_categories_migration Ideajar.Repo.Migrations.CreateIdeaCategories
  @idea_categories_version 20_260_428_000_004
  @idea_categories_path Path.expand(
                          "../../priv/repo/migrations/20260428000004_create_idea_categories.exs",
                          __DIR__
                        )

  @add_duration_migration Ideajar.Repo.Migrations.AddDurationToIdeas
  @add_duration_version 20_260_428_000_005
  @add_duration_path Path.expand(
                       "../../priv/repo/migrations/20260428000005_add_duration_to_ideas.exs",
                       __DIR__
                     )

  unless Code.ensure_loaded?(@ideas_migration), do: Code.require_file(@ideas_path)
  unless Code.ensure_loaded?(@categories_migration), do: Code.require_file(@categories_path)

  unless Code.ensure_loaded?(@seed_categories_migration),
    do: Code.require_file(@seed_categories_path)

  unless Code.ensure_loaded?(@wipe_ideas_migration), do: Code.require_file(@wipe_ideas_path)

  unless Code.ensure_loaded?(@idea_categories_migration),
    do: Code.require_file(@idea_categories_path)

  unless Code.ensure_loaded?(@add_duration_migration),
    do: Code.require_file(@add_duration_path)

  @canonical_categories [
    {1, "passeggiata"},
    {2, "mare"},
    {3, "museo"},
    {4, "ristorante"},
    {5, "sport"},
    {6, "cultura"},
    {7, "cinema"},
    {8, "viaggio"}
  ]

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

    drop_table("idea_categories")
    drop_table("ideas")
    drop_table("categories")
    delete_versions()

    on_exit(fn ->
      drop_table("idea_categories")
      drop_table("ideas")
      drop_table("categories")
      delete_versions()

      # Restore the production schema for subsequent sandbox-aware tests:
      # ideas + categories tables, the 8 seed rows, the wipe migration
      # recorded as run, and the idea_categories join table.
      Ecto.Migrator.up(Repo, @ideas_version, @ideas_migration, log: false)
      Ecto.Migrator.up(Repo, @categories_version, @categories_migration, log: false)

      Ecto.Migrator.up(
        Repo,
        @seed_categories_version,
        @seed_categories_migration,
        log: false
      )

      Ecto.Migrator.up(Repo, @wipe_ideas_version, @wipe_ideas_migration, log: false)

      Ecto.Migrator.up(
        Repo,
        @idea_categories_version,
        @idea_categories_migration,
        log: false
      )

      # Restore the slice-5 add_duration column directly (raw SQL)
      # rather than `Ecto.Migrator.up`. The migrator forks a Task whose
      # pool connection has a stale schema cache after the test's column
      # changes (see `run_add_duration/1` rationale above). Running on
      # the test connection avoids the cache miss; the schema_migrations
      # row is upserted manually for fidelity with `mix ecto.migrate`.
      unless duration_column_present?() do
        SQL.query!(Repo, ~s|ALTER TABLE "ideas" ADD COLUMN "duration" TEXT|, [])
      end

      SQL.query!(
        Repo,
        "INSERT OR IGNORE INTO schema_migrations (version, inserted_at) VALUES (?, datetime('now'))",
        [@add_duration_version]
      )

      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    end)

    :ok
  end

  # ── Schema migrations: round-trip up/down/up ───────────────────────

  test "create_ideas migration is reversible and creates the inserted_at index" do
    refute table_exists?("ideas")

    Ecto.Migrator.up(Repo, @ideas_version, @ideas_migration, log: false)

    assert table_exists?("ideas")
    assert index_exists?("ideas_inserted_at_desc_idx")

    Ecto.Migrator.down(Repo, @ideas_version, @ideas_migration, log: false)

    refute table_exists?("ideas")

    Ecto.Migrator.up(Repo, @ideas_version, @ideas_migration, log: false)

    assert table_exists?("ideas")
    assert index_exists?("ideas_inserted_at_desc_idx")
  end

  test "create_categories migration is reversible and creates the unique indexes" do
    refute table_exists?("categories")

    Ecto.Migrator.up(Repo, @categories_version, @categories_migration, log: false)

    assert table_exists?("categories")
    assert index_exists?("categories_name_index")
    assert index_exists?("categories_display_order_index")

    Ecto.Migrator.down(Repo, @categories_version, @categories_migration, log: false)

    refute table_exists?("categories")

    Ecto.Migrator.up(Repo, @categories_version, @categories_migration, log: false)

    assert table_exists?("categories")
    assert index_exists?("categories_name_index")
    assert index_exists?("categories_display_order_index")
  end

  # ── Seed migration: contents + idempotency ─────────────────────────

  test "seed_categories migration inserts the canonical 8 in display_order 1..8" do
    Ecto.Migrator.up(Repo, @categories_version, @categories_migration, log: false)

    Ecto.Migrator.up(
      Repo,
      @seed_categories_version,
      @seed_categories_migration,
      log: false
    )

    rows =
      Repo
      |> SQL.query!("SELECT name, display_order FROM categories ORDER BY display_order", [])
      |> Map.fetch!(:rows)

    assert rows == Enum.map(@canonical_categories, fn {ord, name} -> [name, ord] end)
  end

  test "seed_categories down then up restores the canonical 8 rows (round-trip)" do
    Ecto.Migrator.up(Repo, @categories_version, @categories_migration, log: false)

    Ecto.Migrator.up(
      Repo,
      @seed_categories_version,
      @seed_categories_migration,
      log: false
    )

    %{rows: [[count_after_up]]} = SQL.query!(Repo, "SELECT COUNT(*) FROM categories", [])
    assert count_after_up == 8

    Ecto.Migrator.down(
      Repo,
      @seed_categories_version,
      @seed_categories_migration,
      log: false
    )

    %{rows: [[count_after_down]]} = SQL.query!(Repo, "SELECT COUNT(*) FROM categories", [])
    assert count_after_down == 0

    Ecto.Migrator.up(
      Repo,
      @seed_categories_version,
      @seed_categories_migration,
      log: false
    )

    rows =
      Repo
      |> SQL.query!("SELECT name, display_order FROM categories ORDER BY display_order", [])
      |> Map.fetch!(:rows)

    assert rows == Enum.map(@canonical_categories, fn {ord, name} -> [name, ord] end)
  end

  test "running seed_categories up/0 a second time on an already-seeded DB is a no-op" do
    Ecto.Migrator.up(Repo, @categories_version, @categories_migration, log: false)

    Ecto.Migrator.up(
      Repo,
      @seed_categories_version,
      @seed_categories_migration,
      log: false
    )

    SQL.query!(Repo, "DELETE FROM schema_migrations WHERE version = ?", [
      @seed_categories_version
    ])

    Ecto.Migrator.up(
      Repo,
      @seed_categories_version,
      @seed_categories_migration,
      log: false
    )

    %{rows: [[count]]} = SQL.query!(Repo, "SELECT COUNT(*) FROM categories", [])
    assert count == 8
  end

  # ── Wipe migration ─────────────────────────────────────────────────

  test "wipe_slice2_dev_ideas migration empties the ideas table and leaves categories untouched" do
    Ecto.Migrator.up(Repo, @ideas_version, @ideas_migration, log: false)
    Ecto.Migrator.up(Repo, @categories_version, @categories_migration, log: false)

    Ecto.Migrator.up(
      Repo,
      @seed_categories_version,
      @seed_categories_migration,
      log: false
    )

    SQL.query!(
      Repo,
      "INSERT INTO ideas (title, inserted_at, updated_at) VALUES (?, ?, ?)",
      ["left over", "2026-04-27 00:00:00", "2026-04-27 00:00:00"]
    )

    %{rows: [[ideas_before]]} = SQL.query!(Repo, "SELECT COUNT(*) FROM ideas", [])
    %{rows: [[cats_before]]} = SQL.query!(Repo, "SELECT COUNT(*) FROM categories", [])
    assert ideas_before == 1
    assert cats_before == 8

    Ecto.Migrator.up(Repo, @wipe_ideas_version, @wipe_ideas_migration, log: false)

    %{rows: [[ideas_after]]} = SQL.query!(Repo, "SELECT COUNT(*) FROM ideas", [])
    %{rows: [[cats_after]]} = SQL.query!(Repo, "SELECT COUNT(*) FROM categories", [])
    assert ideas_after == 0
    assert cats_after == 8
  end

  # ── Join migration: round-trip ─────────────────────────────────────

  test "create_idea_categories migration is reversible" do
    Ecto.Migrator.up(Repo, @ideas_version, @ideas_migration, log: false)
    Ecto.Migrator.up(Repo, @categories_version, @categories_migration, log: false)

    refute table_exists?("idea_categories")

    Ecto.Migrator.up(
      Repo,
      @idea_categories_version,
      @idea_categories_migration,
      log: false
    )

    assert table_exists?("idea_categories")

    Ecto.Migrator.down(
      Repo,
      @idea_categories_version,
      @idea_categories_migration,
      log: false
    )

    refute table_exists?("idea_categories")

    Ecto.Migrator.up(
      Repo,
      @idea_categories_version,
      @idea_categories_migration,
      log: false
    )

    assert table_exists?("idea_categories")
  end

  test "running wipe_slice2_dev_ideas up/0 a second time is a no-op" do
    Ecto.Migrator.up(Repo, @ideas_version, @ideas_migration, log: false)
    Ecto.Migrator.up(Repo, @wipe_ideas_version, @wipe_ideas_migration, log: false)

    SQL.query!(Repo, "DELETE FROM schema_migrations WHERE version = ?", [@wipe_ideas_version])

    Ecto.Migrator.up(Repo, @wipe_ideas_version, @wipe_ideas_migration, log: false)

    %{rows: [[ideas]]} = SQL.query!(Repo, "SELECT COUNT(*) FROM ideas", [])
    assert ideas == 0
  end

  # ── add_duration_to_ideas migration (slice 5) ──────────────────────
  #
  # The Ecto.Migrator path forks a `Task.async`, which gets a fresh pool
  # connection from `:auto`-mode sandbox. SQLite caches the table schema
  # per-connection; an `ALTER TABLE ADD COLUMN` committed on connection A
  # is invisible to connection B's parser until B re-opens — and the
  # very next `Migrator.down` task pulls B and crashes with
  # `no such column: duration`. The pre-slice-5 migrations don't trip
  # this because they only `CREATE TABLE` / `DROP TABLE`, which SQLite
  # always re-resolves from sqlite_master.
  #
  # We work around it for slice-5 only by driving the migration's
  # `change/0` directly through `Ecto.Migration.Runner.run/8`, which
  # executes synchronously on the caller's connection (the sandbox-owned
  # one), keeping the schema cookie consistent throughout the test.

  defp run_add_duration(direction) do
    operation =
      case direction do
        :forward -> :up
        :backward -> :down
      end

    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @add_duration_version,
      @add_duration_migration,
      direction,
      :change,
      operation,
      log: false
    )
  end

  test "add_duration_to_ideas migration is reversible and adds a TEXT NULLABLE column" do
    Ecto.Migrator.up(Repo, @ideas_version, @ideas_migration, log: false)
    Ecto.Migrator.up(Repo, @categories_version, @categories_migration, log: false)
    Ecto.Migrator.up(Repo, @seed_categories_version, @seed_categories_migration, log: false)
    Ecto.Migrator.up(Repo, @wipe_ideas_version, @wipe_ideas_migration, log: false)

    Ecto.Migrator.up(
      Repo,
      @idea_categories_version,
      @idea_categories_migration,
      log: false
    )

    refute duration_column_present?()

    run_add_duration(:forward)

    assert duration_column_text_nullable?()

    run_add_duration(:backward)

    refute duration_column_present?()

    run_add_duration(:forward)

    assert duration_column_text_nullable?()
  end

  test "add_duration_to_ideas migration accepts valid duration and NULL on insert" do
    Ecto.Migrator.up(Repo, @ideas_version, @ideas_migration, log: false)
    Ecto.Migrator.up(Repo, @categories_version, @categories_migration, log: false)
    Ecto.Migrator.up(Repo, @seed_categories_version, @seed_categories_migration, log: false)
    Ecto.Migrator.up(Repo, @wipe_ideas_version, @wipe_ideas_migration, log: false)

    Ecto.Migrator.up(
      Repo,
      @idea_categories_version,
      @idea_categories_migration,
      log: false
    )

    run_add_duration(:forward)

    SQL.query!(
      Repo,
      "INSERT INTO ideas (title, duration, inserted_at, updated_at) VALUES (?, ?, ?, ?)",
      ["Weekend al mare", "weekend", "2026-04-27 10:00:00", "2026-04-27 10:00:00"]
    )

    SQL.query!(
      Repo,
      "INSERT INTO ideas (title, duration, inserted_at, updated_at) VALUES (?, ?, ?, ?)",
      ["Senza durata", nil, "2026-04-27 10:01:00", "2026-04-27 10:01:00"]
    )

    %{rows: rows} =
      SQL.query!(Repo, "SELECT title, duration FROM ideas ORDER BY title", [])

    assert rows == [["Senza durata", nil], ["Weekend al mare", "weekend"]]
  end

  test "add_duration_to_ideas down preserves rows but resets duration column on next up" do
    Ecto.Migrator.up(Repo, @ideas_version, @ideas_migration, log: false)
    Ecto.Migrator.up(Repo, @categories_version, @categories_migration, log: false)
    Ecto.Migrator.up(Repo, @seed_categories_version, @seed_categories_migration, log: false)
    Ecto.Migrator.up(Repo, @wipe_ideas_version, @wipe_ideas_migration, log: false)

    Ecto.Migrator.up(
      Repo,
      @idea_categories_version,
      @idea_categories_migration,
      log: false
    )

    run_add_duration(:forward)

    SQL.query!(
      Repo,
      "INSERT INTO ideas (title, description, url, duration, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
      [
        "Sirolo",
        "Bella spiaggia",
        "https://example.com",
        "weekend",
        "2026-04-27 10:00:00",
        "2026-04-27 10:00:00"
      ]
    )

    SQL.query!(
      Repo,
      "INSERT INTO ideas (title, description, url, duration, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
      ["Cinema", "", "", nil, "2026-04-27 10:01:00", "2026-04-27 10:01:00"]
    )

    run_add_duration(:backward)

    %{rows: [[count_after_down]]} = SQL.query!(Repo, "SELECT COUNT(*) FROM ideas", [])
    assert count_after_down == 2

    %{rows: [[title, description, url]]} =
      SQL.query!(
        Repo,
        "SELECT title, description, url FROM ideas WHERE title = ?",
        ["Sirolo"]
      )

    assert title == "Sirolo"
    assert description == "Bella spiaggia"
    assert url == "https://example.com"

    run_add_duration(:forward)

    %{rows: rows} =
      SQL.query!(Repo, "SELECT duration FROM ideas ORDER BY title", [])

    # SQLite ALTER TABLE DROP COLUMN + add reset = column ripristinata vuota.
    assert rows == [[nil], [nil]]
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp drop_table(name), do: SQL.query!(Repo, "DROP TABLE IF EXISTS #{name}", [])

  defp delete_versions do
    versions = [
      @ideas_version,
      @categories_version,
      @seed_categories_version,
      @wipe_ideas_version,
      @idea_categories_version,
      @add_duration_version
    ]

    Enum.each(versions, fn v ->
      SQL.query!(Repo, "DELETE FROM schema_migrations WHERE version = ?", [v])
    end)
  end

  defp table_exists?(name) do
    %{rows: rows} =
      SQL.query!(Repo, "SELECT name FROM sqlite_master WHERE type='table' AND name=?", [name])

    rows != []
  end

  defp index_exists?(name) do
    %{rows: rows} =
      SQL.query!(Repo, "SELECT name FROM sqlite_master WHERE type='index' AND name=?", [name])

    rows != []
  end

  defp duration_column_present? do
    duration_column_row() != nil
  end

  defp duration_column_text_nullable? do
    case duration_column_row() do
      nil ->
        false

      row ->
        # PRAGMA table_info columns: cid, name, type, notnull, dflt_value, pk
        type = Enum.at(row, 2)
        notnull = Enum.at(row, 3)
        String.upcase(type) == "TEXT" and notnull == 0
    end
  end

  defp duration_column_row do
    %{rows: rows} = SQL.query!(Repo, "PRAGMA table_info(ideas)", [])
    Enum.find(rows, fn row -> Enum.at(row, 1) == "duration" end)
  end
end
