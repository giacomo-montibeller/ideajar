defmodule IdeajarWeb.Components.BudgetChip do
  @moduledoc """
  Slice-6 chip components for the budget UI.

  `form_chip/1` is the binary single-select form chip used inside the
  add-idea fieldset Budget. It carries `aria-pressed="true|false"` and
  is wired to the LV `toggle_form_budget` event. Single-select
  enforcement happens server-side: assigning `@selected_cost` (an
  `integer | nil`) re-renders only one chip with `pressed?: true`.
  There is no DOM-level coupling between chips.

  `filter_chip/1` (slice 6 step 8) carries a separate ARIA contract
  (`data-budget-filter-state` rather than `aria-pressed`), a separate
  DOM id namespace (`filter-budget-chip-<value>`) and a separate event
  (`toggle_budget_filter`). The two ARIA contracts are deliberately
  encoded as two distinct functions so the type system enforces mutual
  exclusion (S6): a caller cannot pass `state` to `form_chip/1` because
  the attr does not exist there, and `pressed?` cannot reach
  `filter_chip/1` for the same reason.

  `budget_badge/1` (slice 6 step 5) renders a read-only badge on idea
  cards when `idea.estimated_cost != nil` (including `0` / "gratis").

  The chip class string is shared with the other chip families via
  `IdeajarWeb.Components.ChipBase.chip_base_class/0` (R5-2).
  """

  use Phoenix.Component

  import IdeajarWeb.CoreComponents, only: [icon: 1]

  alias Ideajar.Ideas.Budget
  alias IdeajarWeb.Components.ChipBase

  attr :cost, :integer, required: true, values: Budget.values()
  attr :pressed?, :boolean, default: false

  def form_chip(assigns) do
    ~H"""
    <button
      id={"form-budget-chip-#{@cost}"}
      type="button"
      aria-pressed={if @pressed?, do: "true", else: "false"}
      phx-click="toggle_form_budget"
      phx-value-cost={Integer.to_string(@cost)}
      class={[
        ChipBase.chip_base_class(),
        if(@pressed?,
          do: "bg-primary text-primary-content border-primary",
          else: "bg-base-100 text-base-content border-base-300 hover:border-base-content/50"
        )
      ]}
    >
      <.icon :if={@pressed?} name="hero-check" class="size-4" />
      {Budget.label(@cost)}
    </button>
    """
  end

  attr :cost, :integer, required: true, values: Budget.values()
  attr :state, :atom, default: :off, values: [:off, :on]
  attr :tabindex, :integer, default: -1

  @doc """
  Slice 6 step 8 binary 2-state filter chip rendered in the filter row's
  budget sub-block. ARIA contract:

    * `aria-label="<label>"` when off
    * `aria-label="<label> attiva"` when on (BB14 — uniform suffix even
      for the boundary buckets `gratis` and `oltre 1000€`)
    * `data-budget-filter-state="off|on"` (no `aria-pressed` — that
      primitive is reserved for the form-side `form_chip/1`; the two
      contracts are mutually exclusive at the type level — S6)
    * Hero-check icon rendered only when `:on`

  The `tabindex` attr defaults to `-1` so the caller can wire roving
  tabindex semantics (one chip per group is `tabindex="0"`, the rest
  `-1`). The DOM id `filter-budget-chip-<value>` is namespaced so it
  cannot collide with `form-budget-chip-<value>` when the form is open
  and the filter is active simultaneously (BB12, A10).
  """
  def filter_chip(assigns) do
    ~H"""
    <button
      id={"filter-budget-chip-#{@cost}"}
      type="button"
      aria-label={filter_chip_aria_label(@cost, @state)}
      data-budget-filter-state={Atom.to_string(@state)}
      tabindex={@tabindex}
      phx-click="toggle_budget_filter"
      phx-value-cost={Integer.to_string(@cost)}
      class={[ChipBase.chip_base_class(), filter_chip_state_class(@state)]}
    >
      <.icon :if={@state == :on} name="hero-check" class="size-4" />
      {Budget.label(@cost)}
    </button>
    """
  end

  defp filter_chip_aria_label(cost, :off), do: Budget.label(cost)
  defp filter_chip_aria_label(cost, :on), do: "#{Budget.label(cost)} attiva"

  defp filter_chip_state_class(:off),
    do: "bg-base-100 text-base-content border-base-300 hover:border-base-content/50"

  defp filter_chip_state_class(:on),
    do: "bg-success text-success-content border-success"

  attr :cost, :integer, required: true, values: Budget.values()

  @doc """
  Read-only badge rendered inside the idea card to advertise the persisted
  budget bucket. Conditional rendering (only when `idea.estimated_cost`
  is not `nil`) is the caller's responsibility — the badge always renders
  when invoked.

  Use `:if={not is_nil(idea.estimated_cost)}` at the call site rather than
  the truthy `:if={idea.estimated_cost}`. In Elixir `0` is truthy (so the
  truthy form would still render the gratis badge), but the explicit
  nil-check is more robust against future template helper changes that
  might apply Boolean coercion, and it is semantically clearer.

  Visually mirrors `DurationChip.duration_badge/1` (`bg-base-200`) so the
  two badges stack consistently inside the card. The label flows through
  HEEx auto-escape via `{Budget.label(@cost)}`; never wrap with `raw/1`
  (AA14 — XSS regression structural pin in `BudgetChipTest`).
  """
  def budget_badge(assigns) do
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
