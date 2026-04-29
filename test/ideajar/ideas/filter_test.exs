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
end
