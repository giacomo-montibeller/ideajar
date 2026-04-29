defmodule IdeajarWeb.Components.DurationChip do
  @moduledoc """
  Slice-5 chip components for the duration UI.

  `form_chip/1` is the binary single-select form chip used inside the
  add-idea fieldset Durata. It carries `aria-pressed="true|false"` and
  is wired to the LV `toggle_form_duration` event. Single-select
  enforcement happens server-side: assigning `@selected_duration` (an
  `atom | nil`) re-renders only one chip with `pressed?: true`. There is
  no DOM-level coupling between chips.

  Slice 5 step 6 adds `filter_chip/1` with a separate ARIA contract
  (`data-duration-filter-state` rather than `aria-pressed`), a separate
  DOM id namespace (`filter-duration-chip-<atom>`) and a separate event
  (`toggle_duration_filter`). The two ARIA contracts are deliberately
  encoded as two distinct functions so the type system enforces mutual
  exclusion (a caller cannot pass `state` to `form_chip/1` because the
  attr does not exist there, and `pressed?` cannot reach `filter_chip/1`
  for the same reason — S8). The filter chip is binary (`:off | :on`),
  symmetrical to a 2-state toggle: distinct from `CategoryChip.filter_chip/1`
  which is tri-state (`:off | :optional | :required`).

  The chip class string mirrors `IdeajarWeb.Components.CategoryChip`
  visually but is duplicated by intent (R5-2): the third chip family
  (slice 6) is the trigger to extract a shared `ChipBase` helper.
  """

  use Phoenix.Component

  import IdeajarWeb.CoreComponents, only: [icon: 1]

  alias Ideajar.Ideas.Duration
  alias IdeajarWeb.Components.ChipBase

  attr :duration, :atom, required: true, values: Duration.values()
  attr :pressed?, :boolean, default: false

  def form_chip(assigns) do
    ~H"""
    <button
      id={"form-duration-chip-#{@duration}"}
      type="button"
      aria-pressed={if @pressed?, do: "true", else: "false"}
      phx-click="toggle_form_duration"
      phx-value-duration={Atom.to_string(@duration)}
      class={[
        ChipBase.chip_base_class(),
        if(@pressed?,
          do: "bg-primary text-primary-content border-primary",
          else: "bg-base-100 text-base-content border-base-300 hover:border-base-content/50"
        )
      ]}
    >
      <.icon :if={@pressed?} name="hero-check" class="size-4" />
      {Duration.label(@duration)}
    </button>
    """
  end

  attr :duration, :atom, required: true, values: Duration.values()
  attr :state, :atom, default: :off, values: [:off, :on]
  attr :tabindex, :integer, default: -1

  @doc """
  Slice 5 step 6 binary 2-state filter chip rendered in the filter row's
  durata sub-block. ARIA contract:

    * `aria-label="<label>"` when off
    * `aria-label="<label> attiva"` when on
    * `data-duration-filter-state="off|on"` (no `aria-pressed` — that
      primitive is reserved for the form-side `form_chip/1`; the two
      contracts are mutually exclusive at the type level — S8)
    * Hero-check icon rendered only when `:on`

  The `tabindex` attr defaults to `-1` so the caller can wire roving
  tabindex semantics (one chip per group is `tabindex="0"`, the rest
  `-1`). The DOM id `filter-duration-chip-<atom>` is namespaced so it
  cannot collide with `form-duration-chip-<atom>` when the form is open
  and the filter is active simultaneously (AA18).
  """
  def filter_chip(assigns) do
    ~H"""
    <button
      id={"filter-duration-chip-#{@duration}"}
      type="button"
      aria-label={filter_chip_aria_label(@duration, @state)}
      data-duration-filter-state={Atom.to_string(@state)}
      tabindex={@tabindex}
      phx-click="toggle_duration_filter"
      phx-value-duration={Atom.to_string(@duration)}
      class={[ChipBase.chip_base_class(), filter_chip_state_class(@state)]}
    >
      <.icon :if={@state == :on} name="hero-check" class="size-4" />
      {Duration.label(@duration)}
    </button>
    """
  end

  defp filter_chip_aria_label(duration, :off), do: Duration.label(duration)
  defp filter_chip_aria_label(duration, :on), do: "#{Duration.label(duration)} attiva"

  defp filter_chip_state_class(:off),
    do: "bg-base-100 text-base-content border-base-300 hover:border-base-content/50"

  defp filter_chip_state_class(:on),
    do: "bg-success text-success-content border-success"

  attr :duration, :atom, required: true, values: Duration.values()

  @doc """
  Read-only badge rendered inside the idea card to advertise the persisted
  duration. Conditional rendering (only when `idea.duration != nil`) is
  the caller's responsibility — the badge always renders when invoked.

  Subtly distinct from category badges (`bg-base-200` instead of the
  default surface) for visual hierarchy. The label flows through HEEx
  auto-escape via `{Duration.label(@duration)}`; never wrap with `raw/1`
  (AA14 — XSS regression structural pin in `DurationChipTest`).
  """
  def duration_badge(assigns) do
    ~H"""
    <span
      data-testid="idea-duration-badge"
      class="inline-flex items-center px-2 py-1 rounded-full border border-base-300 text-xs text-base-content/80 bg-base-200"
    >
      {Duration.label(@duration)}
    </span>
    """
  end
end
