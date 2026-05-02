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

  describe "apply_post/2 — slice 7b post-query distance filter (DD3)" do
    # `apply_post/2` operates on the in-memory list AFTER the SQL query
    # returns + Repo.preload runs. Slice 7b's only post-query clause is
    # `apply_max_distance/2` which uses `Ideajar.Ideas.Distance.km/4`.
    # Tests build plain `%Idea{}` structs (no Repo round-trip) — the
    # function is pure and the boundary between query and post-query is
    # exactly that.

    # Sirolo, AN baseline reference point (43.5, 13.6).
    @sirolo_lat 43.5
    @sirolo_lng 13.6

    defp ideas_fixture do
      [
        %Idea{id: 1, title: "Sirolo", lat: 43.5, lng: 13.6},
        %Idea{id: 2, title: "Ancona", lat: 43.6, lng: 13.5},
        %Idea{id: 3, title: "Roma", lat: 41.9, lng: 12.5},
        %Idea{id: 4, title: "Parigi", lat: 48.85, lng: 2.35},
        %Idea{id: 5, title: "Senza coords", lat: nil, lng: nil},
        %Idea{id: 6, title: "Solo lat", lat: 43.5, lng: nil},
        %Idea{id: 7, title: "Solo lng", lat: nil, lng: 13.6}
      ]
    end

    test "no opts → list unchanged" do
      ideas = ideas_fixture()
      assert Filter.apply_post(ideas, []) == ideas
    end

    test "max_distance_km nil → no-op" do
      ideas = ideas_fixture()
      assert Filter.apply_post(ideas, max_distance_km: nil) == ideas
    end

    test "max_distance_km: 5 + ref Sirolo → only ideas within 5 km AND non-nil coords" do
      ideas = ideas_fixture()

      result =
        Filter.apply_post(ideas,
          max_distance_km: 5,
          ref_lat: @sirolo_lat,
          ref_lng: @sirolo_lng
        )

      titles = Enum.map(result, & &1.title)
      assert "Sirolo" in titles
      refute "Ancona" in titles
      refute "Roma" in titles
      refute "Parigi" in titles
      refute "Senza coords" in titles
      refute "Solo lat" in titles
      refute "Solo lng" in titles
    end

    test "max_distance_km: 1_000_000 (slider idx 6 mapping) → all ideas with non-nil coords, NULL excluded" do
      ideas = ideas_fixture()

      result =
        Filter.apply_post(ideas,
          max_distance_km: 1_000_000,
          ref_lat: @sirolo_lat,
          ref_lng: @sirolo_lng
        )

      titles = Enum.map(result, & &1.title)
      assert "Sirolo" in titles
      assert "Ancona" in titles
      assert "Roma" in titles
      assert "Parigi" in titles
      refute "Senza coords" in titles
      refute "Solo lat" in titles
      refute "Solo lng" in titles
    end

    test "ref_lat nil → no-op (DD5 defensive)" do
      ideas = ideas_fixture()

      result =
        Filter.apply_post(ideas,
          max_distance_km: 50,
          ref_lat: nil,
          ref_lng: @sirolo_lng
        )

      assert result == ideas
    end

    test "ref_lng nil → no-op (DD5 defensive)" do
      ideas = ideas_fixture()

      result =
        Filter.apply_post(ideas,
          max_distance_km: 50,
          ref_lat: @sirolo_lat,
          ref_lng: nil
        )

      assert result == ideas
    end

    test "idea with lat nil but lng set → excluded when filter on" do
      ideas = ideas_fixture()

      result =
        Filter.apply_post(ideas,
          max_distance_km: 1_000_000,
          ref_lat: @sirolo_lat,
          ref_lng: @sirolo_lng
        )

      refute Enum.any?(result, &(&1.title == "Solo lng"))
    end

    test "idea with lng nil but lat set → excluded when filter on" do
      ideas = ideas_fixture()

      result =
        Filter.apply_post(ideas,
          max_distance_km: 1_000_000,
          ref_lat: @sirolo_lat,
          ref_lng: @sirolo_lng
        )

      refute Enum.any?(result, &(&1.title == "Solo lat"))
    end
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

  describe "apply/2 — :text_search clause (slice 8)" do
    # Text-search filter on title + description. Case-insensitive LIKE
    # with literal-character escape for `%`, `_`, `\`. NULL-description
    # ideas pass through if title matches (DD-S8-4 documented exception
    # to the slice 5/6/7b uniform NULL-exclude pattern).

    defp insert_idea_with_title_desc!(title, desc, %DateTime{} = at) do
      mare = by_name("mare")

      idea =
        %Idea{title: title, description: desc}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:categories, [mare])
        |> Repo.insert!()

      Repo.update!(
        Ecto.Changeset.change(idea, inserted_at: at, updated_at: at),
        force: true
      )
    end

    test "text_search: nil returns the query unchanged (clause inactive)" do
      query = base_query()

      assert Repo.to_sql(:all, Filter.apply(query, text_search: nil)) ==
               Repo.to_sql(:all, query)
    end

    test "text_search: \"\" empty string is a no-op (< 3 chars)" do
      query = base_query()

      assert Repo.to_sql(:all, Filter.apply(query, text_search: "")) ==
               Repo.to_sql(:all, query)
    end

    test "text_search: \"ma\" (< 3 chars) is a no-op" do
      query = base_query()

      assert Repo.to_sql(:all, Filter.apply(query, text_search: "ma")) ==
               Repo.to_sql(:all, query)
    end

    test "text_search: \"mar\" emits LOWER LIKE LOWER ESCAPE '\\' on title + description" do
      # SQL emission pin (DM3, B1 fix iter1). Elixir source `"\\"` is 1
      # byte runtime `\`; Elixir source `"\\\\"` is 2 byte runtime `\\`.
      # SQLite ESCAPE requires exactly 1 byte. The fragment template
      # uses `"ESCAPE '\\'"` (Elixir source 4 chars: ' \ \ ') producing
      # SQL byte sequence `ESCAPE '\'` (1 byte escape char). The regex
      # below uses Elixir source `\\` to match the 1-byte runtime `\`.
      query = base_query()
      {sql, params} = Repo.to_sql(:all, Filter.apply(query, text_search: "mar"))

      assert sql =~ ~r/LOWER\(.*?\) LIKE LOWER\(.*?\) ESCAPE '\\'/
      # Description clause must include the IS NOT NULL guard (DD-S8-4).
      assert sql =~ ~r/IS NOT NULL.*LIKE/is

      # The pattern is parametrised — `%mar%` literal substring with
      # wildcards wrapping. No SQL injection surface.
      assert "%mar%" in params
    end

    test "text_search: 123 (non-binary) is a no-op (defensive)" do
      query = base_query()

      assert Repo.to_sql(:all, Filter.apply(query, text_search: 123)) ==
               Repo.to_sql(:all, query)
    end

    test "DB roundtrip: text_search matches title or description, case-insensitive, NULL desc passes if title matches" do
      a = insert_idea_with_title_desc!("Sirolo", "Mare bellissimo", ~U[2026-04-27 10:00:00Z])
      b = insert_idea_with_title_desc!("Uffizi", "Galleria di Firenze", ~U[2026-04-27 10:01:00Z])
      c = insert_idea_with_title_desc!("Picnic improvviso", nil, ~U[2026-04-27 10:02:00Z])
      d = insert_idea_with_title_desc!("MARE in tempesta", nil, ~U[2026-04-27 10:03:00Z])

      # Lowercase query → case-insensitive match on both title and
      # description; NULL-description "MARE in tempesta" matches via
      # title; NULL-description "Picnic improvviso" excluded (neither
      # field matches "mare").
      ids =
        base_query()
        |> Filter.apply(text_search: "mare")
        |> Repo.all()
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert ids == Enum.sort([a.id, d.id])
      refute b.id in ids
      refute c.id in ids
    end

    test "case-insensitive: query MARE matches title 'sirolo' description 'mare bellissimo'" do
      _ = insert_idea_with_title_desc!("Sirolo", "mare bellissimo", ~U[2026-04-27 10:00:00Z])

      ids =
        base_query()
        |> Filter.apply(text_search: "MARE")
        |> Repo.all()
        |> Enum.map(& &1.id)

      assert length(ids) == 1
    end

    test "LIKE wildcard escape: query \"%\" treats it as literal, only ideas containing literal % match" do
      # Without escape, `%` would be an SQL wildcard matching every
      # row. With escape, only ideas whose title or description
      # contains a literal `%` character pass.
      with_pct = insert_idea_with_title_desc!("Sale 50% off", nil, ~U[2026-04-27 10:00:00Z])
      _no_pct = insert_idea_with_title_desc!("Senza simboli", nil, ~U[2026-04-27 10:01:00Z])

      ids =
        base_query()
        |> Filter.apply(text_search: "50%")
        |> Repo.all()
        |> Enum.map(& &1.id)

      assert ids == [with_pct.id]
    end

    test "LIKE wildcard escape: query \"a_b\" treats `_` as literal" do
      with_underscore =
        insert_idea_with_title_desc!("test_a_b_test", nil, ~U[2026-04-27 10:00:00Z])

      _without =
        insert_idea_with_title_desc!("test axb test", nil, ~U[2026-04-27 10:01:00Z])

      ids =
        base_query()
        |> Filter.apply(text_search: "a_b")
        |> Repo.all()
        |> Enum.map(& &1.id)

      assert ids == [with_underscore.id]
    end

    test "LIKE escape character: query containing literal \\ is treated as literal char" do
      # Elixir runtime: "\\foo" is 4 bytes: \ f o o.
      with_backslash = insert_idea_with_title_desc!("\\foo", nil, ~U[2026-04-27 10:00:00Z])
      _without = insert_idea_with_title_desc!("foo", nil, ~U[2026-04-27 10:01:00Z])

      ids =
        base_query()
        |> Filter.apply(text_search: "\\foo")
        |> Repo.all()
        |> Enum.map(& &1.id)

      assert ids == [with_backslash.id]
    end

    test "description-only match: title doesn't match but description does → idea returned" do
      a =
        insert_idea_with_title_desc!("Concerto rock", "Stadio Olimpico", ~U[2026-04-27 10:00:00Z])

      _b = insert_idea_with_title_desc!("Sirolo", "Mare bellissimo", ~U[2026-04-27 10:01:00Z])

      ids =
        base_query()
        |> Filter.apply(text_search: "stadio")
        |> Repo.all()
        |> Enum.map(& &1.id)

      assert ids == [a.id]
    end
  end
end
