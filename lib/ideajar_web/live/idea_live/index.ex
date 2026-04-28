defmodule IdeajarWeb.IdeaLive.Index do
  @moduledoc """
  Workspace home: lists ideas (newest first) and lets the couple add a new
  one through an inline collapsible form. Slice 3 adds multi-category
  tagging via toggleable chips.

  Mount enforces an authenticated session as defense-in-depth on top of the
  `IdeajarWeb.RequireAuth` plug — the plug already gates the HTTP request,
  but a future refactor that moved this LiveView under a different scope
  could lose that guarantee silently. The mount keeps the redirect behaviour
  byte-equivalent to the plug (`/login?return_to=%2F`).

  Focus management is a server-driven concern: every time we want to move
  focus we emit a `phx:ideajar:focus` event with a CSS selector and a small
  listener in `assets/js/app.js` does the actual `.focus()` call. That keeps
  the behaviour testable (`assert_push_event/3`) and avoids HTML
  `autofocus`, which doesn't survive LiveView re-renders.

  Categories live outside the `@form` because chips are not HTML form
  inputs — `@selected_category_ids` is a `MapSet` updated by the
  `toggle_category` handler, and the save handler injects `category_ids`
  into the form data before calling `Ideas.create_idea/1`.
  """

  use IdeajarWeb, :live_view

  import IdeajarWeb.Components.CategoryChip

  alias Ideajar.Categories
  alias Ideajar.Ideas
  alias Ideajar.Ideas.Idea

  @impl Phoenix.LiveView
  def mount(_params, %{"authenticated" => true}, socket) do
    {:ok,
     socket
     |> assign(:filter_state, %{})
     |> assign(:last_filter_action, nil)
     |> assign(:categories, Categories.list_categories())
     |> assign(:form_visible?, false)
     |> reset_categories()
     |> assign_form()
     |> reload_ideas()}
  end

  def mount(_params, _session, socket) do
    {:ok, redirect_to_login(socket)}
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_form", _params, %{assigns: %{form_visible?: false}} = socket) do
    {:noreply,
     socket
     |> assign(:form_visible?, true)
     |> reset_categories()
     |> assign_form()
     |> push_event("ideajar:focus", %{to: "#idea-title"})}
  end

  def handle_event("toggle_form", _params, %{assigns: %{form_visible?: true}} = socket) do
    # Idempotent: a second click on the open form is a no-op so we do not
    # wipe what the user has already typed.
    {:noreply, socket}
  end

  def handle_event("close_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:form_visible?, false)
     |> reset_categories()
     |> assign_form()}
  end

  def handle_event("toggle_category", %{"id" => raw_id}, socket) when is_binary(raw_id) do
    case Integer.parse(raw_id) do
      {id, ""} when id > 0 ->
        set = socket.assigns.selected_category_ids

        new_set =
          if MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id)

        {:noreply, assign(socket, :selected_category_ids, new_set)}

      _ ->
        {:noreply, socket}
    end
  end

  # Catchall for hostile or malformed phx-value-id (non-string types).
  def handle_event("toggle_category", _params, socket), do: {:noreply, socket}

  def handle_event("cycle_filter", %{"id" => raw_id}, socket) when is_binary(raw_id) do
    case parse_known_category_id(raw_id, socket.assigns.categories) do
      {:ok, id} ->
        category_name = category_name_by_id(id, socket.assigns.categories)
        new_state = cycle_state(socket.assigns.filter_state, id)
        new_action_prefix = action_prefix(new_state, id, category_name)

        {:noreply,
         socket
         |> assign(:filter_state, new_state)
         |> assign(:last_filter_action, new_action_prefix)
         |> reload_ideas()}

      :error ->
        {:noreply, socket}
    end
  end

  # Catchall for cycle_filter with malformed/missing params (defense-in-depth
  # against DevTools tampering). Hostile id values land here as well.
  def handle_event("cycle_filter", _params, socket), do: {:noreply, socket}

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:filter_state, %{})
     |> assign(:last_filter_action, "Filtri rimossi, ")
     |> reload_ideas()}
  end

  def handle_event("save", %{"idea" => attrs}, socket) do
    attrs_with_categories =
      Map.put(attrs, "category_ids", MapSet.to_list(socket.assigns.selected_category_ids))

    socket
    |> create_idea_fun()
    |> apply([attrs_with_categories])
    |> handle_save_result(socket, attrs)
  end

  # Test seam: tests assign `:create_idea_fun` to inject a deterministic
  # failure without dragging in Mox for a single call site. In production
  # the assign is absent and we fall back to the real context call.
  defp create_idea_fun(socket) do
    socket.assigns[:create_idea_fun] || (&Ideas.create_idea/1)
  end

  defp handle_save_result({:ok, _idea}, socket, _attrs) do
    {:noreply,
     socket
     |> assign(:form_visible?, false)
     |> assign(:last_filter_action, nil)
     |> reset_categories()
     |> assign_form()
     |> reload_ideas()
     |> put_flash(:info, "Idea aggiunta")
     |> push_event("ideajar:focus", %{to: "#add-idea-button"})}
  end

  defp handle_save_result({:error, %Ecto.Changeset{} = changeset}, socket, _attrs) do
    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: "idea", action: :insert))
     |> push_event("ideajar:focus", %{to: focus_first_invalid(changeset)})}
  end

  defp handle_save_result({:error, _other}, socket, attrs) do
    # Persistence layer failed for a non-validation reason (DB locked,
    # disk full, …). Surface a generic flash, keep the form open with
    # the user's input, leave the LV process alive.
    {:noreply,
     socket
     |> assign(:form, to_form(Idea.changeset(%Idea{}, attrs), as: "idea"))
     |> put_flash(:error, "Salvataggio non riuscito, riprova")}
  end

  defp reset_categories(socket), do: assign(socket, :selected_category_ids, MapSet.new())

  # Re-loads the ideas list from the context using the filter opts derived
  # from `@filter_state`. Called on mount + after every event that may
  # change either the filter or the underlying ideas (cycle, clear, save).
  defp reload_ideas(socket) do
    opts = derive_filter_opts(socket.assigns.filter_state)
    assign(socket, :ideas, Ideas.list_ideas(opts))
  end

  defp derive_filter_opts(filter_state) do
    Enum.reduce(filter_state, [required: [], optional: []], fn
      {id, :required}, acc -> Keyword.update!(acc, :required, &[id | &1])
      {id, :optional}, acc -> Keyword.update!(acc, :optional, &[id | &1])
    end)
  end

  @doc """
  Returns true when at least one category in @filter_state is in
  :optional or :required state. Used by the template to decide whether
  to render the `Mostra tutte` reset button.
  """
  def filter_active?(filter_state), do: filter_state != %{}

  defp category_name_by_id(id, categories) do
    Enum.find_value(categories, fn cat -> if cat.id == id, do: cat.name end)
  end

  # Builds the live-region prefix that describes the action just applied
  # to the chip with `id`. Read directly from the post-cycle state.
  defp action_prefix(filter_state, id, name) do
    case Map.get(filter_state, id) do
      :optional -> "#{name} opzionale, "
      :required -> "#{name} obbligatoria, "
      nil -> "#{name} rimossa, "
    end
  end

  # Tri-state cycle: off → optional → required → off.
  defp cycle_state(map, id) do
    case Map.get(map, id) do
      nil -> Map.put(map, id, :optional)
      :optional -> Map.put(map, id, :required)
      :required -> Map.delete(map, id)
    end
  end

  # Membership-gated parse: accepts only string-encoded positive integers
  # whose value matches a category id present in `@categories` (the
  # snapshot loaded at mount). Defense-in-depth against DevTools id
  # tampering.
  defp parse_known_category_id(raw, categories) do
    with {id, ""} <- Integer.parse(raw),
         true <- id > 0,
         true <- Enum.any?(categories, &(&1.id == id)) do
      {:ok, id}
    else
      _ -> :error
    end
  end

  defp assign_form(socket) do
    assign(socket, :form, to_form(Idea.changeset(%Idea{}, %{}), as: "idea"))
  end

  # First-invalid focus: priority follows the visual order of the form so
  # screen-reader users land on the topmost field that needs attention.
  # When the error is on :categories, we focus the error region (which is
  # `tabindex="-1"`) so the SR announces the message before the user
  # reaches the chips.
  defp focus_first_invalid(%Ecto.Changeset{errors: errors}) do
    cond do
      Keyword.has_key?(errors, :title) -> "#idea-title"
      Keyword.has_key?(errors, :categories) -> "#idea-categories-error"
      Keyword.has_key?(errors, :url) -> "#idea-url"
      true -> "#idea-description"
    end
  end

  defp redirect_to_login(socket) do
    Phoenix.LiveView.redirect(socket, to: "/login?return_to=%2F")
  end

  # Used by the template to decide whether to render the error region
  # and what message to show. Public so HEEx can call them via the
  # implicit module dispatch; they read only the form.source.errors
  # keyword list and surface the field-level state.
  def has_categories_error?(form) do
    Keyword.has_key?(form.source.errors, :categories)
  end

  def categories_error_message(form) do
    case Keyword.get(form.source.errors, :categories) do
      {message, _opts} -> message
      _ -> nil
    end
  end

  @doc """
  Builds the space-separated list of ids that each chip should expose as
  `aria-describedby`. The help text is always associated; on error, the
  error region id is appended so screen readers announce both when the
  chip receives focus.
  """
  def chip_describedby(form) do
    if has_categories_error?(form) do
      "idea-categories-help idea-categories-error"
    else
      "idea-categories-help"
    end
  end
end
