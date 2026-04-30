defmodule IdeajarWeb.Components.LocationBadge do
  @moduledoc """
  Slice 7a — read-only badge for `idea.location_name`.

  Renders `📍 <name>` on idea cards when `location_name` is set (with or
  without coords). State (b) name-only and state (c) name+coords both
  surface the badge; coords are not displayed (slice 7b distance filter
  will use them).

  Conditional rendering (only when `idea.location_name` is not `nil`)
  is the caller's responsibility — the badge always renders when invoked.
  Use `:if={not is_nil(idea.location_name)}` at the call site (parallel
  to slice 6 step 5 `BudgetChip.budget_badge/1`); the explicit nil-check
  is more robust against future template helper changes that might apply
  Boolean coercion.

  Visually mirrors `BudgetChip.budget_badge/1` (`bg-base-200`, `text-xs`)
  so the two badges stack consistently inside the card. The label flows
  through HEEx auto-escape via `{@name}`; never wrap with `raw/1`
  (AA14 — XSS regression structural pin in `LocationBadgeTest`).
  """

  use Phoenix.Component

  attr :name, :string, required: true

  def location_badge(assigns) do
    ~H"""
    <span
      data-testid="idea-location-badge"
      class="inline-flex items-center gap-1 px-2 py-1 rounded-full border border-base-300 text-xs text-base-content/80 bg-base-200"
    >
      📍 {@name}
    </span>
    """
  end
end
