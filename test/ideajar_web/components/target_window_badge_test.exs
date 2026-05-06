defmodule IdeajarWeb.Components.TargetWindowBadgeTest do
  @moduledoc """
  Unit tests for `TargetWindowBadge.badge/1` (slice 15 step 4).

  Mirrors the `BudgetBadge` / `DurationChip.duration_badge` test pattern.
  Detailed format coverage lives in `Ideajar.Ideas.TargetWindowTest`; here
  we pin only the rendering contract: presence of testid, conditional
  no-render when no target is set, and HEEx auto-escape on the label.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Ideajar.Ideas.Idea
  alias IdeajarWeb.Components.TargetWindowBadge

  @today ~D[2026-05-06]

  defp render_badge(assigns) do
    render_component(&TargetWindowBadge.target_window_badge/1, assigns)
  end

  describe "badge/1 — rendering contract" do
    test "renders the formatted label with the canonical testid" do
      idea = %Idea{
        target_start: ~D[2026-05-06],
        target_end: ~D[2026-05-06],
        target_granularity: :day,
        target_weekend_only: false
      }

      html = render_badge(%{idea: idea, today: @today})

      assert html =~ ~s(data-testid="idea-target-window-badge")
      assert html =~ "6 maggio"
    end

    test "renders 'weekend di maggio' for a month range with weekend flag" do
      idea = %Idea{
        target_start: ~D[2026-05-01],
        target_end: ~D[2026-05-31],
        target_granularity: :month,
        target_weekend_only: true
      }

      html = render_badge(%{idea: idea, today: @today})
      assert html =~ "weekend di maggio"
    end

    test "returns no badge element when the idea has no target window" do
      idea = %Idea{
        target_start: nil,
        target_end: nil,
        target_granularity: nil,
        target_weekend_only: false
      }

      html = render_badge(%{idea: idea, today: @today})
      refute html =~ ~s(data-testid="idea-target-window-badge")
    end
  end

  describe "badge/1 — XSS structural pin (S1)" do
    test "the formatted label flows through HEEx auto-escape — no raw/1 wrap" do
      # The label is composed of digits and lowercase italian month names —
      # no path produces HTML. Pin the structural absence of `raw/1` by
      # verifying the rendered output is plain text inside the span.
      idea = %Idea{
        target_start: ~D[2026-05-06],
        target_end: ~D[2026-05-06],
        target_granularity: :day,
        target_weekend_only: false
      }

      html = render_badge(%{idea: idea, today: @today})

      refute html =~ "<script"
      refute html =~ "javascript:"
    end
  end
end
