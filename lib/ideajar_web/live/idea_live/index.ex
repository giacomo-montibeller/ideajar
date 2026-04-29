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
  # DurationChip carries its own `filter_chip/1` (slice 5 step 6) which would
  # collide with `CategoryChip.filter_chip/1`. We import only the form-side
  # helpers and call the duration filter chip via the module-qualified form
  # `<DurationChip.filter_chip … />` in the template.
  import IdeajarWeb.Components.DurationChip, only: [form_chip: 1, duration_badge: 1]

  alias Ideajar.Categories
  alias Ideajar.Ideas
  alias Ideajar.Ideas.Budget
  alias Ideajar.Ideas.Duration
  alias Ideajar.Ideas.Idea
  # BudgetChip.form_chip/1 collides on name with DurationChip.form_chip/1
  # (both are imported above), so we leave it module-qualified in the
  # template via `<BudgetChip.form_chip … />` (BB12 — same pattern as
  # DurationChip.filter_chip).
  alias IdeajarWeb.Components.BudgetChip
  alias IdeajarWeb.Components.DurationChip

  @impl Phoenix.LiveView
  def mount(_params, %{"authenticated" => true}, socket) do
    {:ok,
     socket
     |> assign(:filter_state, %{})
     |> assign(:duration_filter, MapSet.new())
     # Live-region split (slice 5 step 6 / AA20):
     #
     #   * `@last_filter_action_prefix` — action-only part such as
     #     `"weekend attiva, "` or `"Filtri rimossi, "`. `nil` until the
     #     user first interacts with the filter row.
     #   * `@last_filter_action_suffix` — compound-state suffix such as
     #     `", filtri categoria attivi"`. Empty string when the *other*
     #     filter group is empty (no compound).
     #
     # The template interleaves prefix + count + suffix at render time
     # because the count is derived from `length(@ideas)` after each
     # event. See `compound_suffix/3`.
     |> assign(:last_filter_action_prefix, nil)
     |> assign(:last_filter_action_suffix, "")
     |> assign(:categories, Categories.list_categories())
     |> assign(:form_visible?, false)
     |> reset_categories()
     |> reset_duration()
     |> reset_budget()
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
     |> reset_duration()
     |> reset_budget()
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
     |> reset_duration()
     |> reset_budget()
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

  def handle_event("toggle_form_duration", %{"duration" => raw}, socket)
      when is_binary(raw) do
    case Duration.parse(raw) do
      {:ok, atom} ->
        new_value =
          if socket.assigns.selected_duration == atom, do: nil, else: atom

        {:noreply, assign(socket, :selected_duration, new_value)}

      :error ->
        {:noreply, socket}
    end
  end

  # Catchall for hostile or malformed phx-value-duration payloads (non-string
  # types or missing key).
  def handle_event("toggle_form_duration", _params, socket), do: {:noreply, socket}

  # Slice 6 step 4 — binary single-select budget chip on the form.
  # Membership-gated parse via `Budget.parse/1`; hostile payloads
  # (non-string values, out-of-whitelist integers, non-numeric strings)
  # land in the catchall as no-ops (S2). A click on the currently-pressed
  # chip toggles back to nil; a click on a different chip swaps the
  # single selection.
  def handle_event("toggle_form_budget", %{"cost" => raw}, socket)
      when is_binary(raw) do
    case Budget.parse(raw) do
      {:ok, val} ->
        new_value =
          if socket.assigns.selected_cost == val, do: nil, else: val

        {:noreply, assign(socket, :selected_cost, new_value)}

      :error ->
        {:noreply, socket}
    end
  end

  # Catchall for hostile or malformed phx-value-cost payloads (non-string
  # types or missing key). Pinned by S2 hostile uniform list.
  def handle_event("toggle_form_budget", _params, socket), do: {:noreply, socket}

  def handle_event("cycle_filter", %{"id" => raw_id}, socket) when is_binary(raw_id) do
    case parse_known_category_id(raw_id, socket.assigns.categories) do
      {:ok, id} ->
        category_name = category_name_by_id(id, socket.assigns.categories)
        new_state = cycle_state(socket.assigns.filter_state, id)
        new_action_prefix = action_prefix(new_state, id, category_name)
        new_suffix = compound_suffix(new_state, socket.assigns.duration_filter, :category)

        {:noreply,
         socket
         |> assign(:filter_state, new_state)
         |> assign(:last_filter_action_prefix, new_action_prefix)
         |> assign(:last_filter_action_suffix, new_suffix)
         |> reload_ideas()}

      :error ->
        {:noreply, socket}
    end
  end

  # Catchall for cycle_filter with malformed/missing params (defense-in-depth
  # against DevTools tampering). Hostile id values land here as well.
  def handle_event("cycle_filter", _params, socket), do: {:noreply, socket}

  # Slice 5 step 6: binary 2-state duration filter. Membership-gated parse
  # via `Duration.parse/1`; hostile payloads (non-string values, unknown
  # atoms, casing mismatches) land in the catchall as no-ops.
  def handle_event("toggle_duration_filter", %{"duration" => raw}, socket)
      when is_binary(raw) do
    case Duration.parse(raw) do
      {:ok, atom} ->
        current = socket.assigns.duration_filter

        new_set =
          if MapSet.member?(current, atom),
            do: MapSet.delete(current, atom),
            else: MapSet.put(current, atom)

        new_prefix = duration_action_prefix(new_set, atom)
        new_suffix = compound_suffix(socket.assigns.filter_state, new_set, :duration)

        {:noreply,
         socket
         |> assign(:duration_filter, new_set)
         |> assign(:last_filter_action_prefix, new_prefix)
         |> assign(:last_filter_action_suffix, new_suffix)
         |> reload_ideas()}

      :error ->
        {:noreply, socket}
    end
  end

  # Catchall for hostile or malformed phx-value-duration payloads on the
  # filter row (non-string types, missing key). Pinned by S1/S2 hostile
  # uniform list in `index_test.exs` (slice 5 step 6 RED #16).
  def handle_event("toggle_duration_filter", _params, socket), do: {:noreply, socket}

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:filter_state, %{})
     |> assign(:duration_filter, MapSet.new())
     |> assign(:last_filter_action_prefix, "Filtri rimossi, ")
     |> assign(:last_filter_action_suffix, "")
     |> reload_ideas()}
  end

  def handle_event("save", %{"idea" => attrs}, socket) do
    attrs_with_categories =
      Map.put(attrs, "category_ids", MapSet.to_list(socket.assigns.selected_category_ids))

    attrs_with_duration =
      maybe_inject_duration(attrs_with_categories, socket.assigns.selected_duration, attrs)

    attrs_with_budget =
      maybe_inject_budget(attrs_with_duration, socket.assigns.selected_cost)

    socket
    |> create_idea_fun()
    |> apply([attrs_with_budget])
    |> handle_save_result(socket, attrs)
  end

  # Slice 5: inject the chip-derived duration into the form params.
  #
  #   * `@selected_duration` is an atom → stringify and override any
  #     `"duration"` key present in `attrs` (the chip is the source of truth).
  #   * `@selected_duration` is `nil` → preserve whatever the form params
  #     already had under `"duration"`. This is what surfaces the hostile-
  #     duration error path: a tampered payload (`"duration" => "<script>"`)
  #     reaches the changeset and produces `"Durata non valida"`.
  defp maybe_inject_duration(params, nil, _attrs), do: params

  defp maybe_inject_duration(params, atom, _attrs) when is_atom(atom),
    do: Map.put(params, "duration", Atom.to_string(atom))

  # Slice 6 — symmetric to `maybe_inject_duration/3`:
  #
  #   * `@selected_cost` is an integer → stringify and override any
  #     `"estimated_cost"` key present in `attrs` (chip is source of truth).
  #     Note: `0` is a valid bucket (gratis); we override on every non-nil
  #     value, including `0`.
  #   * `@selected_cost` is `nil` → preserve whatever the form params
  #     already had under `"estimated_cost"`. This is what surfaces the
  #     hostile-cost error path (S3): a tampered payload (e.g.
  #     `"estimated_cost" => "175"` or `"abc"`) reaches the changeset
  #     and produces `"Budget non valido"`.
  defp maybe_inject_budget(params, nil), do: params

  defp maybe_inject_budget(params, value) when is_integer(value),
    do: Map.put(params, "estimated_cost", Integer.to_string(value))

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
     |> assign(:last_filter_action_prefix, nil)
     |> assign(:last_filter_action_suffix, "")
     |> reset_categories()
     |> reset_duration()
     |> reset_budget()
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

  # Slice 5 (AA5): `@selected_duration :: atom | nil`. Reset on mount, on form
  # open, on close_form, and on save success — symmetrical with `reset_categories/1`.
  defp reset_duration(socket), do: assign(socket, :selected_duration, nil)

  # Slice 6 (BB6): `@selected_cost :: integer | nil`. Reset on mount, on form
  # open, on close_form, and on save success — symmetrical with
  # `reset_categories/1` and `reset_duration/1`. `nil` means "no chip
  # selected"; `0` is a valid bucket (gratis) and is NOT the reset value.
  defp reset_budget(socket), do: assign(socket, :selected_cost, nil)

  # Re-loads the ideas list from the context using the filter opts derived
  # from `@filter_state` and `@duration_filter`. Called on mount + after
  # every event that may change either the filter or the underlying ideas
  # (cycle, clear, save, toggle_duration_filter).
  defp reload_ideas(socket) do
    opts =
      derive_filter_opts(
        socket.assigns.filter_state,
        socket.assigns.duration_filter
      )

    assign(socket, :ideas, Ideas.list_ideas(opts))
  end

  defp derive_filter_opts(filter_state, duration_filter) do
    filter_state
    |> Enum.reduce([required: [], optional: []], fn
      {id, :required}, acc -> Keyword.update!(acc, :required, &[id | &1])
      {id, :optional}, acc -> Keyword.update!(acc, :optional, &[id | &1])
    end)
    |> Keyword.put(:durations, MapSet.to_list(duration_filter))
  end

  @doc """
  Returns true when at least one filter is active across categories
  (`@filter_state`) or durations (`@duration_filter`). Used by the
  template to decide whether to render the `Mostra tutte` reset button
  and the empty-filter message.

  Slice 5 step 6 extends this from `/1` (categoria-only) to `/2` (categoria
  + durata) so the empty-filter affordance fires even when the only
  active filter is on duration. Slice 5 step 7 adds combined-filter
  scenarios on top of this.
  """
  def filter_active?(filter_state, duration_filter) do
    filter_state != %{} or MapSet.size(duration_filter) > 0
  end

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

  # Slice 5 step 6 / AA9 — duration live-region prefix:
  #
  #   * `<label> attiva, ` when the toggle put `atom` into `new_set`
  #   * `<label> rimossa, ` when the toggle removed `atom` from `new_set`
  #
  # Uses the IT label (not the atom form) so the SR announcement reads
  # `poche ore attiva, …` instead of `poche_ore attiva, …`.
  defp duration_action_prefix(new_set, atom) do
    label = Duration.label(atom)

    if MapSet.member?(new_set, atom),
      do: "#{label} attiva, ",
      else: "#{label} rimossa, "
  end

  # Slice 5 step 6 / AA20 — compound live-region suffix.
  #
  # When the action was on one filter group (categoria or durata) and the
  # OTHER group has at least one active filter, append a short suffix
  # advertising that compound state. Returns `""` when the other group is
  # empty (single-axis filter — no compound to announce).
  #
  # Four cases:
  #
  #   * `:category` action, durations active   → `, filtri durata attivi`
  #   * `:category` action, durations empty    → `""`
  #   * `:duration` action, categories active  → `, filtri categoria attivi`
  #   * `:duration` action, categories empty   → `""`
  #
  # `clear_filters` does NOT route through this helper because its prefix
  # `Filtri rimossi, ` is an absolute statement: both groups are empty
  # by construction, so the suffix is always `""` and the helper would be
  # a no-op anyway.
  defp compound_suffix(_filter_state, duration_filter, :category) do
    if MapSet.size(duration_filter) > 0, do: ", filtri durata attivi", else: ""
  end

  defp compound_suffix(filter_state, _duration_filter, :duration) do
    if filter_state != %{}, do: ", filtri categoria attivi", else: ""
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
  Slice 5: surface the canonical "Durata non valida" error under the Durata
  fieldset when the changeset reports a `:duration` cast failure (S4).
  """
  def has_duration_error?(form) do
    Keyword.has_key?(form.source.errors, :duration)
  end

  def duration_error_message(form) do
    case Keyword.get(form.source.errors, :duration) do
      {message, _opts} -> message
      _ -> nil
    end
  end

  @doc """
  Slice 6: surface the canonical "Budget non valido" error under the
  Budget fieldset when the changeset reports an `:estimated_cost` cast
  failure (S3) or a whitelist violation. Symmetrical with
  `has_duration_error?/1`.
  """
  def has_estimated_cost_error?(form) do
    Keyword.has_key?(form.source.errors, :estimated_cost)
  end

  def estimated_cost_error_message(form) do
    case Keyword.get(form.source.errors, :estimated_cost) do
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
