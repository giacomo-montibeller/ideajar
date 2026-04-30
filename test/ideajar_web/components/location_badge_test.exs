defmodule IdeajarWeb.Components.LocationBadgeTest do
  @moduledoc """
  Unit tests for the slice-7a step-5 `LocationBadge.location_badge/1`
  read-only badge rendered on idea cards when `idea.location_name` is
  set (with or without coords). State (b) name-only and state (c)
  name+coords both surface the badge; coords are not displayed (slice
  7b distance filter will use them).

  Parallel to `BudgetChip.budget_badge/1` — conditional rendering is
  the caller's responsibility (`:if={not is_nil(idea.location_name)}`
  in the template).

  AA14 — XSS structural pin: the badge label flows through HEEx
  auto-escape via `{@name}`. Never wrap with `raw/1` or
  `Phoenix.HTML.raw` (mirrors slice 6 step 5 BudgetChip badge AA14
  pin).
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias IdeajarWeb.Components.LocationBadge

  defp render_location_badge(assigns) do
    render_component(&LocationBadge.location_badge/1, assigns)
  end

  describe "location_badge/1" do
    test "name: \"Sirolo, AN\" renders <span data-testid=idea-location-badge> with 📍 prefix and the name" do
      html = render_location_badge(%{name: "Sirolo, AN"})

      assert html =~ ~s(data-testid="idea-location-badge")

      [_full, inner] =
        Regex.run(
          ~r{<span[^>]*data-testid="idea-location-badge"[^>]*>(.*?)</span>}s,
          html
        )

      assert String.trim(inner) == "📍 Sirolo, AN"
    end

    test "name: \"Casa di nonna\" renders that name inside the badge" do
      html = render_location_badge(%{name: "Casa di nonna"})

      [_full, inner] =
        Regex.run(
          ~r{<span[^>]*data-testid="idea-location-badge"[^>]*>(.*?)</span>}s,
          html
        )

      assert String.trim(inner) == "📍 Casa di nonna"
    end

    test "class string includes inline-flex and text-xs for visual consistency with other badges" do
      html = render_location_badge(%{name: "Sirolo, AN"})

      [span_tag] =
        Regex.run(
          ~r{<span[^>]*data-testid="idea-location-badge"[^>]*>},
          html
        )

      assert span_tag =~ "inline-flex"
      assert span_tag =~ "text-xs"
    end
  end

  describe "location_badge/1 — AA14 structural XSS pin" do
    # The badge label must flow through HEEx auto-escape via `{@name}`.
    # Never wrap with `raw/1` or `Phoenix.HTML.raw` (parallel to slice 6
    # step 5 BudgetChip badge AA14 pin and slice 5 DurationChip badge
    # AA14 pin).
    test "source contains {@name} interpolation and no raw/1 calls" do
      src =
        File.read!(Path.join(File.cwd!(), "lib/ideajar_web/components/location_badge.ex"))

      assert src =~ "{@name}"
      refute src =~ ~r/\braw\(/
      refute src =~ "Phoenix.HTML.raw"
    end

    test "declares attr :name, :string, required: true" do
      src =
        File.read!(Path.join(File.cwd!(), "lib/ideajar_web/components/location_badge.ex"))

      assert src =~ ~r/attr :name,\s*:string,\s*required: true/
    end
  end
end
