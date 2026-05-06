defmodule Ideajar.Ideas.IdeaTest do
  use Ideajar.DataCase, async: true

  alias Ideajar.Categories.Category
  alias Ideajar.Ideas.Idea

  @title_required "Il titolo è obbligatorio"
  @title_too_long "Il titolo non può superare i 200 caratteri"
  @url_invalid "Il link deve iniziare con http:// o https://"
  @url_too_long "Il link non può superare i 2000 caratteri"
  @categories_required "Seleziona almeno una categoria"

  # Default helper used by slice-2-era validation tests: pre-attaches a
  # canonical category so the changeset's slice-3 "min: 1 category" rule
  # does not fail tests that are about title / description / url. Tests
  # that specifically exercise the categories rule (or set their own)
  # provide :categories explicitly and override this default.
  defp changeset(attrs) do
    cat = Repo.get_by!(Category, name: "mare")

    full_attrs =
      if Map.has_key?(attrs, :categories) or Map.has_key?(attrs, "categories") do
        attrs
      else
        Map.put(attrs, :categories, [cat])
      end

    Idea.changeset(%Idea{}, full_attrs)
  end

  defp first_error(%Ecto.Changeset{} = cs, field) do
    {message, _opts} = Keyword.fetch!(cs.errors, field)
    message
  end

  defp by_name(name), do: Repo.get_by!(Category, name: name)

  describe "schema" do
    test "lists the expected fields" do
      assert Idea.__schema__(:fields) ==
               [
                 :id,
                 :title,
                 :description,
                 :url,
                 :duration,
                 :estimated_cost,
                 :location_name,
                 :lat,
                 :lng,
                 :target_start,
                 :target_end,
                 :target_granularity,
                 :target_weekend_only,
                 :inserted_at,
                 :updated_at
               ]
    end

    test "target_granularity is an Ecto.Enum with [:day, :month] values" do
      type = Idea.__schema__(:type, :target_granularity)
      # Ecto stores parameterized type as a tuple {:parameterized, ...}.
      # Use Ecto.Enum.values/2 to assert the whitelist.
      assert Ecto.Enum.values(Idea, :target_granularity) == [:day, :month]
      refute is_nil(type)
    end
  end

  describe "schema — target window round-trip (slice 15 step 1)" do
    test "round-trips a fully populated day-range target window" do
      mare = by_name("mare")

      {:ok, idea} =
        Repo.insert(
          Idea.changeset(%Idea{}, %{
            title: "Cinema stasera",
            categories: [mare],
            target_start: ~D[2026-05-06],
            target_end: ~D[2026-05-06],
            target_granularity: :day,
            target_weekend_only: false
          })
        )

      reloaded = Repo.get!(Idea, idea.id)
      assert reloaded.target_start == ~D[2026-05-06]
      assert reloaded.target_end == ~D[2026-05-06]
      assert reloaded.target_granularity == :day
      assert reloaded.target_weekend_only == false
    end

    test "round-trips a month-range with weekend-only=true" do
      mare = by_name("mare")

      {:ok, idea} =
        Repo.insert(
          Idea.changeset(%Idea{}, %{
            title: "Mare a maggio",
            categories: [mare],
            target_start: ~D[2026-05-01],
            target_end: ~D[2026-05-31],
            target_granularity: :month,
            target_weekend_only: true
          })
        )

      reloaded = Repo.get!(Idea, idea.id)
      assert reloaded.target_granularity == :month
      assert reloaded.target_weekend_only == true
    end

    test "an idea without target window has all 4 fields nil/false" do
      mare = by_name("mare")

      {:ok, idea} = Repo.insert(Idea.changeset(%Idea{}, %{title: "x", categories: [mare]}))
      reloaded = Repo.get!(Idea, idea.id)

      assert is_nil(reloaded.target_start)
      assert is_nil(reloaded.target_end)
      assert is_nil(reloaded.target_granularity)
      assert reloaded.target_weekend_only == false
    end
  end

  describe "changeset/2 — categories (slice 3)" do
    test "is valid with a populated categories list" do
      mare = by_name("mare")
      assert changeset(%{title: "x", categories: [mare]}).valid?
    end

    test "rejects a missing :categories key with a single canonical error" do
      cs = Idea.changeset(%Idea{}, %{title: "x"})
      refute cs.valid?
      assert first_error(cs, :categories) == @categories_required
      assert length(Keyword.get_values(cs.errors, :categories)) == 1
    end

    test "rejects an empty categories list with the canonical error" do
      cs = Idea.changeset(%Idea{}, %{title: "x", categories: []})
      refute cs.valid?
      assert first_error(cs, :categories) == @categories_required
      assert length(Keyword.get_values(cs.errors, :categories)) == 1
    end

    test "is valid with two distinct categories and stores them in :categories" do
      mare = by_name("mare")
      sport = by_name("sport")

      cs = changeset(%{title: "x", categories: [mare, sport]})

      assert cs.valid?
      ids = cs.changes[:categories] |> Enum.map(& &1.data.id)
      assert mare.id in ids
      assert sport.id in ids
      assert length(cs.changes[:categories]) == 2
    end

    test "regression: an empty changeset (used by LV form mount) does not crash" do
      cs = Idea.changeset(%Idea{}, %{})

      refute cs.valid?
      # Both :title and :categories should error — both are required.
      assert {@title_required, _} = Keyword.fetch!(cs.errors, :title)
      assert {@categories_required, _} = Keyword.fetch!(cs.errors, :categories)
    end
  end

  describe "Repo.insert/1" do
    test "persists a fully populated idea" do
      assert {:ok, %Idea{} = idea} =
               Repo.insert(%Idea{
                 title: "Mare",
                 description: "x",
                 url: "https://example.com"
               })

      assert is_integer(idea.id)
      assert %DateTime{} = idea.inserted_at
      assert %DateTime{} = idea.updated_at
    end

    test "rejects a nil title with a NOT NULL constraint error" do
      assert_raise Postgrex.Error, ~r/not-null|NOT NULL/i, fn ->
        Repo.insert(%Idea{title: nil})
      end
    end
  end

  describe "changeset/2 — title" do
    test "with a non-empty title is valid" do
      assert changeset(%{title: "Mare"}).valid?
    end

    test "rejects a missing title with the canonical message" do
      cs = changeset(%{title: ""})
      refute cs.valid?
      assert first_error(cs, :title) == @title_required
    end

    test "rejects a whitespace-only title (trimmed before validation, F6)" do
      cs = changeset(%{title: "   "})
      refute cs.valid?
      assert first_error(cs, :title) == @title_required
    end

    test "rejects a 201-char title with the canonical too-long message" do
      cs = changeset(%{title: String.duplicate("a", 201)})
      refute cs.valid?
      assert first_error(cs, :title) == @title_too_long
    end

    test "accepts a title of exactly 200 characters (boundary)" do
      assert changeset(%{title: String.duplicate("a", 200)}).valid?
    end
  end

  describe "changeset/2 — description" do
    test "accepts an arbitrarily long description (no app-level cap, A2)" do
      assert changeset(%{title: "x", description: String.duplicate("d", 100_000)}).valid?
    end
  end

  describe "changeset/2 — url" do
    test "accepts an empty url (optional)" do
      assert changeset(%{title: "x", url: ""}).valid?
    end

    test "treats whitespace-only url as empty (optional)" do
      assert changeset(%{title: "x", url: "   "}).valid?
    end

    test "trims surrounding whitespace from a valid url" do
      cs = changeset(%{title: "x", url: "  https://example.com  "})
      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :url) == "https://example.com"
    end

    test "rejects a 2001-char url with the canonical too-long message" do
      cs = changeset(%{title: "x", url: String.duplicate("h", 2001)})
      refute cs.valid?
      assert first_error(cs, :url) == @url_too_long
    end

    test "accepts a 2000-char https url (boundary)" do
      url = "https://" <> String.duplicate("a", 1992)
      assert String.length(url) == 2000
      assert changeset(%{title: "x", url: url}).valid?
    end

    test "accumulates errors on both title and url without short-circuiting" do
      cs = changeset(%{title: "", url: "ftp://x"})
      refute cs.valid?
      assert first_error(cs, :title) == @title_required
      assert first_error(cs, :url) == @url_invalid
    end

    for value <- [
          "not-a-url",
          "ftp://example.com",
          "javascript:alert(1)",
          "mailto:foo@bar.com",
          "http:/missing-slash",
          "data:text/html,<script>alert(1)</script>",
          "https://",
          "://example.com"
        ] do
      test "rejects invalid url #{inspect(value)}" do
        cs = changeset(%{title: "x", url: unquote(value)})
        refute cs.valid?
        assert first_error(cs, :url) == @url_invalid
      end
    end

    for value <- [
          "http://example.com",
          "https://example.com",
          "HTTPS://example.com",
          "Http://Example.com"
        ] do
      test "accepts valid url #{inspect(value)} (case-insensitive scheme, S5)" do
        assert changeset(%{title: "x", url: unquote(value)}).valid?
      end
    end
  end
end
