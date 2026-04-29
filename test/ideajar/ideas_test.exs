defmodule Ideajar.IdeasTest do
  # async: false: this module does many concurrent writes through the
  # `Ideas.create_idea/1` boundary, and the migrations test toggles the
  # SQLite Sandbox into `:auto` mode globally — that combination triggers
  # SQLite "Database busy" when the migrator's connection and an async
  # test both attempt to write. Serializing this module avoids the race.
  use Ideajar.DataCase, async: false

  alias Ideajar.Categories.Category
  alias Ideajar.Ideas
  alias Ideajar.Ideas.Idea

  @categories_required "Seleziona almeno una categoria"
  @category_invalid "Categoria non valida"
  @title_required "Il titolo è obbligatorio"

  defp by_name(name), do: Repo.get_by!(Category, name: name)

  defp first_error(%Ecto.Changeset{} = cs, field) do
    {message, _opts} = Keyword.fetch!(cs.errors, field)
    message
  end

  # ── Slice 4 fixture: 5 ideas across canonical categories ────────────
  defp seed_5_ideas do
    %{
      sirolo:
        insert_idea_with_categories!(
          "Sirolo",
          [by_name("mare"), by_name("viaggio")],
          ~U[2026-04-27 10:00:00Z]
        ),
      uffizi:
        insert_idea_with_categories!(
          "Uffizi",
          [by_name("museo"), by_name("cultura")],
          ~U[2026-04-27 10:01:00Z]
        ),
      stadio:
        insert_idea_with_categories!(
          "Stadio",
          [by_name("sport")],
          ~U[2026-04-27 10:02:00Z]
        ),
      bagno:
        insert_idea_with_categories!(
          "Bagno",
          [by_name("mare"), by_name("sport")],
          ~U[2026-04-27 10:03:00Z]
        ),
      cinema:
        insert_idea_with_categories!(
          "Cinema",
          [by_name("cinema"), by_name("cultura")],
          ~U[2026-04-27 10:04:00Z]
        )
    }
  end

  describe "list_ideas/1 — required (AND clause, slice 4)" do
    test "returns ideas tagged with the single required category" do
      _ = seed_5_ideas()
      mare = by_name("mare")

      titles = Ideas.list_ideas(required: [mare.id]) |> Enum.map(& &1.title) |> Enum.sort()
      assert titles == ["Bagno", "Sirolo"]
    end

    test "returns ideas tagged with all required categories (AND)" do
      _ = seed_5_ideas()
      mare = by_name("mare")
      sport = by_name("sport")

      titles =
        Ideas.list_ideas(required: [mare.id, sport.id]) |> Enum.map(& &1.title)

      assert titles == ["Bagno"]
    end

    test "returns [] when no idea has all required categories" do
      _ = seed_5_ideas()
      mare = by_name("mare")
      museo = by_name("museo")

      assert Ideas.list_ideas(required: [mare.id, museo.id]) == []
    end

    test "required: [] is a no-op (returns every idea)" do
      _ = seed_5_ideas()
      assert length(Ideas.list_ideas(required: [])) == 5
    end

    test "required: [non_existent_id] returns []" do
      _ = seed_5_ideas()
      assert Ideas.list_ideas(required: [999_999]) == []
    end

    test "duplicate ids in required are normalized via Enum.uniq" do
      _ = seed_5_ideas()
      mare = by_name("mare")

      titles_dup =
        Ideas.list_ideas(required: [mare.id, mare.id]) |> Enum.map(& &1.title) |> Enum.sort()

      titles_uniq =
        Ideas.list_ideas(required: [mare.id]) |> Enum.map(& &1.title) |> Enum.sort()

      assert titles_dup == titles_uniq
    end

    test "SQL emission pin (O2): subquery emits HAVING COUNT(DISTINCT …)" do
      mare = by_name("mare")
      sport = by_name("sport")

      query =
        from i in Idea,
          where:
            i.id in subquery(
              from ic in "idea_categories",
                where: ic.category_id in ^[mare.id, sport.id],
                group_by: ic.idea_id,
                having: count(fragment("DISTINCT ?", ic.category_id)) == ^2,
                select: ic.idea_id
            )

      {sql, _params} = Repo.to_sql(:all, query)
      assert sql =~ ~r/having\s+\(?\s*count\s*\(\s*distinct/i
    end
  end

  describe "list_ideas/1 — optional (OR clause, slice 4)" do
    test "returns ideas tagged with the single optional category" do
      _ = seed_5_ideas()
      sport = by_name("sport")

      titles =
        Ideas.list_ideas(optional: [sport.id]) |> Enum.map(& &1.title) |> Enum.sort()

      assert titles == ["Bagno", "Stadio"]
    end

    test "returns ideas tagged with any of the optional categories (OR)" do
      _ = seed_5_ideas()
      sport = by_name("sport")
      cultura = by_name("cultura")

      titles =
        Ideas.list_ideas(optional: [sport.id, cultura.id])
        |> Enum.map(& &1.title)
        |> Enum.sort()

      assert titles == ["Bagno", "Cinema", "Stadio", "Uffizi"]
    end

    test "optional: [] is a no-op (returns every idea)" do
      _ = seed_5_ideas()
      assert length(Ideas.list_ideas(optional: [])) == 5
    end

    test "optional: [non_existent_id] returns []" do
      _ = seed_5_ideas()
      assert Ideas.list_ideas(optional: [999_999]) == []
    end

    test "duplicate ids in optional are normalized" do
      _ = seed_5_ideas()
      sport = by_name("sport")

      titles_dup =
        Ideas.list_ideas(optional: [sport.id, sport.id])
        |> Enum.map(& &1.title)
        |> Enum.sort()

      titles_uniq =
        Ideas.list_ideas(optional: [sport.id])
        |> Enum.map(& &1.title)
        |> Enum.sort()

      assert titles_dup == titles_uniq
    end
  end

  describe "list_ideas/1 — combined required + optional (slice 4)" do
    test "mare required + (sport or cultura) optional → only Bagno" do
      _ = seed_5_ideas()
      mare = by_name("mare")
      sport = by_name("sport")
      cultura = by_name("cultura")

      titles =
        Ideas.list_ideas(required: [mare.id], optional: [sport.id, cultura.id])
        |> Enum.map(& &1.title)

      assert titles == ["Bagno"]
    end

    test "required only with optional: [] is identical to required only" do
      _ = seed_5_ideas()
      mare = by_name("mare")

      with_empty_opt = Ideas.list_ideas(required: [mare.id], optional: [])
      without_opt_key = Ideas.list_ideas(required: [mare.id])

      assert Enum.map(with_empty_opt, & &1.id) == Enum.map(without_opt_key, & &1.id)
    end

    test "optional only with required: [] is identical to optional only" do
      _ = seed_5_ideas()
      sport = by_name("sport")

      with_empty_req = Ideas.list_ideas(required: [], optional: [sport.id])
      without_req_key = Ideas.list_ideas(optional: [sport.id])

      assert Enum.map(with_empty_req, & &1.id) == Enum.map(without_req_key, & &1.id)
    end

    test "incompatible combinations return []" do
      _ = seed_5_ideas()
      mare = by_name("mare")
      museo = by_name("museo")

      assert Ideas.list_ideas(required: [mare.id], optional: [museo.id]) == []
    end
  end

  describe "list_ideas/1 — signature and guard (slice 4)" do
    test "list_ideas() == list_ideas([]) (regression for slice 3 callers)" do
      mare = by_name("mare")
      insert_idea_with_categories!("A", [mare], ~U[2026-04-27 10:00:00Z])
      insert_idea_with_categories!("B", [mare], ~U[2026-04-27 10:01:00Z])

      assert Enum.map(Ideas.list_ideas(), & &1.id) == Enum.map(Ideas.list_ideas([]), & &1.id)
    end

    test "exposes both arity 0 and arity 1 in __info__(:functions)" do
      arities =
        Ideas.__info__(:functions)
        |> Enum.filter(fn {name, _arity} -> name == :list_ideas end)
        |> Enum.map(fn {_name, arity} -> arity end)
        |> MapSet.new()

      assert MapSet.equal?(arities, MapSet.new([0, 1]))
    end

    test "raises ArgumentError when opts is not a keyword list" do
      assert_raise ArgumentError, ~r/keyword list/, fn ->
        Ideas.list_ideas([1, 2, 3])
      end
    end

    test "raises ArgumentError when opts is not a list at all" do
      assert_raise FunctionClauseError, fn ->
        Ideas.list_ideas("not a list")
      end
    end
  end

  describe "list_ideas/0" do
    test "returns an empty list when there are no ideas" do
      assert Ideas.list_ideas() == []
    end

    test "orders by inserted_at descending" do
      mare = by_name("mare")
      old = insert_idea_with_categories!("Vecchia", [mare], ~U[2026-04-26 10:00:00Z])
      new = insert_idea_with_categories!("Recente", [mare], ~U[2026-04-27 10:00:00Z])

      assert Enum.map(Ideas.list_ideas(), & &1.id) == [new.id, old.id]
    end

    test "tie-breaks ideas with the same inserted_at by id descending" do
      mare = by_name("mare")
      same = ~U[2026-04-27 10:00:00Z]
      first = insert_idea_with_categories!("First", [mare], same)
      second = insert_idea_with_categories!("Second", [mare], same)

      assert second.id > first.id
      assert Enum.map(Ideas.list_ideas(), & &1.id) == [second.id, first.id]
    end

    test "preloads :categories ordered by display_order ASC" do
      cinema = by_name("cinema")
      cultura = by_name("cultura")
      mare = by_name("mare")

      insert_idea_with_categories!("Mix", [cinema, mare, cultura], ~U[2026-04-27 10:00:00Z])

      [idea] = Ideas.list_ideas()
      names = Enum.map(idea.categories, & &1.name)
      # display_order: mare=2, cultura=6, cinema=7
      assert names == ["mare", "cultura", "cinema"]
    end
  end

  describe "create_idea/1 — happy path" do
    test "persists an idea with one category and preloads it ordered" do
      mare = by_name("mare")

      assert {:ok, %Idea{id: id, title: "Mare", categories: cats}} =
               Ideas.create_idea(%{title: "Mare", category_ids: [mare.id]})

      assert [%Category{id: cid, name: "mare"}] = cats
      assert cid == mare.id
      assert Enum.any?(Ideas.list_ideas(), &(&1.id == id))
    end

    test "persists an idea with multiple categories ordered by display_order" do
      mare = by_name("mare")
      cinema = by_name("cinema")
      cultura = by_name("cultura")

      assert {:ok, %Idea{categories: cats}} =
               Ideas.create_idea(%{
                 title: "Multi",
                 category_ids: [cinema.id, mare.id, cultura.id]
               })

      assert Enum.map(cats, & &1.name) == ["mare", "cultura", "cinema"]
    end
  end

  describe "create_idea/1 — F2 categories required" do
    test "rejects an empty category_ids list with the canonical error" do
      assert {:error, %Ecto.Changeset{} = cs} =
               Ideas.create_idea(%{title: "x", category_ids: []})

      assert first_error(cs, :categories) == @categories_required
      assert length(Keyword.get_values(cs.errors, :categories)) == 1
    end

    test "rejects a missing category_ids key with the canonical error" do
      assert {:error, %Ecto.Changeset{} = cs} = Ideas.create_idea(%{title: "x"})
      assert first_error(cs, :categories) == @categories_required
      assert length(Keyword.get_values(cs.errors, :categories)) == 1
    end

    test "still surfaces the title error when title is empty (slice-2 invariant)" do
      mare = by_name("mare")
      assert {:error, cs} = Ideas.create_idea(%{title: "", category_ids: [mare.id]})
      assert first_error(cs, :title) == @title_required
    end
  end

  describe "create_idea/1 — S2 hostile category_ids" do
    test "rejects a non-existent category_id with 'Categoria non valida'" do
      assert {:error, cs} = Ideas.create_idea(%{title: "x", category_ids: [999_999]})
      assert first_error(cs, :categories) == @category_invalid
      assert length(Keyword.get_values(cs.errors, :categories)) == 1
      assert Repo.aggregate(Idea, :count) == 0
    end

    test "rejects a mix of valid and invalid ids (no partial commit)" do
      mare = by_name("mare")
      assert {:error, cs} = Ideas.create_idea(%{title: "x", category_ids: [mare.id, 999_999]})
      assert first_error(cs, :categories) == @category_invalid
      assert Repo.aggregate(Idea, :count) == 0
    end

    for value <- [-1, 0, 1.5] do
      test "rejects #{inspect(value)} with the controlled error (no exception)" do
        assert {:error, cs} = Ideas.create_idea(%{title: "x", category_ids: [unquote(value)]})
        assert first_error(cs, :categories) == @category_invalid
      end
    end

    for value <- ["abc", ""] do
      test "rejects non-numeric string #{inspect(value)} with the controlled error" do
        assert {:error, cs} = Ideas.create_idea(%{title: "x", category_ids: [unquote(value)]})
        assert first_error(cs, :categories) == @category_invalid
      end
    end

    test "rejects a list containing nil" do
      assert {:error, cs} = Ideas.create_idea(%{title: "x", category_ids: [nil]})
      assert first_error(cs, :categories) == @category_invalid
    end
  end

  describe "create_idea/1 — S3 dedupe POST cast" do
    test "deduplicates duplicate integer ids" do
      mare = by_name("mare")
      sport = by_name("sport")

      assert {:ok, idea} =
               Ideas.create_idea(%{title: "x", category_ids: [mare.id, mare.id, sport.id]})

      assert length(idea.categories) == 2
    end

    test "deduplicates all-same ids and still satisfies min:1" do
      mare = by_name("mare")

      assert {:ok, idea} =
               Ideas.create_idea(%{title: "x", category_ids: [mare.id, mare.id, mare.id]})

      assert length(idea.categories) == 1
      assert hd(idea.categories).id == mare.id
    end

    test "deduplicates mixed-type duplicates ('id_string' and id_int)" do
      mare = by_name("mare")

      assert {:ok, idea} =
               Ideas.create_idea(%{title: "x", category_ids: ["#{mare.id}", mare.id]})

      assert length(idea.categories) == 1
    end
  end

  describe "create_idea/1 — string-keyed attrs (LiveView path)" do
    test "accepts string keys mirroring LV submission" do
      mare = by_name("mare")

      assert {:ok, %Idea{title: "Sirolo", categories: [%Category{}]}} =
               Ideas.create_idea(%{
                 "title" => "Sirolo",
                 "url" => "https://example.com",
                 "category_ids" => [mare.id]
               })
    end

    test "rejects invalid id with string keys, preserves title/url in changeset" do
      assert {:error, cs} =
               Ideas.create_idea(%{
                 "title" => "Sirolo",
                 "url" => "https://example.com",
                 "category_ids" => [999_999]
               })

      assert first_error(cs, :categories) == @category_invalid
      # Title and url are preserved on the changeset so the LiveView re-render
      # can show what the user typed.
      assert Ecto.Changeset.get_change(cs, :title) == "Sirolo"
      assert Ecto.Changeset.get_change(cs, :url) == "https://example.com"
    end
  end

  describe "changeset/2 — duration field (slice 5)" do
    test "valid 'weekend' string casts to :weekend atom in changes" do
      mare = by_name("mare")

      cs =
        Idea.changeset(%Idea{}, %{
          title: "Foo",
          url: "",
          description: "",
          categories: [mare],
          duration: "weekend"
        })

      assert cs.valid?
      assert cs.changes[:duration] == :weekend
    end

    test "duration: nil leaves :duration out of changes (NULL ammesso)" do
      mare = by_name("mare")

      cs =
        Idea.changeset(%Idea{}, %{
          title: "Foo",
          url: "",
          description: "",
          categories: [mare],
          duration: nil
        })

      assert cs.valid?
      refute Map.has_key?(cs.changes, :duration)
    end

    test "duration: '' leaves :duration out of changes (Ecto.Enum casts empty string to nil)" do
      mare = by_name("mare")

      cs =
        Idea.changeset(%Idea{}, %{
          title: "Foo",
          url: "",
          description: "",
          categories: [mare],
          duration: ""
        })

      assert cs.valid?
      refute Map.has_key?(cs.changes, :duration)
    end

    test "rejects 'schifoso' with the custom Italian error message" do
      mare = by_name("mare")

      cs =
        Idea.changeset(%Idea{}, %{
          title: "Foo",
          url: "",
          description: "",
          categories: [mare],
          duration: "schifoso"
        })

      refute cs.valid?
      assert {"Durata non valida", _opts} = Keyword.fetch!(cs.errors, :duration)
    end

    test "rejects '<script>' with the custom Italian error message" do
      mare = by_name("mare")

      cs =
        Idea.changeset(%Idea{}, %{
          title: "Foo",
          url: "",
          description: "",
          categories: [mare],
          duration: "<script>"
        })

      refute cs.valid?
      assert {"Durata non valida", _opts} = Keyword.fetch!(cs.errors, :duration)
    end

    test "schema declares :duration as a parameterized Ecto.Enum with Duration.values()" do
      type = Idea.__schema__(:type, :duration)

      assert match?({:parameterized, {Ecto.Enum, _}}, type)

      {:parameterized, {Ecto.Enum, %{mappings: mappings}}} = type
      atom_values = Enum.map(mappings, fn {atom, _string} -> atom end)

      assert atom_values == Ideajar.Ideas.Duration.values()
    end
  end

  describe "changeset/2 — estimated_cost field (slice 6)" do
    @cost_invalid "Budget non valido"

    test "valid '100' string casts to 100 integer in changes" do
      mare = by_name("mare")

      cs =
        Idea.changeset(%Idea{}, %{
          title: "Foo",
          url: "",
          description: "",
          categories: [mare],
          estimated_cost: "100"
        })

      assert cs.valid?
      assert cs.changes[:estimated_cost] == 100
    end

    test "estimated_cost: nil leaves :estimated_cost out of changes (NULL ammesso)" do
      mare = by_name("mare")

      cs =
        Idea.changeset(%Idea{}, %{
          title: "Foo",
          url: "",
          description: "",
          categories: [mare],
          estimated_cost: nil
        })

      assert cs.valid?
      refute Map.has_key?(cs.changes, :estimated_cost)
    end

    test "estimated_cost: '' leaves :estimated_cost out of changes (cast empty to nil)" do
      mare = by_name("mare")

      cs =
        Idea.changeset(%Idea{}, %{
          title: "Foo",
          url: "",
          description: "",
          categories: [mare],
          estimated_cost: ""
        })

      assert cs.valid?
      refute Map.has_key?(cs.changes, :estimated_cost)
    end

    test "out-of-whitelist '175' is cast to 175 then rejected via validate_inclusion" do
      mare = by_name("mare")

      cs =
        Idea.changeset(%Idea{}, %{
          title: "Foo",
          url: "",
          description: "",
          categories: [mare],
          estimated_cost: "175"
        })

      refute cs.valid?
      assert {@cost_invalid, _opts} = Keyword.fetch!(cs.errors, :estimated_cost)
    end

    test "negative out-of-whitelist '-50' is cast to -50 then rejected via validate_inclusion" do
      mare = by_name("mare")

      cs =
        Idea.changeset(%Idea{}, %{
          title: "Foo",
          url: "",
          description: "",
          categories: [mare],
          estimated_cost: "-50"
        })

      refute cs.valid?
      assert {@cost_invalid, _opts} = Keyword.fetch!(cs.errors, :estimated_cost)
    end

    test "non-numeric 'abc' fails the integer cast and override rewrites to canonical message" do
      mare = by_name("mare")

      cs =
        Idea.changeset(%Idea{}, %{
          title: "Foo",
          url: "",
          description: "",
          categories: [mare],
          estimated_cost: "abc"
        })

      refute cs.valid?
      assert {@cost_invalid, _opts} = Keyword.fetch!(cs.errors, :estimated_cost)
    end

    test "XSS-like '<script>' fails the integer cast and override rewrites to canonical message" do
      mare = by_name("mare")

      cs =
        Idea.changeset(%Idea{}, %{
          title: "Foo",
          url: "",
          description: "",
          categories: [mare],
          estimated_cost: "<script>"
        })

      refute cs.valid?
      assert {@cost_invalid, _opts} = Keyword.fetch!(cs.errors, :estimated_cost)
    end

    test "non-interference pin: cost cast failure + empty title surfaces both canonical errors" do
      mare = by_name("mare")

      cs =
        Idea.changeset(%Idea{}, %{
          title: "",
          url: "",
          description: "",
          categories: [mare],
          estimated_cost: "abc"
        })

      refute cs.valid?
      assert {@title_required, _} = Keyword.fetch!(cs.errors, :title)
      assert {@cost_invalid, _} = Keyword.fetch!(cs.errors, :estimated_cost)
    end
  end

  describe "list_ideas/1 with :durations opt (slice 5 step 5)" do
    # Background fixture matching the spec: 6 ideas across all 5 durations
    # plus one NULL-duration idea (Bagno improvviso) used as the regression
    # pin for AA7 NULL exclusion semantics.
    defp seed_6_ideas_with_durations do
      %{
        caffe:
          insert_idea_with_categories_and_duration!(
            "Caffè al volo",
            [by_name("passeggiata")],
            :poche_ore,
            ~U[2026-04-27 10:00:00Z]
          ),
        sirolo:
          insert_idea_with_categories_and_duration!(
            "Sirolo",
            [by_name("mare"), by_name("viaggio")],
            :weekend,
            ~U[2026-04-27 10:01:00Z]
          ),
        uffizi:
          insert_idea_with_categories_and_duration!(
            "Uffizi",
            [by_name("museo"), by_name("cultura")],
            :giornata,
            ~U[2026-04-27 10:02:00Z]
          ),
        stadio:
          insert_idea_with_categories_and_duration!(
            "Stadio",
            [by_name("sport")],
            :mezza_giornata,
            ~U[2026-04-27 10:03:00Z]
          ),
        parigi:
          insert_idea_with_categories_and_duration!(
            "Parigi 4 giorni",
            [by_name("viaggio"), by_name("cultura")],
            :piu_giorni,
            ~U[2026-04-27 10:04:00Z]
          ),
        bagno:
          insert_idea_with_categories_and_duration!(
            "Bagno improvviso",
            [by_name("mare")],
            nil,
            ~U[2026-04-27 10:05:00Z]
          )
      }
    end

    test "F6 regression: list_ideas([]) returns all 6 ideas (NULL passes)" do
      _ = seed_6_ideas_with_durations()

      titles = Ideas.list_ideas([]) |> Enum.map(& &1.title) |> Enum.sort()

      assert titles ==
               [
                 "Bagno improvviso",
                 "Caffè al volo",
                 "Parigi 4 giorni",
                 "Sirolo",
                 "Stadio",
                 "Uffizi"
               ]
    end

    test "F7 single duration filter: only :weekend ideas, NULL excluded" do
      _ = seed_6_ideas_with_durations()

      result = Ideas.list_ideas(durations: [:weekend])
      titles = Enum.map(result, & &1.title)

      assert titles == ["Sirolo"]
      # Pin: Bagno improvviso (NULL duration) is EXCLUDED.
      refute Enum.any?(result, &(&1.title == "Bagno improvviso"))
    end

    test "F8 multiple durations form OR (Sirolo + Uffizi)" do
      _ = seed_6_ideas_with_durations()

      result = Ideas.list_ideas(durations: [:weekend, :giornata])
      titles = result |> Enum.map(& &1.title) |> Enum.sort()

      assert titles == ["Sirolo", "Uffizi"]
      refute Enum.any?(result, &(&1.title == "Bagno improvviso"))
    end

    test "F10 empty durations list is inactive (NULL passes, all 6 returned)" do
      _ = seed_6_ideas_with_durations()

      titles =
        Ideas.list_ideas(durations: []) |> Enum.map(& &1.title) |> Enum.sort()

      assert titles ==
               [
                 "Bagno improvviso",
                 "Caffè al volo",
                 "Parigi 4 giorni",
                 "Sirolo",
                 "Stadio",
                 "Uffizi"
               ]
    end

    test "F9 combined required + durations is AND (only Sirolo, Parigi excluded)" do
      _ = seed_6_ideas_with_durations()
      viaggio = by_name("viaggio")

      titles =
        Ideas.list_ideas(required: [viaggio.id], durations: [:weekend])
        |> Enum.map(& &1.title)

      assert titles == ["Sirolo"]
    end

    test "NULL strict exclusion edge: only NULL idea in DB returns []" do
      _ =
        insert_idea_with_categories_and_duration!(
          "Bagno improvviso",
          [by_name("mare")],
          nil,
          ~U[2026-04-27 10:00:00Z]
        )

      assert Ideas.list_ideas(durations: [:weekend]) == []
    end

    test "duplicate atoms in durations are normalized via Enum.uniq" do
      _ = seed_6_ideas_with_durations()

      titles_dup =
        Ideas.list_ideas(durations: [:weekend, :weekend])
        |> Enum.map(& &1.title)
        |> Enum.sort()

      titles_uniq =
        Ideas.list_ideas(durations: [:weekend])
        |> Enum.map(& &1.title)
        |> Enum.sort()

      assert titles_dup == titles_uniq
    end

    test "unknown atom raises Ecto.Query.CastError (caller-responsibility contract)" do
      _ = seed_6_ideas_with_durations()

      # Boundary contract: `list_ideas/1` trusts callers to pass only atoms
      # in `Duration.values/0`. Production callers (LiveView toggle handlers)
      # gate input through `Duration.parse/1`, which filters to the whitelist
      # via `String.to_existing_atom/1`. If a bug ever lets an out-of-band
      # atom through, Ecto.Enum surfaces a CastError loudly instead of
      # silently returning a misleading empty list — this test pins that
      # contract so the safety net cannot drift.
      assert_raise Ecto.Query.CastError, fn ->
        Ideas.list_ideas(durations: [:totally_made_up])
      end
    end

    test "slice-4 regression: required: [mare_id] still returns Sirolo + Bagno" do
      _ = seed_6_ideas_with_durations()
      mare = by_name("mare")

      titles =
        Ideas.list_ideas(required: [mare.id])
        |> Enum.map(& &1.title)
        |> Enum.sort()

      assert titles == ["Bagno improvviso", "Sirolo"]
    end

    test "slice-4 regression: optional: [sport_id, cultura_id] still works (OR)" do
      _ = seed_6_ideas_with_durations()
      sport = by_name("sport")
      cultura = by_name("cultura")

      titles =
        Ideas.list_ideas(optional: [sport.id, cultura.id])
        |> Enum.map(& &1.title)
        |> Enum.sort()

      assert titles == ["Parigi 4 giorni", "Stadio", "Uffizi"]
    end

    test "O3 SQL emission pin: durations clause emits IN, no IS NULL" do
      # `build_query/1` is exposed as a `@doc false` test seam (see
      # `Ideajar.Ideas`) so we can introspect the Ecto query before
      # `Repo.all` runs. Parallel to other test seams in the codebase.
      query = Ideas.build_query(durations: [:weekend])
      {sql, _params} = Repo.to_sql(:all, query)

      assert sql =~ ~r/"duration"\s+IN/i
      refute sql =~ ~r/IS\s+NULL/i
    end
  end

  defp insert_idea_with_categories!(title, cats, %DateTime{} = at) do
    idea =
      %Idea{title: title}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:categories, cats)
      |> Repo.insert!()

    # Force inserted_at to a known value (Repo.insert! sets it to now()).
    Repo.update!(
      Ecto.Changeset.change(idea, inserted_at: at, updated_at: at),
      force: true
    )
  end

  defp insert_idea_with_categories_and_duration!(title, cats, duration, %DateTime{} = at) do
    idea =
      %Idea{title: title, duration: duration}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:categories, cats)
      |> Repo.insert!()

    Repo.update!(
      Ecto.Changeset.change(idea, inserted_at: at, updated_at: at),
      force: true
    )
  end
end
