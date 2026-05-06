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
end
