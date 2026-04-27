defmodule Ideajar.Ideas.MigrationTest do
  # Manipulates schema directly; cannot run with sandbox-shared tests.
  use ExUnit.Case, async: false

  @moduletag :migration

  alias Ecto.Adapters.SQL
  alias Ideajar.Repo

  @migration_module Ideajar.Repo.Migrations.CreateIdeas
  @migration_version 20_260_427_000_001

  # Migration files in `priv/repo/migrations/` are not compiled by Mix; they
  # are loaded from disk by the migrator at runtime. For an in-process test we
  # have to require the file explicitly so the module becomes available.
  unless Code.ensure_loaded?(@migration_module) do
    Code.require_file(
      Path.expand(
        "../../../priv/repo/migrations/20260427000001_create_ideas.exs",
        __DIR__
      )
    )
  end

  setup do
    # Migrations bypass the sandbox: they manipulate schema via DDL and must
    # see the changes from outside the test transaction.
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

    drop_if_exists()

    on_exit(fn ->
      drop_if_exists()
      # Re-apply the migration so the schema is restored for sandbox tests.
      Ecto.Migrator.up(Repo, @migration_version, @migration_module, log: false)
    end)

    :ok
  end

  test "create_ideas migration is reversible and creates the index" do
    refute table_exists?("ideas")

    Ecto.Migrator.up(Repo, @migration_version, @migration_module, log: false)

    assert table_exists?("ideas")
    assert index_exists?("ideas_inserted_at_desc_idx")

    Ecto.Migrator.down(Repo, @migration_version, @migration_module, log: false)

    refute table_exists?("ideas")

    Ecto.Migrator.up(Repo, @migration_version, @migration_module, log: false)

    assert table_exists?("ideas")
    assert index_exists?("ideas_inserted_at_desc_idx")
  end

  defp drop_if_exists do
    SQL.query!(Repo, "DROP TABLE IF EXISTS ideas", [])
    SQL.query!(Repo, "DELETE FROM schema_migrations WHERE version = ?", [@migration_version])
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
