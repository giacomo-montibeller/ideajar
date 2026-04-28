defmodule Ideajar.Categories.SeedMigrationTest do
  # Manipulates the categories table directly; cannot run with sandbox-shared
  # tests. Lives outside `migrations_test.exs` because that module pre-cleans
  # both ideas and categories tables for round-trip testing — here we want
  # the categories table present (from the schema migration) but its rows
  # under our control.
  use ExUnit.Case, async: false

  @moduletag :migration

  alias Ecto.Adapters.SQL
  alias Ideajar.Repo

  @migration_module Ideajar.Repo.Migrations.SeedCategories
  @migration_version 20_260_428_000_002
  @migration_path Path.expand(
                    "../../../priv/repo/migrations/20260428000002_seed_categories.exs",
                    __DIR__
                  )

  unless Code.ensure_loaded?(@migration_module), do: Code.require_file(@migration_path)

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

    # Each test starts with the categories table empty and the seed migration
    # not recorded.
    SQL.query!(Repo, "DELETE FROM categories", [])
    SQL.query!(Repo, "DELETE FROM schema_migrations WHERE version = ?", [@migration_version])

    on_exit(fn ->
      SQL.query!(Repo, "DELETE FROM categories", [])
      SQL.query!(Repo, "DELETE FROM schema_migrations WHERE version = ?", [@migration_version])
      Ecto.Migrator.up(Repo, @migration_version, @migration_module, log: false)

      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    end)

    :ok
  end

  test "seed migration inserts the 8 canonical categories in display_order 1..8" do
    Ecto.Migrator.up(Repo, @migration_version, @migration_module, log: false)

    rows =
      SQL.query!(Repo, "SELECT name, display_order FROM categories ORDER BY display_order", [])
      |> Map.fetch!(:rows)

    assert rows == Enum.map(@canonical_categories, fn {ord, name} -> [name, ord] end)
  end

  test "running the seed migration up/0 a second time on an already-seeded DB is a no-op" do
    Ecto.Migrator.up(Repo, @migration_version, @migration_module, log: false)

    # Remove the schema_migrations row so the migrator will execute up/0
    # again instead of treating the version as already applied.
    SQL.query!(Repo, "DELETE FROM schema_migrations WHERE version = ?", [@migration_version])

    Ecto.Migrator.up(Repo, @migration_version, @migration_module, log: false)

    %{rows: [[count]]} = SQL.query!(Repo, "SELECT COUNT(*) FROM categories", [])
    assert count == 8
  end
end
