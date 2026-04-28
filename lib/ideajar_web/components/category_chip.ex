defmodule IdeajarWeb.Components.CategoryChip do
  @moduledoc """
  Toggleable category chip. Renders a `<button>` with `aria-pressed`,
  `data-selected`, and a leading checkmark icon when selected — three
  cues that are independent of each other so the selected/deselected
  visual contract stays color-blind safe (WCAG 1.4.11).
  """

  use Phoenix.Component

  import IdeajarWeb.CoreComponents, only: [icon: 1]

  attr :id, :integer, required: true
  attr :name, :string, required: true
  attr :selected?, :boolean, required: true

  def category_chip(assigns) do
    ~H"""
    <button
      id={"category-chip-#{@id}"}
      type="button"
      aria-pressed={if @selected?, do: "true", else: "false"}
      data-selected={if @selected?, do: "true", else: "false"}
      phx-click="toggle_category"
      phx-value-id={@id}
      class={[
        "min-h-11 min-w-11 px-3 py-2 rounded-full border-2 inline-flex items-center gap-1 text-sm",
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
end
