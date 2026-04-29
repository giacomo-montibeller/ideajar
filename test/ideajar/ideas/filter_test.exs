defmodule Ideajar.Ideas.FilterTest do
  # async: false matching `Ideajar.IdeasTest` for the same migration-toggle
  # rationale: the migrations test flips the SQLite Sandbox to :auto and any
  # async test that writes through the same Repo races against it. Test 5
  # below seeds and queries the DB through `Filter.apply/2`, so we serialize.
  use Ideajar.DataCase, async: false

  alias Ideajar.Categories.Category
  alias Ideajar.Ideas.Filter
  alias Ideajar.Ideas.Idea

  defp by_name(name), do: Repo.get_by!(Category, name: name)

  defp base_query do
    from i in Idea, order_by: [desc: i.inserted_at, desc: i.id]
  end

  defp insert_idea_with_categories!(title, cats, %DateTime{} = at) do
    idea =
      %Idea{title: title}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:categories, cats)
      |> Repo.insert!()

    Repo.update!(
      Ecto.Changeset.change(idea, inserted_at: at, updated_at: at),
      force: true
    )
  end

  describe "apply/2 — module surface (slice 6 R5-1 extraction)" do
    test "exports apply/2 as a public function" do
      # R1 pin: the public API contract for the new `Ideajar.Ideas.Filter`
      # module is `apply(query, opts)`. Dynamic introspection prevents
      # accidental private-ization or arity drift across future slices.
      assert function_exported?(Ideajar.Ideas.Filter, :apply, 2)
    end

    test "apply(query, []) returns the query unchanged (no-op SQL)" do
      # No-op pin: empty opts MUST emit identical SQL to the input query.
      # We compare via Repo.to_sql/2 so the contract holds at the SQL layer
      # (parameters and shape) rather than at Elixir struct equality, which
      # is brittle across Ecto versions.
      query = base_query()

      assert Repo.to_sql(:all, Filter.apply(query, [])) ==
               Repo.to_sql(:all, query)
    end
  end

  describe "extraction completeness pin (slice 6 step 2)" do
    test "lib/ideajar/ideas.ex no longer defines defp apply_filters" do
      # Regression pin: the slice-5 `defp apply_filters/2` MUST be removed
      # from `Ideajar.Ideas` so no parallel implementation can drift from
      # `Filter.apply/2`. Reading the source rather than introspecting at
      # runtime is intentional: private functions are still in
      # __info__(:functions) at runtime in some Elixir variants only when
      # @compile :debug_info is set, and this is the canonical way the
      # rest of the suite verifies "this defp is gone".
      source = File.read!("lib/ideajar/ideas.ex")
      refute source =~ "defp apply_filters"
    end
  end

  describe "apply/2 — direct unit test seam (test 5)" do
    test "required: [id] returns ideas tagged with the required category" do
      # Test seam pin: `Filter.apply/2` is callable directly on a base
      # query, without going through `Ideas.list_ideas/1`. This proves the
      # module is genuinely reusable (and not just an internal alias) and
      # makes the future `apply_max_cost/2` clause (slice 6 step 6)
      # directly testable in isolation.
      mare = by_name("mare")
      sport = by_name("sport")

      bagno =
        insert_idea_with_categories!("Bagno", [mare, sport], ~U[2026-04-27 10:00:00Z])

      sirolo =
        insert_idea_with_categories!("Sirolo", [mare], ~U[2026-04-27 10:01:00Z])

      _stadio =
        insert_idea_with_categories!("Stadio", [sport], ~U[2026-04-27 10:02:00Z])

      ids =
        base_query()
        |> Filter.apply(required: [mare.id])
        |> Repo.all()
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert ids == Enum.sort([bagno.id, sirolo.id])
    end
  end

  describe "apply/2 — :max_cost clause (slice 6 step 6, BB8)" do
    defp insert_idea_with_cost!(title, cost, %DateTime{} = at) do
      mare = by_name("mare")

      idea =
        %Idea{title: title, estimated_cost: cost}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:categories, [mare])
        |> Repo.insert!()

      Repo.update!(
        Ecto.Changeset.change(idea, inserted_at: at, updated_at: at),
        force: true
      )
    end

    test "max_cost: nil returns the query unchanged (clause inactive)" do
      # nil means clause inactive — emitted SQL must equal the no-op SQL
      # (which itself equals the input base query SQL). This is the F12
      # pin at the Filter unit-test layer.
      query = base_query()

      assert Repo.to_sql(:all, Filter.apply(query, max_cost: nil)) ==
               Repo.to_sql(:all, query)
    end

    test "max_cost: 100 emits estimated_cost <= 100 AND a NULL-exclude predicate" do
      # O3 SQL emission pin via direct Filter.apply/2 call. The regex is
      # case-insensitive with whitespace tolerance to stay robust across
      # ecto_sqlite3 quoting styles (BB15). ecto_sqlite3 currently emits
      # `not is_nil/1` as `NOT (... IS NULL)` rather than `IS NOT NULL`,
      # so we accept either canonical form — both are semantically the
      # NULL-exclude predicate we intend.
      query = base_query()
      {sql, params} = Repo.to_sql(:all, Filter.apply(query, max_cost: 100))

      assert sql =~ ~r/"estimated_cost"\s+<=/i

      # NULL-exclude predicate present in either of the two canonical
      # forms ecto adapters emit for `not is_nil(field)`.
      assert sql =~ ~r/IS\s+NOT\s+NULL/i or
               sql =~ ~r/NOT\s*\([^)]*"estimated_cost"\s+IS\s+NULL/i

      # Forbid an `OR ... IS NULL` permissive branch (NULL-pass leak).
      # The emitted `NOT (... IS NULL)` predicate is allowed because the
      # `NOT` precedes — we look for an `IS NULL` not preceded by `NOT (`
      # at any distance and not preceded by `IS NOT`.
      refute sql =~ ~r/\bOR\b[^()]*IS\s+NULL/i

      # The 100 threshold is parameterized, not inlined.
      assert 100 in params
    end

    test "max_cost: 100 DB roundtrip excludes NULL and over-threshold ideas" do
      # Direct unit test on `apply_max_cost` via `Filter.apply/2` with only
      # `:max_cost` opt + DB roundtrip. Combines the SQL emission pin with
      # the runtime semantics: cost ≤ 100 AND cost IS NOT NULL.
      cheap = insert_idea_with_cost!("Cheap", 50, ~U[2026-04-27 10:00:00Z])
      boundary = insert_idea_with_cost!("Boundary", 100, ~U[2026-04-27 10:01:00Z])
      _expensive = insert_idea_with_cost!("Expensive", 500, ~U[2026-04-27 10:02:00Z])
      _null_cost = insert_idea_with_cost!("Sconosciuto", nil, ~U[2026-04-27 10:03:00Z])

      ids =
        base_query()
        |> Filter.apply(max_cost: 100)
        |> Repo.all()
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert ids == Enum.sort([cheap.id, boundary.id])
    end
  end
end
