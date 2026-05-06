defmodule Ideajar.Ideas.TargetWindowTest do
  use ExUnit.Case, async: true

  alias Ideajar.Ideas.Idea
  alias Ideajar.Ideas.TargetWindow

  @today ~D[2026-05-06]

  describe "month_label/1" do
    @months_canonical [
      {1, "gennaio"},
      {2, "febbraio"},
      {3, "marzo"},
      {4, "aprile"},
      {5, "maggio"},
      {6, "giugno"},
      {7, "luglio"},
      {8, "agosto"},
      {9, "settembre"},
      {10, "ottobre"},
      {11, "novembre"},
      {12, "dicembre"}
    ]

    for {n, label} <- @months_canonical do
      test "month #{n} → #{inspect(label)}" do
        assert TargetWindow.month_label(unquote(n)) == unquote(label)
      end
    end
  end

  describe "format/2 — day range" do
    test "single day same year as today hides year" do
      window = %{
        start: ~D[2026-05-06],
        end: ~D[2026-05-06],
        granularity: :day,
        weekend_only: false
      }

      assert TargetWindow.format(window, @today) == "6 maggio"
    end

    test "multi-day same-month range" do
      window = %{
        start: ~D[2026-05-05],
        end: ~D[2026-05-07],
        granularity: :day,
        weekend_only: false
      }

      assert TargetWindow.format(window, @today) == "5-7 maggio"
    end

    test "multi-day cross-month, same year" do
      window = %{
        start: ~D[2026-05-30],
        end: ~D[2026-06-02],
        granularity: :day,
        weekend_only: false
      }

      assert TargetWindow.format(window, @today) == "30 maggio - 2 giugno"
    end

    test "single day in a future year shows year" do
      window = %{
        start: ~D[2027-01-15],
        end: ~D[2027-01-15],
        granularity: :day,
        weekend_only: false
      }

      assert TargetWindow.format(window, @today) == "15 gennaio 2027"
    end

    test "day range crossing the year boundary shows both years" do
      window = %{
        start: ~D[2026-12-30],
        end: ~D[2027-01-02],
        granularity: :day,
        weekend_only: false
      }

      assert TargetWindow.format(window, @today) == "30 dicembre 2026 - 2 gennaio 2027"
    end
  end

  describe "format/2 — month range" do
    test "single month, no weekend flag" do
      window = %{
        start: ~D[2026-05-01],
        end: ~D[2026-05-31],
        granularity: :month,
        weekend_only: false
      }

      assert TargetWindow.format(window, @today) == "maggio"
    end

    test "single month with weekend flag" do
      window = %{
        start: ~D[2026-05-01],
        end: ~D[2026-05-31],
        granularity: :month,
        weekend_only: true
      }

      assert TargetWindow.format(window, @today) == "weekend di maggio"
    end

    test "multi-month range, no weekend flag" do
      window = %{
        start: ~D[2026-05-01],
        end: ~D[2026-06-30],
        granularity: :month,
        weekend_only: false
      }

      assert TargetWindow.format(window, @today) == "maggio-giugno"
    end

    test "multi-month range with weekend flag" do
      window = %{
        start: ~D[2026-05-01],
        end: ~D[2026-06-30],
        granularity: :month,
        weekend_only: true
      }

      assert TargetWindow.format(window, @today) == "weekend tra maggio e giugno"
    end

    test "future-year single month shows year" do
      window = %{
        start: ~D[2027-01-01],
        end: ~D[2027-01-31],
        granularity: :month,
        weekend_only: false
      }

      assert TargetWindow.format(window, @today) == "gennaio 2027"
    end

    test "cross-year month range shows both years" do
      window = %{
        start: ~D[2026-12-01],
        end: ~D[2027-01-31],
        granularity: :month,
        weekend_only: false
      }

      assert TargetWindow.format(window, @today) == "dicembre 2026 - gennaio 2027"
    end
  end

  describe "from_idea/1" do
    test "returns nil when all 4 target fields are nil/false" do
      idea = %Idea{
        target_start: nil,
        target_end: nil,
        target_granularity: nil,
        target_weekend_only: false
      }

      assert TargetWindow.from_idea(idea) == nil
    end

    test "returns the value object when fully populated (day range)" do
      idea = %Idea{
        target_start: ~D[2026-05-06],
        target_end: ~D[2026-05-06],
        target_granularity: :day,
        target_weekend_only: false
      }

      assert TargetWindow.from_idea(idea) == %{
               start: ~D[2026-05-06],
               end: ~D[2026-05-06],
               granularity: :day,
               weekend_only: false
             }
    end

    test "returns the value object with weekend_only=true (month range)" do
      idea = %Idea{
        target_start: ~D[2026-05-01],
        target_end: ~D[2026-05-31],
        target_granularity: :month,
        target_weekend_only: true
      }

      assert TargetWindow.from_idea(idea).weekend_only == true
      assert TargetWindow.from_idea(idea).granularity == :month
    end

    test "raises on partial state (defensive — should be unreachable past changeset)" do
      idea = %Idea{
        target_start: ~D[2026-05-06],
        target_end: nil,
        target_granularity: nil,
        target_weekend_only: false
      }

      assert_raise ArgumentError, ~r/partial target window/i, fn ->
        TargetWindow.from_idea(idea)
      end
    end
  end

  describe "validate_changeset/1 — happy path" do
    test "all-nil target fields → cs valid (no errors added)" do
      cs = build_cs(%{})
      assert cs.valid?
      refute Keyword.has_key?(cs.errors, :target)
      refute Keyword.has_key?(cs.errors, :target_end)
    end

    test "valid day-range single → cs valid" do
      cs =
        build_cs(%{
          target_start: ~D[2026-05-06],
          target_end: ~D[2026-05-06],
          target_granularity: :day
        })

      assert cs.valid?
    end

    test "valid day-range multi → cs valid" do
      cs =
        build_cs(%{
          target_start: ~D[2026-05-05],
          target_end: ~D[2026-05-07],
          target_granularity: :day
        })

      assert cs.valid?
    end

    test "valid month-range single → cs valid" do
      cs =
        build_cs(%{
          target_start: ~D[2026-05-01],
          target_end: ~D[2026-05-31],
          target_granularity: :month
        })

      assert cs.valid?
    end

    test "valid month-range multi → cs valid" do
      cs =
        build_cs(%{
          target_start: ~D[2026-05-01],
          target_end: ~D[2026-06-30],
          target_granularity: :month
        })

      assert cs.valid?
    end
  end

  describe "validate_changeset/1 — end >= start" do
    test "end before start → error on :target_end with the canonical message" do
      cs =
        build_cs(%{
          target_start: ~D[2026-05-10],
          target_end: ~D[2026-05-05],
          target_granularity: :day
        })

      refute cs.valid?

      assert {message, _opts} = Keyword.fetch!(cs.errors, :target_end)
      assert message == "La data di fine deve essere uguale o successiva alla data di inizio"
    end
  end

  describe "validate_changeset/1 — month boundaries" do
    test "month granularity with start.day != 1 → error :target == 'Periodo non valido'" do
      cs =
        build_cs(%{
          target_start: ~D[2026-05-15],
          target_end: ~D[2026-05-31],
          target_granularity: :month
        })

      refute cs.valid?
      assert error_on(cs, :target) == "Periodo non valido"
    end

    test "month granularity with end != end-of-month → error :target == 'Periodo non valido'" do
      cs =
        build_cs(%{
          target_start: ~D[2026-05-01],
          target_end: ~D[2026-05-20],
          target_granularity: :month
        })

      refute cs.valid?
      assert error_on(cs, :target) == "Periodo non valido"
    end

    test "month granularity end-of-month boundary uses Date.end_of_month/1 (Feb non-leap)" do
      cs =
        build_cs(%{
          target_start: ~D[2027-02-01],
          target_end: ~D[2027-02-28],
          target_granularity: :month
        })

      assert cs.valid?
    end
  end

  describe "validate_changeset/1 — weekend coercion on day granularity" do
    test "weekend_only=true on day granularity is silently coerced to false" do
      cs =
        build_cs(%{
          target_start: ~D[2026-05-06],
          target_end: ~D[2026-05-06],
          target_granularity: :day,
          target_weekend_only: true
        })

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :target_weekend_only) == false
    end
  end

  describe "validate_changeset/1 — partial set rejected" do
    test "only target_start set → error :target" do
      cs = build_cs(%{target_start: ~D[2026-05-06]})
      refute cs.valid?
      assert error_on(cs, :target) == "Periodo non valido"
    end

    test "only target_end set → error :target" do
      cs = build_cs(%{target_end: ~D[2026-05-06]})
      refute cs.valid?
      assert error_on(cs, :target) == "Periodo non valido"
    end

    test "only target_granularity set → error :target" do
      cs = build_cs(%{target_granularity: :day})
      refute cs.valid?
      assert error_on(cs, :target) == "Periodo non valido"
    end

    test "two of three target fields set → error :target" do
      cs = build_cs(%{target_start: ~D[2026-05-06], target_granularity: :day})
      refute cs.valid?
      assert error_on(cs, :target) == "Periodo non valido"
    end
  end

  defp build_cs(attrs) do
    # Build via Idea.changeset/2 so the integration with the existing
    # changeset pipeline is exercised. Pre-populates a category to satisfy
    # the unrelated slice-3 "almeno una categoria" rule.
    base = Map.merge(%{title: "x"}, attrs)

    Idea.changeset(
      %Idea{},
      Map.put(base, :categories, [%Ideajar.Categories.Category{id: 1, name: "_test"}])
    )
  end

  defp error_on(cs, field) do
    case Keyword.fetch(cs.errors, field) do
      {:ok, {message, _opts}} -> message
      :error -> nil
    end
  end
end
