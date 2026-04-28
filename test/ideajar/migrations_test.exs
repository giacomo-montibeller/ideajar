defmodule Ideajar.MigrationsTest do
  @moduledoc """
  Round-trip tests for every migration in `priv/repo/migrations/`.

  Migrations bypass the Ecto sandbox because they apply DDL outside any
  transaction. Each test:

    1. drops the target table(s) and removes the schema_migrations rows for
       the migration versions involved (clean slate)
    2. runs the migration up and asserts the schema state is correct
    3. runs the migration down and asserts the schema is gone
    4. runs up again to leave the DB in a state subsequent sandbox-aware
       tests can depend on

  Both migrations live in this single module on purpose: running two
  separate `async: false` modules that each toggle the Sandbox into `:auto`
  mode is fragile in practice — they conflict on the global pool mode and
  one drop can be invisible to the other's connection. Consolidating keeps
  ordering and cleanup deterministic.
  """

  use ExUnit.Case, async: false

  @moduletag :migration

  alias Ecto.Adapters.SQL
  alias Ideajar.Repo

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

  unless Code.ensure_loaded?(@ideas_migration), do: Code.require_file(@ideas_path)
  unless Code.ensure_loaded?(@categories_migration), do: Code.require_file(@categories_path)

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

    # Bring everything down so each test starts from an empty schema.
    drop_table("ideas")
    drop_table("categories")
    delete_schema_version(@ideas_version)
    delete_schema_version(@categories_version)

    on_exit(fn ->
      drop_table("ideas")
      drop_table("categories")
      delete_schema_version(@ideas_version)
      delete_schema_version(@categories_version)

      # Restore both schemas so subsequent sandbox-aware tests find the
      # tables they need.
      Ecto.Migrator.up(Repo, @categories_version, @categories_migration, log: false)
      Ecto.Migrator.up(Repo, @ideas_version, @ideas_migration, log: false)

      # Hand the pool back to manual mode so non-migration tests get their
      # transactional isolation back. Without this, a test that runs after
      # this module sees Sandbox in :auto mode and its sandbox setup never
      # actually isolates anything.
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    end)

    :ok
  end

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

  defp drop_table(name), do: SQL.query!(Repo, "DROP TABLE IF EXISTS #{name}", [])

  defp delete_schema_version(version) do
    SQL.query!(Repo, "DELETE FROM schema_migrations WHERE version = ?", [version])
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
