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

  unless Code.ensure_loaded?(@ideas_migration), do: Code.require_file(@ideas_path)
  unless Code.ensure_loaded?(@categories_migration), do: Code.require_file(@categories_path)

  unless Code.ensure_loaded?(@seed_categories_migration),
    do: Code.require_file(@seed_categories_path)

  unless Code.ensure_loaded?(@wipe_ideas_migration), do: Code.require_file(@wipe_ideas_path)

  unless Code.ensure_loaded?(@idea_categories_migration),
    do: Code.require_file(@idea_categories_path)

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

  # ── Helpers ────────────────────────────────────────────────────────

  defp drop_table(name), do: SQL.query!(Repo, "DROP TABLE IF EXISTS #{name}", [])

  defp delete_versions do
    versions = [
      @ideas_version,
      @categories_version,
      @seed_categories_version,
      @wipe_ideas_version,
      @idea_categories_version
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
end
