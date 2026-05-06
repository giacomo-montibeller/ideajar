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

  @add_emoji_module Ideajar.Repo.Migrations.AddEmojiToCategories
  @add_emoji_version 20_260_506_133_631

  @migrations_dir Path.expand("../../priv/repo/migrations", __DIR__)

  setup do
    SQL.Sandbox.mode(Repo, :auto)
    # Pre-load migration modules; they aren't on the autoload path because
    # they live under `priv/`. Without this, `Ecto.Migrator.down/up` with
    # a module reference would raise `UndefinedFunctionError`.
    ensure_migrations_loaded!()

    # Each test in this module mutates global schema state. Re-baseline
    # at setup so a previous test that crashed mid-way (e.g. an assertion
    # raised before its own up/0 calls completed) cannot leak a corrupt
    # schema into the next test.
    restore_baseline()

    on_exit(fn ->
      restore_baseline()
      SQL.Sandbox.mode(Repo, :manual)
    end)

    :ok
  end

  describe "priv/repo/migrations directory" do
    test "contains the 3 expected migration files" do
      files =
        @migrations_dir
        |> File.ls!()
        |> Enum.filter(&String.match?(&1, ~r/^\d+_.*\.exs$/))
        |> Enum.sort()

      assert files == [
               "20260503000001_initial_schema.exs",
               "20260503000002_seed_categories.exs",
               "20260506133631_add_emoji_to_categories.exs"
             ]
    end
  end

  describe "InitialSchema migration round-trip (slice 11a)" do
    test "down + up restores the 3 tables" do
      # Roll back the full applied stack from newest to oldest. Skipping
      # the emoji migration here would leave the (now-orphaned)
      # add_emoji_to_categories row in schema_migrations, and the
      # subsequent up(initial_schema) would not re-apply it — leaving
      # `categories` without the `emoji` column for every test that
      # follows in the suite.
      Ecto.Migrator.down(Repo, @add_emoji_version, @add_emoji_module)
      Ecto.Migrator.down(Repo, @seed_categories_version, @seed_categories_module)
      Ecto.Migrator.down(Repo, @initial_schema_version, @initial_schema_module)

      refute table_exists?("ideas")
      refute table_exists?("categories")
      refute table_exists?("idea_categories")

      # And bring them back in order.
      Ecto.Migrator.up(Repo, @initial_schema_version, @initial_schema_module)
      Ecto.Migrator.up(Repo, @seed_categories_version, @seed_categories_module)
      Ecto.Migrator.up(Repo, @add_emoji_version, @add_emoji_module)

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
      assert "emoji" in cols

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert_all("categories", [
        %{name: "dup-test", display_order: 99, emoji: "🧪", inserted_at: now, updated_at: now}
      ])

      assert_raise Postgrex.Error, ~r/unique|duplicate/i, fn ->
        Repo.insert_all("categories", [
          %{name: "dup-test", display_order: 100, emoji: "🧪", inserted_at: now, updated_at: now}
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

  describe "AddEmojiToCategories migration round-trip" do
    test "down removes the emoji column and up restores it with the canonical map" do
      Ecto.Migrator.down(Repo, @add_emoji_version, @add_emoji_module)
      refute "emoji" in column_names("categories")

      Ecto.Migrator.up(Repo, @add_emoji_version, @add_emoji_module)
      assert "emoji" in column_names("categories")

      # Verify the canonical map is populated and the column is NOT NULL.
      # Read the expected emoji from CategoriesFixtures.canonical_emojis/0
      # (the test single-source-of-truth). If the migration's @emoji_by_name
      # diverges from the fixture, this assertion pins the drift on the
      # exact name where it happens.
      {:ok, %Postgrex.Result{rows: rows}} =
        SQL.query(
          Repo,
          "SELECT name, emoji FROM categories ORDER BY display_order",
          []
        )

      expected = Ideajar.CategoriesFixtures.canonical_emojis()

      for [name, emoji] <- rows do
        assert emoji == Map.fetch!(expected, name),
               "migration emoji for #{name} = #{inspect(emoji)} does not match fixture #{inspect(expected[name])}"
      end
    end
  end

  describe "SeedCategories migration (slice 11a)" do
    test "re-running up is idempotent (on_conflict :nothing on :name)" do
      # The seed migration insert_all does not set `emoji`, so we must
      # roll back the emoji NOT NULL constraint first; otherwise the
      # idempotency re-run would violate the constraint instead of
      # exercising on_conflict :nothing.
      Ecto.Migrator.down(Repo, @add_emoji_version, @add_emoji_module)
      Ecto.Migrator.down(Repo, @seed_categories_version, @seed_categories_module)
      assert Repo.aggregate("categories", :count) == 0

      Ecto.Migrator.up(Repo, @seed_categories_version, @seed_categories_module)
      assert Repo.aggregate("categories", :count) == 8

      Ecto.Migrator.up(Repo, @seed_categories_version, @seed_categories_module)
      assert Repo.aggregate("categories", :count) == 8

      # Restore the emoji constraint for the next test (the on_exit
      # restore_baseline would also catch this, but keeping the stack
      # consistent within the test makes intent clearer).
      Ecto.Migrator.up(Repo, @add_emoji_version, @add_emoji_module)
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
    # Drop everything explicitly so we don't depend on schema_migrations
    # rows being in sync with the actual schema (a crashed mid-test leaves
    # the registry advanced but the schema regressed). Then re-apply all
    # migrations from scratch.
    SQL.query!(Repo, "DROP TABLE IF EXISTS idea_categories CASCADE", [])
    SQL.query!(Repo, "DROP TABLE IF EXISTS ideas CASCADE", [])
    SQL.query!(Repo, "DROP TABLE IF EXISTS categories CASCADE", [])
    SQL.query!(Repo, "DROP TABLE IF EXISTS schema_migrations CASCADE", [])

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
        # already-loaded definition is current. Elixir raises
        # ArgumentError for the redefinition path; CompileError signals
        # an actual syntax/semantic failure in the migration file and
        # must propagate so a broken edit surfaces immediately rather
        # than silently using a stale in-memory module.
        ArgumentError -> :ok
        Code.LoadError -> :ok
      end
    end)
  end
end
