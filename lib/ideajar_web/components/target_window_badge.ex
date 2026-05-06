defmodule IdeajarWeb.Components.TargetWindowBadge do
  @moduledoc """
  Slice 15 — function component that renders the planned target window
  ("Quando") on an idea card.

  Mirrors the slice-9 `BudgetBadge.badge/1` / slice-5 `DurationChip.duration_badge/1`
  contract: identical daisyUI styling (`bg-base-200`), HEEx auto-escape
  via `{...}` (never `raw/1` — S1 XSS structural pin), and a stable
  `data-testid="idea-target-window-badge"` for integration assertions.

  Conditional render is the caller's responsibility (`:if=...`) AND the
  component's own internal guard: `TargetWindow.from_idea/1` returns nil
  for an idea without a target, in which case the component emits
  nothing. This double-guard mirrors the duration-badge pattern (caller
  uses `:if`, component is also resilient if invoked unconditionally).
  """
  use Phoenix.Component

  alias Ideajar.Ideas.TargetWindow

  attr :idea, :any, required: true

  attr :today, Date,
    default: nil,
    doc:
      "Test seam — when nil, defaults to `Date.utc_today/0`. Production callers omit this attr."

  def badge(assigns) do
    today = assigns[:today] || Date.utc_today()

    case TargetWindow.from_idea(assigns.idea) do
      nil ->
        ~H""

      window ->
        assigns = assign(assigns, :label, TargetWindow.format(window, today))

        ~H"""
        <span
          data-testid="idea-target-window-badge"
          class="inline-flex items-center px-2 py-1 rounded-full border border-base-300 text-xs text-base-content/80 bg-base-200"
        >
          {@label}
        </span>
        """
    end
  end
end
