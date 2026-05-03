defmodule IdeajarWeb.Components.BudgetBadge do
  @moduledoc """
  Slice 9 — extracted from `BudgetChip.budget_badge/1` ahead of the
  `BudgetChip` module deletion (slice 9 step 4). Renders the canonical
  IT label for an idea's `estimated_cost` inside the card. The
  rendering contract is identical to slice 6 BB12 (`data-testid=
  "idea-budget-badge"`, daisyUI badge styling, HEEx auto-escape via
  `{Budget.label(@cost)}` — never wrap with `raw/1`, AA14 XSS pin).

  Lives in the web layer because it is rendering. The integer→IT-label
  mapping itself stays in `Ideajar.Ideas.Budget.label/1` (domain).
  """
  use Phoenix.Component

  alias Ideajar.Ideas.Budget

  @doc """
  Renders the budget badge for an idea card. `@cost` must be a canonical
  budget value from `Budget.values/0`. Visually mirrors
  `DurationChip.duration_badge/1` (`bg-base-200`) so the badges stack
  consistently inside the card.
  """
  def badge(assigns) do
    ~H"""
    <span
      data-testid="idea-budget-badge"
      class="inline-flex items-center px-2 py-1 rounded-full border border-base-300 text-xs text-base-content/80 bg-base-200"
    >
      {Budget.label(@cost)}
    </span>
    """
  end
end
