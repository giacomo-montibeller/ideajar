defmodule IdeajarWeb.Components.LocationSearchInput do
  @moduledoc """
  Slice-7b step-1 (DD1) shared search-dropdown input. Encapsulates the
  slice-7a-iter2 pattern of a text input wired to a forward-geocoding
  search whose result list renders inside a `phx-click-away` listbox
  underneath the input.

  Both the slice-7a form fieldset Posizione and the slice-7b filter
  sub-block Distanza render this component with their own caller-
  parametrised `phx-*` event names so the LiveView can keep distinct
  assigns (`@selected_*` for the form, `@user_*` for the filter) while
  sharing the markup and a11y contract.

  The component does not own the result data: the caller passes
  `search_results`, `search_state`, and `name_value` as assigns. The
  caller also owns the `Rimuovi …` button that resets its own state —
  the two sub-blocks have different reset semantics (form clears 3
  `@selected_*`, filter clears 3 `@user_*` plus cascades the slider).
  """
  use Phoenix.Component

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :name_value, :string, default: ""
  attr :placeholder, :string, default: ""
  attr :search_results, :list, required: true

  attr :search_state, :atom,
    required: true,
    values: [:idle, :searching, :empty, :results]

  attr :on_change_event, :string, required: true
  attr :on_select_event, :string, required: true
  attr :on_dismiss_event, :string, required: true

  def location_search_input(assigns) do
    ~H"""
    <div phx-click-away={@on_dismiss_event} class="relative">
      <input
        type="text"
        id={@id}
        name={@name}
        value={@name_value}
        placeholder={@placeholder}
        phx-change={@on_change_event}
        phx-debounce="300"
        maxlength="200"
        autocomplete="off"
        class="input w-full"
      />
      <ul
        :if={@search_state != :idle}
        class="absolute z-10 mt-1 w-full max-h-64 overflow-auto rounded-box border border-base-300 bg-base-100 shadow-lg"
        role="listbox"
      >
        <li
          :if={@search_state == :searching}
          class="px-3 py-2 text-sm text-base-content/70"
        >
          Cerco…
        </li>
        <li
          :if={@search_state == :empty}
          class="px-3 py-2 text-sm text-base-content/70"
        >
          Nessun risultato
        </li>
        <li
          :for={result <- @search_results}
          class="border-t border-base-300 first:border-t-0"
        >
          <button
            type="button"
            phx-click={@on_select_event}
            phx-value-name={result.display_name}
            phx-value-lat={result.lat}
            phx-value-lng={result.lng}
            class="block w-full text-left px-3 py-2 text-sm hover:bg-base-200"
          >
            {result.display_name}
          </button>
        </li>
      </ul>
    </div>
    """
  end
end
