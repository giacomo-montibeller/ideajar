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
     |> assign(:ideas, Ideas.list_ideas())
     |> assign(:categories, Categories.list_categories())
     |> assign(:form_visible?, false)
     |> assign(:selected_category_ids, MapSet.new())
     |> assign_form()}
  end

  def mount(_params, _session, socket) do
    {:ok, redirect_to_login(socket)}
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_form", _params, %{assigns: %{form_visible?: false}} = socket) do
    {:noreply,
     socket
     |> assign(:form_visible?, true)
     |> assign(:selected_category_ids, MapSet.new())
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
     |> assign(:selected_category_ids, MapSet.new())
     |> assign_form()}
  end

  def handle_event("toggle_category", %{"id" => raw_id}, socket) do
    case Integer.parse(to_string(raw_id)) do
      {id, ""} when id > 0 ->
        set = socket.assigns.selected_category_ids
        new_set = if MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id)
        {:noreply, assign(socket, :selected_category_ids, new_set)}

      _ ->
        # Hostile or malformed phx-value-id: treat as no-op rather than
        # crashing the LV process.
        {:noreply, socket}
    end
  end

  def handle_event("save", %{"idea" => attrs}, socket) do
    attrs_with_categories =
      Map.put(attrs, "category_ids", MapSet.to_list(socket.assigns.selected_category_ids))

    case create_idea_fun(socket).(attrs_with_categories) do
      {:ok, _idea} ->
        {:noreply,
         socket
         |> assign(:ideas, Ideas.list_ideas())
         |> assign(:form_visible?, false)
         |> assign(:selected_category_ids, MapSet.new())
         |> assign_form()
         |> put_flash(:info, "Idea aggiunta")
         |> push_event("ideajar:focus", %{to: "#add-idea-button"})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset, as: "idea", action: :insert))
         |> push_event("ideajar:focus", %{to: focus_first_invalid(changeset)})}

      {:error, _other} ->
        # Persistence layer failed for a non-validation reason (DB locked,
        # disk full, …). We surface a generic flash, keep the form open
        # with the user's input, and leave the LV process alive.
        {:noreply,
         socket
         |> assign(:form, to_form(Idea.changeset(%Idea{}, attrs), as: "idea"))
         |> put_flash(:error, "Salvataggio non riuscito, riprova")}
    end
  end

  defp assign_form(socket) do
    assign(socket, :form, to_form(Idea.changeset(%Idea{}, %{}), as: "idea"))
  end

  # Test seam: tests assign `:create_idea_fun` to inject a deterministic
  # failure without dragging in Mox for a single call site. In production
  # the assign is absent and we fall back to the real context call.
  defp create_idea_fun(socket) do
    socket.assigns[:create_idea_fun] || (&Ideas.create_idea/1)
  end

  # First-invalid focus: priority follows the visual order of the form so
  # screen-reader users land on the topmost field that needs attention.
  # When the error is on :categories, we focus the error region (which is
  # `tabindex="-1"` and `role="alert"`) so the SR announces the message
  # before the user reaches the chips.
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

  # Used by the template to decide whether to render the error region.
  def has_categories_error?(form) do
    Keyword.has_key?(form.source.errors, :categories)
  end

  def categories_error_message(form) do
    case Keyword.get(form.source.errors, :categories) do
      {message, _opts} -> message
      _ -> nil
    end
  end
end
