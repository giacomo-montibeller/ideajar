defmodule Ideajar.MigrationsTest do
  @moduledoc """
  Slice 11a — rewritten from scratch for the consolidated initial
  schema migration. Pre-slice-11a tested 8 slice-by-slice migrations
  with their own up/down round-trips; post-consolidation there are
  exactly 2 migrations (initial_schema + seed_categories) and the
  test surface shrinks accordingly.

  Migrations bypass the Ecto sandbox because they apply DDL outside
  any transaction. The :auto/:manual sandbox toggle is global; we
  serialize this module (`async: false`) so it cannot race other
  tests through the global pool state. On exit we restore both the
  schema and the :manual mode so subsequent sandbox-aware tests
  recover cleanly.
  """

  use ExUnit.Case, async: false

  @moduletag :migration

  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.SQL
  alias Ideajar.Repo

  @initial_schema_module Ideajar.Repo.Migrations.InitialSchema
  @initial_schema_version 20_260_503_000_001

  @seed_categories_module Ideajar.Repo.Migrations.SeedCategories
  @seed_categories_version 20_260_503_000_002

  @migrations_dir Path.expand("../../priv/repo/migrations", __DIR__)

  setup do
    SQL.Sandbox.mode(Repo, :auto)
    # Pre-load migration modules; they aren't on the autoload path because
    # they live under `priv/`. Without this, `Ecto.Migrator.down/up` with
    # a module reference would raise `UndefinedFunctionError`.
    ensure_migrations_loaded!()

    on_exit(fn ->
      restore_baseline()
      SQL.Sandbox.mode(Repo, :manual)
    end)

    :ok
  end

  describe "priv/repo/migrations directory" do
    test "contains exactly the 2 consolidated slice-11a files" do
      files =
        @migrations_dir
        |> File.ls!()
        |> Enum.filter(&String.match?(&1, ~r/^\d+_.*\.exs$/))
        |> Enum.sort()

      assert files == [
               "20260503000001_initial_schema.exs",
               "20260503000002_seed_categories.exs"
             ]
    end
  end

  describe "InitialSchema migration round-trip (slice 11a)" do
    test "down + up restores the 3 tables" do
      # Roll back both seed + schema.
      Ecto.Migrator.down(Repo, @seed_categories_version, @seed_categories_module)
      Ecto.Migrator.down(Repo, @initial_schema_version, @initial_schema_module)

      refute table_exists?("ideas")
      refute table_exists?("categories")
      refute table_exists?("idea_categories")

      # And bring them back.
      Ecto.Migrator.up(Repo, @initial_schema_version, @initial_schema_module)
      Ecto.Migrator.up(Repo, @seed_categories_version, @seed_categories_module)

      assert table_exists?("ideas")
      assert table_exists?("categories")
      assert table_exists?("idea_categories")
    end

    test "ideas table carries every final-state column" do
      cols = column_names("ideas")

      for needed <- ~w(id title description url duration estimated_cost
                       location_name lat lng inserted_at updated_at) do
        assert needed in cols, "ideas table missing column: #{needed}"
      end
    end

    test "categories table enforces unique name" do
      cols = column_names("categories")
      assert "name" in cols
      assert "display_order" in cols

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert_all("categories", [
        %{name: "dup-test", display_order: 99, inserted_at: now, updated_at: now}
      ])

      assert_raise Postgrex.Error, ~r/unique|duplicate/i, fn ->
        Repo.insert_all("categories", [
          %{name: "dup-test", display_order: 100, inserted_at: now, updated_at: now}
        ])
      end

      Repo.delete_all(from c in "categories", where: c.name == "dup-test")
    end

    test "idea_categories cascades on idea delete" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      mare_id =
        Repo.one!(from c in "categories", where: c.name == "mare", select: c.id)

      {1, [%{id: idea_id}]} =
        Repo.insert_all(
          "ideas",
          [%{title: "Cascade test", inserted_at: now, updated_at: now}],
          returning: [:id]
        )

      Repo.insert_all("idea_categories", [
        %{idea_id: idea_id, category_id: mare_id}
      ])

      assert 1 ==
               Repo.aggregate(
                 from(ic in "idea_categories", where: ic.idea_id == ^idea_id),
                 :count
               )

      Repo.delete_all(from i in "ideas", where: i.id == ^idea_id)

      assert 0 ==
               Repo.aggregate(
                 from(ic in "idea_categories", where: ic.idea_id == ^idea_id),
                 :count
               )
    end
  end

  describe "SeedCategories migration (slice 11a)" do
    test "re-running up is idempotent (on_conflict :nothing on :name)" do
      Ecto.Migrator.down(Repo, @seed_categories_version, @seed_categories_module)
      assert Repo.aggregate("categories", :count) == 0

      Ecto.Migrator.up(Repo, @seed_categories_version, @seed_categories_module)
      assert Repo.aggregate("categories", :count) == 8

      Ecto.Migrator.up(Repo, @seed_categories_version, @seed_categories_module)
      assert Repo.aggregate("categories", :count) == 8
    end

    test "all 8 canonical category names are present after up" do
      names =
        Repo.all(from c in "categories", select: c.name)
        |> MapSet.new()

      for needed <- ~w(passeggiata mare museo ristorante sport cultura cinema viaggio) do
        assert MapSet.member?(names, needed),
               "missing canonical seed: #{needed}"
      end
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp table_exists?(table) do
    {:ok, %Postgrex.Result{rows: [[exists]]}} =
      SQL.query(
        Repo,
        "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = $1)",
        [table]
      )

    exists
  end

  defp column_names(table) do
    {:ok, %Postgrex.Result{rows: rows}} =
      SQL.query(
        Repo,
        "SELECT column_name FROM information_schema.columns WHERE table_name = $1",
        [table]
      )

    Enum.map(rows, fn [name] -> name end)
  end

  defp restore_baseline do
    Ecto.Migrator.run(Repo, @migrations_dir, :up, all: true)
  end

  defp ensure_migrations_loaded! do
    @migrations_dir
    |> File.ls!()
    |> Enum.filter(&String.match?(&1, ~r/^\d+_.*\.exs$/))
    |> Enum.each(fn name ->
      path = Path.join(@migrations_dir, name)

      try do
        Code.compile_file(path)
      rescue
        # Already compiled (test run #2+) — module clash is fine, the
        # already-loaded definition is current.
        CompileError -> :ok
        Code.LoadError -> :ok
      end
    end)
  end
end
