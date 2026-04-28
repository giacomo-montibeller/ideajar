defmodule IdeajarWeb.Components.CategoryChip do
  @moduledoc """
  Two related but distinct chip components for category UI:

    * `category_chip/1` — slice-3 binary chip used by the add-idea form.
      Carries `aria-pressed="true|false"` + `data-selected="true|false"` +
      a leading hero-check icon when selected. The form chip mutates
      `phx-click="toggle_category"`.

    * `filter_chip/1` — slice-4 tri-state chip used in the filter row
      above the ideas list. Three states: `:off`, `:optional`, `:required`.
      Carries `aria-label` dynamic + `data-filter-state` (no `aria-pressed`,
      because that ARIA primitive is binary). Optional renders the
      hero-check icon; required renders hero-lock-closed (different
      shapes, not different counts of the same icon — more robust than
      icon counts for low-vision users per WCAG 1.4.11). The filter chip
      mutates `phx-click="cycle_filter"`.

  The two components are deliberately **separate public functions** to
  encode the mutual exclusion of their ARIA contracts at the type level
  (a caller cannot accidentally pass `state` to `category_chip/1` because
  the attr does not exist there, and vice versa). DOM ids are also
  hard-coded per component so form-chip and filter-chip for the same
  category cannot collide:

    * `category_chip/1` ⇒ `id="category-chip-<id>"`
    * `filter_chip/1`   ⇒ `id="filter-chip-<id>"`

  `aria_describedby` should be set on each chip (not on the parent
  fieldset) because most screen-reader / browser pairs do not propagate
  a fieldset's `aria-describedby` to its child controls when the chips
  themselves are tabbed onto.
  """

  use Phoenix.Component

  import IdeajarWeb.CoreComponents, only: [icon: 1]

  attr :id, :integer, required: true
  attr :name, :string, required: true
  attr :selected?, :boolean, required: true
  attr :aria_describedby, :string, default: nil

  def category_chip(assigns) do
    ~H"""
    <button
      id={"category-chip-#{@id}"}
      type="button"
      aria-pressed={if @selected?, do: "true", else: "false"}
      aria-describedby={@aria_describedby}
      data-selected={if @selected?, do: "true", else: "false"}
      phx-click="toggle_category"
      phx-value-id={@id}
      class={[
        chip_base_class(),
        if(@selected?,
          do: "bg-primary text-primary-content border-primary",
          else: "bg-base-100 text-base-content border-base-300 hover:border-base-content/50"
        )
      ]}
    >
      <.icon :if={@selected?} name="hero-check" class="size-4" />
      {@name}
    </button>
    """
  end

  attr :id, :integer, required: true
  attr :name, :string, required: true
  attr :state, :atom, required: true, values: [:off, :optional, :required]
  attr :aria_describedby, :string, default: nil

  def filter_chip(assigns) do
    ~H"""
    <button
      id={"filter-chip-#{@id}"}
      type="button"
      aria-label={filter_chip_aria_label(@name, @state)}
      aria-describedby={@aria_describedby}
      data-filter-state={Atom.to_string(@state)}
      phx-click="cycle_filter"
      phx-value-id={@id}
      class={[chip_base_class(), filter_chip_state_class(@state)]}
    >
      <.icon :if={@state == :optional} name="hero-check" class="size-4" />
      <.icon :if={@state == :required} name="hero-lock-closed" class="size-4" />
      {@name}
    </button>
    """
  end

  defp chip_base_class do
    "min-h-11 min-w-11 px-3 py-2 rounded-full border-2 inline-flex items-center gap-1 text-sm"
  end

  defp filter_chip_aria_label(name, :off), do: name
  defp filter_chip_aria_label(name, :optional), do: "#{name} opzionale"
  defp filter_chip_aria_label(name, :required), do: "#{name} obbligatoria"

  defp filter_chip_state_class(:off),
    do: "bg-base-100 text-base-content border-base-300 hover:border-base-content/50"

  defp filter_chip_state_class(:optional),
    do: "bg-success text-success-content border-success"

  defp filter_chip_state_class(:required),
    do: "bg-error text-error-content border-error"
end
