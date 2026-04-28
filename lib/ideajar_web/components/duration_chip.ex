defmodule IdeajarWeb.Components.DurationChip do
  @moduledoc """
  Slice-5 chip components for the duration UI.

  `form_chip/1` is the binary single-select form chip used inside the
  add-idea fieldset Durata. It carries `aria-pressed="true|false"` and
  is wired to the LV `toggle_form_duration` event. Single-select
  enforcement happens server-side: assigning `@selected_duration` (an
  `atom | nil`) re-renders only one chip with `pressed?: true`. There is
  no DOM-level coupling between chips.

  Slice 6 will add `filter_chip/1` here with a separate ARIA contract
  (`data-duration-filter-state` rather than `aria-pressed`), a separate
  DOM id namespace (`filter-duration-chip-<atom>`) and a separate event
  (`cycle_duration_filter`). The two ARIA contracts are deliberately
  encoded as two distinct functions so the type system enforces mutual
  exclusion (a caller cannot pass `state` to `form_chip/1` because the
  attr does not exist there — S8).

  The chip class string mirrors `IdeajarWeb.Components.CategoryChip`
  visually but is duplicated by intent (R5-2): the third chip family
  (slice 6) is the trigger to extract a shared `ChipBase` helper.
  """

  use Phoenix.Component

  import IdeajarWeb.CoreComponents, only: [icon: 1]

  alias Ideajar.Ideas.Duration

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
        chip_base_class(),
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

  defp chip_base_class do
    "min-h-11 min-w-11 px-3 py-2 rounded-full border-2 inline-flex items-center gap-1 text-sm"
  end
end
