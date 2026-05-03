defmodule IdeajarWeb.Components.BudgetBadgeTest do
  @moduledoc """
  Slice 9 — extracted from `BudgetChipTest` `describe "budget_badge/1"`
  ahead of the `BudgetChip` module deletion. The rendering contract is
  identical to slice 6 BB12 (data-testid, IT labels) plus the AA14 XSS
  structural pin (HEEx auto-escape, no `raw/1`).
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias IdeajarWeb.Components.BudgetBadge

  defp render_badge(assigns), do: render_component(&BudgetBadge.badge/1, assigns)

  test "cost: 100 renders <span data-testid=idea-budget-badge> with IT label" do
    html = render_badge(%{cost: 100})

    assert html =~ ~s(data-testid="idea-budget-badge")

    [_full, inner] =
      Regex.run(
        ~r{<span[^>]*data-testid="idea-budget-badge"[^>]*>(.*?)</span>}s,
        html
      )

    assert String.trim(inner) == "fino a 100€"
  end

  test "cost: 0 renders the IT label 'gratis'" do
    html = render_badge(%{cost: 0})

    [_full, inner] =
      Regex.run(
        ~r{<span[^>]*data-testid="idea-budget-badge"[^>]*>(.*?)</span>}s,
        html
      )

    assert String.trim(inner) == "gratis"
  end

  test "cost: 1000 renders the IT label 'oltre 1000€'" do
    html = render_badge(%{cost: 1000})

    [_full, inner] =
      Regex.run(
        ~r{<span[^>]*data-testid="idea-budget-badge"[^>]*>(.*?)</span>}s,
        html
      )

    assert String.trim(inner) == "oltre 1000€"
  end

  # AA14 — XSS structural pin: the badge label must flow through HEEx
  # auto-escape via `{Budget.label(@cost)}`. Never wrap with `raw/1` or
  # `Phoenix.HTML.raw`.
  test "source contains {Budget.label(@cost)} interpolation and no raw/1 calls" do
    src = File.read!(Path.join(File.cwd!(), "lib/ideajar_web/components/budget_badge.ex"))

    assert src =~ "{Budget.label(@cost)}"
    refute src =~ ~r/\braw\(/
    refute src =~ "Phoenix.HTML.raw"
  end
end
