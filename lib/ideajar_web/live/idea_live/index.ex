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
  import IdeajarWeb.Components.LocationSearchInput
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
  alias IdeajarWeb.Components.LocationBadge

  # Slice 7b step 8 — slider step indices ↔ km mapping. Indices 0-6
  # are the only valid values; index 0 means "filter inactive" (NULL-
  # coord ideas pass through); index 6 means "no upper cap" with
  # NULL-coord ideas STILL excluded (the only difference between 0 and
  # 6 is the NULL treatment, DD4).
  @distance_steps %{
    0 => nil,
    1 => 5,
    2 => 25,
    3 => 50,
    4 => 200,
    5 => 500,
    6 => 1_000_000
  }

  @distance_labels %{
    0 => "Disattivo",
    1 => "fino a 5 km",
    2 => "fino a 25 km",
    3 => "fino a 50 km",
    4 => "fino a 200 km",
    5 => "fino a 500 km",
    6 => "oltre 1000 km"
  }

  @impl Phoenix.LiveView
  def mount(_params, %{"authenticated" => true}, socket) do
    {:ok,
     socket
     |> assign(:filter_state, %{})
     |> assign(:duration_filter, MapSet.new())
     |> assign(:cost_filter, nil)
     |> assign(:categories, Categories.list_categories())
     |> assign(:form_visible?, false)
     |> reset_categories()
     |> reset_duration()
     |> reset_budget()
     |> reset_location()
     |> reset_location_search()
     |> reset_user_location()
     |> assign(:max_distance_index, 0)
     |> assign(:text_search_query, "")
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
     |> reset_location()
     |> reset_location_search()
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
     |> reset_location()
     |> reset_location_search()
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

  # Slice 7a iter2 — text input `phx-change` for the location name and
  # search trigger. Accepts any binary (including the empty string —
  # clearing the input is legal at this layer; the schema validator
  # drops empty-after-trim to nil and surfaces "Posizione incompleta"
  # only when coords are set without a name).
  #
  # Behaviour:
  #
  #   * trimmed query has < 3 chars: silent. `@selected_location_name`
  #     is updated, search results are cleared, state goes back to
  #     `:idle` so no dropdown is rendered.
  #
  #   * trimmed query has ≥ 3 chars: synchronous call to
  #     `Ideajar.Geocoding.search/1`. On success the LV assigns the
  #     results and flips state to `:results` (or `:empty` if the
  #     list comes back empty). On `:service_unavailable` we land
  #     back at `:idle` with no results and put a flash error so
  #     the user knows the service is down.
  #
  #   * Decision C1 — if the user types after a previous successful
  #     selection (`@selected_lat` not nil), lat/lng are also cleared.
  #     A divergent name + stale coords would otherwise produce a
  #     state-(c) submit with the wrong coords for the typed name.
  def handle_event("update_location_name", params, socket) do
    case extract_location_name(params) do
      {:ok, name} -> apply_location_name_change(socket, name)
      :error -> {:noreply, socket}
    end
  end

  # Slice 7a iter2 — selecting a result from the search dropdown.
  # Defensive parse of lat/lng (string → float) plus range validation
  # ([-90, 90] / [-180, 180]). Hostile or out-of-range payloads no-op.
  # On success: populate the 3 location assigns, close the dropdown,
  # and clear the result list.
  def handle_event(
        "select_location",
        %{"name" => name, "lat" => lat_raw, "lng" => lng_raw},
        socket
      )
      when is_binary(name) and is_binary(lat_raw) and is_binary(lng_raw) do
    with {lat, ""} <- Float.parse(lat_raw),
         {lng, ""} <- Float.parse(lng_raw),
         true <- lat >= -90.0 and lat <= 90.0,
         true <- lng >= -180.0 and lng <= 180.0 do
      {:noreply,
       socket
       |> assign(:selected_location_name, name)
       |> assign(:selected_lat, lat)
       |> assign(:selected_lng, lng)
       |> reset_location_search()}
    else
      _ -> {:noreply, socket}
    end
  end

  # Catchall for hostile or malformed `select_location` payloads:
  # missing keys, non-binary values, out-of-range coords.
  def handle_event("select_location", _params, socket), do: {:noreply, socket}

  # Slice 7a iter2 — `phx-click-away` dismiss for the search dropdown.
  # Closes the dropdown without touching the 3 location assigns: a user
  # who has typed a name but not picked a result keeps their typed name
  # (state b on submit).
  def handle_event("dismiss_location_search", _params, socket) do
    {:noreply, reset_location_search(socket)}
  end

  # Slice 7a step 4 — clears the full location triplet at once. Wired to
  # the conditional "Rimuovi posizione" button (rendered when at least one
  # of the 3 assigns is set). Symmetrical with `clear_filters` for the
  # filter row but scoped to the form's location fieldset.
  def handle_event("remove_location", _params, socket) do
    {:noreply,
     socket
     |> reset_location()
     |> reset_location_search()}
  end

  def handle_event("cycle_filter", %{"id" => raw_id}, socket) when is_binary(raw_id) do
    case parse_known_category_id(raw_id, socket.assigns.categories) do
      {:ok, id} ->
        new_state = cycle_state(socket.assigns.filter_state, id)

        {:noreply,
         socket
         |> assign(:filter_state, new_state)
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

        {:noreply,
         socket
         |> assign(:duration_filter, new_set)
         |> reload_ideas()}

      :error ->
        {:noreply, socket}
    end
  end

  # Catchall for hostile or malformed phx-value-duration payloads on the
  # filter row (non-string types, missing key). Pinned by S1/S2 hostile
  # uniform list in `index_test.exs` (slice 5 step 6 RED #16).
  def handle_event("toggle_duration_filter", _params, socket), do: {:noreply, socket}

  # Slice 6 step 8: binary 2-state budget filter (single-select). Click on
  # the currently-active bucket toggles back to nil; click on a different
  # bucket swaps the single selection (F14 cycle, F15 swap). Membership-gated
  # parse via `Budget.parse/1`; hostile payloads (out-of-whitelist integers,
  # non-numeric strings, non-string types) land in the catchall as no-ops (S1).
  def handle_event("toggle_budget_filter", %{"cost" => raw}, socket)
      when is_binary(raw) do
    case Budget.parse(raw) do
      {:ok, val} ->
        new_value = if socket.assigns.cost_filter == val, do: nil, else: val

        {:noreply,
         socket
         |> assign(:cost_filter, new_value)
         |> reload_ideas()}

      :error ->
        {:noreply, socket}
    end
  end

  # Catchall for hostile or malformed phx-value-cost payloads on the filter
  # row (non-string types, missing key). Pinned by S1 hostile uniform list.
  def handle_event("toggle_budget_filter", _params, socket), do: {:noreply, socket}

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:filter_state, %{})
     |> assign(:duration_filter, MapSet.new())
     |> assign(:cost_filter, nil)
     |> reset_user_location()
     |> reset_distance_filter()
     |> assign(:text_search_query, "")
     |> reload_ideas()}
  end

  # Slice 8 step 3 — text-search filter handler. Multi-shape extractor
  # (DD-S8-6, parallel slice 7b filter search bug fix): accepts the
  # bare `%{"q" => v}` shape used by `render_hook/3` AND the form-shape
  # `%{"filter" => %{"text_search" => v}}` shipped by the real browser
  # when phx-change fires on a `name="filter[text_search]"` input.
  # Server-side oversize guard at 200 bytes (S2): client `maxlength`
  # attribute is UX-only and devtools can bypass it.
  def handle_event("update_text_search", params, socket) do
    case extract_text_search_query(params) do
      {:ok, q} -> {:noreply, socket |> assign(:text_search_query, q) |> reload_ideas()}
      :error -> {:noreply, socket}
    end
  end

  # Slice 8 step 3 — scoped reset for the text-search axis.
  def handle_event("remove_text_search", _params, socket) do
    {:noreply, socket |> assign(:text_search_query, "") |> reload_ideas()}
  end

  # Slice 7b step 6 — Geolocation hook success path. The hook in
  # `assets/js/hooks/geolocation.js` resolves `getCurrentPosition` and
  # pushEvents the coords here. We defensively parse + range-check both
  # values and only commit the assigns when the pair is valid; any
  # hostile shape (S1) routes to the catchall no-op below.
  def handle_event("set_user_location", %{"lat" => raw_lat, "lng" => raw_lng}, socket) do
    with {:ok, lat} <- parse_coord(raw_lat, -90.0, 90.0),
         {:ok, lng} <- parse_coord(raw_lng, -180.0, 180.0) do
      {:noreply,
       socket
       |> assign(:user_lat, lat)
       |> assign(:user_lng, lng)
       |> assign(:user_location_name, "La mia posizione")}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_user_location", _params, socket), do: {:noreply, socket}

  # Slice 7b step 6 — Geolocation hook denial path. The hook surfaces
  # one of four documented reason strings (DD7); the LV maps them to
  # the canonical IT flash strings. Any other reason value falls
  # through to the generic message — we don't trust arbitrary input
  # to round-trip into the UI.
  def handle_event("user_location_denied", %{"reason" => reason}, socket)
      when is_binary(reason) do
    flash_msg =
      case reason do
        "permission_denied" -> "Permesso di geolocalizzazione negato"
        _ -> "Posizione non disponibile, riprova"
      end

    {:noreply, put_flash(socket, :error, flash_msg)}
  end

  def handle_event("user_location_denied", _params, socket), do: {:noreply, socket}

  # Slice 7b step 7 — search-driven reference point. Mirrors slice 7a
  # `update_location_name` but lives on the filter side: assigns
  # `@user_location_search_results` / `@user_location_search_state`.
  # The text input does not pre-fill `@user_location_name` — the name
  # is committed only on `select_user_location` (whereas the form's
  # `update_location_name` populates `@selected_location_name` while
  # typing, since the form submits the typed name verbatim).
  #
  # Slice 7b step 7-bis (real-browser bug fix, parallel slice 7a iter2
  # 868f3fc): `phx-change` on a bracketed `name="filter[…]"` input
  # ships params as `%{"filter" => %{"user_location_name" => v}}` in
  # the actual browser, while `render_hook/3` test calls use the bare
  # `%{"name" => v}` shape. We accept both via `extract_user_location_name/1`
  # so production typing fires the search.
  def handle_event("update_user_location_name", params, socket) do
    case extract_user_location_name(params) do
      {:ok, name} -> apply_user_location_search(socket, name)
      :error -> {:noreply, socket}
    end
  end

  # Slice 7b step 7 — picking a result from the filter dropdown.
  # Defensive parse uniform with `select_location` (slice 7a iter2).
  # On success: commits 3 user_* assigns + closes the dropdown,
  # leaves `@max_distance_index` untouched (DD19 swap clause).
  def handle_event(
        "select_user_location",
        %{"name" => name, "lat" => raw_lat, "lng" => raw_lng},
        socket
      )
      when is_binary(name) do
    with {:ok, lat} <- parse_coord(raw_lat, -90.0, 90.0),
         {:ok, lng} <- parse_coord(raw_lng, -180.0, 180.0) do
      {:noreply,
       socket
       |> assign(:user_lat, lat)
       |> assign(:user_lng, lng)
       |> assign(:user_location_name, name)
       |> reset_user_location_search()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("select_user_location", _params, socket), do: {:noreply, socket}

  # Slice 7b step 7 — `phx-click-away` for the filter dropdown. Same
  # contract as slice 7a `dismiss_location_search` but on the filter
  # assigns: closes the dropdown, leaves user_* assigns alone (a user
  # who typed but didn't pick keeps no reference point).
  def handle_event("dismiss_user_location_search", _params, socket) do
    {:noreply, reset_user_location_search(socket)}
  end

  # Slice 7b step 8 — slider drag → server-side index commit. `phx-
  # change` on the HTML5 range input ships the value as a string. We
  # parse to an integer in [0, 6] and reject anything else (DD9
  # hostile uniform list: "abc", "-1", "7", "3.5", missing key).
  def handle_event("update_max_distance", %{"value" => raw}, socket) when is_binary(raw) do
    case Integer.parse(raw) do
      {n, ""} when n >= 0 and n <= 6 ->
        {:noreply, socket |> assign(:max_distance_index, n) |> reload_ideas()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("update_max_distance", _params, socket), do: {:noreply, socket}

  # Slice 7b step 9 — explicit reset of the reference point. Cascades
  # to slider 0 (DD19) so a user who removes the anchor doesn't end up
  # with an active km cap and no point to measure from. Idempotent on
  # already-empty state.
  def handle_event("remove_user_location", _params, socket) do
    {:noreply,
     socket
     |> reset_user_location()
     |> reset_distance_filter()
     |> reload_ideas()}
  end

  # Slice 7b step 9 — slider-only reset. Leaves the reference point
  # in place so the user can dial the radius back from any value to
  # 0 without having to re-enter the anchor.
  def handle_event("remove_distance_filter", _params, socket) do
    {:noreply, socket |> reset_distance_filter() |> reload_ideas()}
  end

  def handle_event("save", %{"idea" => attrs}, socket) do
    attrs_with_categories =
      Map.put(attrs, "category_ids", MapSet.to_list(socket.assigns.selected_category_ids))

    attrs_with_duration =
      maybe_inject_duration(attrs_with_categories, socket.assigns.selected_duration, attrs)

    attrs_with_budget =
      maybe_inject_budget(attrs_with_duration, socket.assigns.selected_cost)

    attrs_with_location =
      attrs_with_budget
      |> maybe_inject_location_name(socket.assigns.selected_location_name)
      |> maybe_inject_lat(socket.assigns.selected_lat)
      |> maybe_inject_lng(socket.assigns.selected_lng)

    socket
    |> create_idea_fun()
    |> apply([attrs_with_location])
    |> handle_save_result(socket, attrs)
  end

  # `phx-change` on a form-bound input sends the full form params shape
  # (`%{"idea" => %{"location_name" => "..."}}`), while direct
  # `render_hook/render_change` test dispatches use the bare `%{"name" => "..."}`
  # shape. We accept both so production typing works AND the slice-7a-step-4
  # hostile-uniform-list tests keep passing. Hostile/missing payloads return
  # `:error` and trigger the no-op catchall.
  defp extract_location_name(%{"idea" => %{"location_name" => name}}) when is_binary(name),
    do: {:ok, name}

  defp extract_location_name(%{"name" => name}) when is_binary(name), do: {:ok, name}
  defp extract_location_name(_), do: :error

  defp apply_location_name_change(socket, name) do
    socket =
      socket
      |> assign(:selected_location_name, name)
      |> maybe_clear_coords_on_text_change()

    case String.trim(name) do
      trimmed when byte_size(trimmed) < 3 ->
        {:noreply, reset_location_search(socket)}

      trimmed ->
        case Ideajar.Geocoding.search(trimmed) do
          {:ok, []} ->
            {:noreply,
             socket
             |> assign(:location_search_results, [])
             |> assign(:location_search_state, :empty)}

          {:ok, results} ->
            {:noreply,
             socket
             |> assign(:location_search_results, results)
             |> assign(:location_search_state, :results)}

          {:error, :service_unavailable} ->
            {:noreply,
             socket
             |> reset_location_search()
             |> put_flash(:error, "Ricerca non disponibile, riprova")}
        end
    end
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

  # Slice 7a step 4 — symmetric to `maybe_inject_duration/3` and
  # `maybe_inject_budget/2`. The form's three location assigns are the
  # source of truth: when any is set we override the matching `"idea[..]"`
  # key in the form params (the text input also posts `idea[location_name]`
  # via its `name` attribute, so on submit the assign and the form param
  # carry the same value — the assign wins for consistency with the chip
  # families). When the assign is `nil` we leave whatever the form params
  # carried so the cross-field validator in the schema can surface the
  # canonical "Posizione incompleta" error on hostile submits.
  defp maybe_inject_location_name(params, nil), do: params

  defp maybe_inject_location_name(params, name) when is_binary(name),
    do: Map.put(params, "location_name", name)

  defp maybe_inject_lat(params, nil), do: params

  defp maybe_inject_lat(params, lat) when is_number(lat),
    do: Map.put(params, "lat", lat)

  defp maybe_inject_lng(params, nil), do: params

  defp maybe_inject_lng(params, lng) when is_number(lng),
    do: Map.put(params, "lng", lng)

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
     |> reset_categories()
     |> reset_duration()
     |> reset_budget()
     |> reset_location()
     |> reset_location_search()
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

  # Slice 7a step 4 (CC11): the form's location triplet
  # `(@selected_location_name, @selected_lat, @selected_lng)` lives outside
  # `@form` for the same reason as the chip-derived fields — in iter2 the
  # search dropdown's `select_location` handler populates all 3 at once
  # and the text input feeds `@selected_location_name` (and clears
  # lat/lng on text change after a select, decision C1) via the
  # `update_location_name` `phx-change` handler. `reset_location/1` runs
  # in the same lifecycle slots as `reset_categories/1` /
  # `reset_duration/1` / `reset_budget/1`: mount, toggle_form open,
  # close_form, and save success.
  defp reset_location(socket) do
    socket
    |> assign(:selected_location_name, nil)
    |> assign(:selected_lat, nil)
    |> assign(:selected_lng, nil)
  end

  # Slice 7a iter2 — search dropdown state. Two assigns:
  #
  #   * `@location_search_results :: [Ideajar.Geocoding.result()]` — the
  #     list rendered as clickable buttons in the dropdown.
  #
  #   * `@location_search_state :: :idle | :searching | :empty | :results`
  #     drives the dropdown visibility and contents:
  #     - `:idle` → no dropdown rendered;
  #     - `:searching` → dropdown shows "Cerco…" placeholder
  #       (reserved for a future async-search switch — the synchronous
  #       handler today never observes this state, but the template
  #       contract is in place for forward compatibility);
  #     - `:empty` → dropdown shows "Nessun risultato";
  #     - `:results` → dropdown lists `@location_search_results`.
  #
  # Reset on the same lifecycle slots as `reset_location/1` plus on
  # `dismiss_location_search` (click-away) and `select_location` (after
  # a successful pick).
  defp reset_location_search(socket) do
    socket
    |> assign(:location_search_results, [])
    |> assign(:location_search_state, :idle)
  end

  # Slice 7b step 6 — distance filter reference point. Three assigns:
  #
  #   * `@user_lat :: float | nil` — latitude of the reference point
  #   * `@user_lng :: float | nil` — longitude of the reference point
  #   * `@user_location_name :: String.t() | nil` — display label
  #
  # `LiveView-session only` (DD11): no localStorage, no DB; refresh
  # reverts to nil. Set via either the geolocation hook
  # (`set_user_location`, label "La mia posizione") or the filter
  # search dropdown (`select_user_location`, label from the chosen
  # geocoding result). `remove_user_location` resets all three plus
  # cascades the slider to 0.
  defp reset_user_location(socket) do
    socket
    |> assign(:user_lat, nil)
    |> assign(:user_lng, nil)
    |> assign(:user_location_name, nil)
    |> reset_user_location_search()
  end

  # Slice 8 step 3 (DD-S8-6) — multi-shape extractor for the filter
  # text-search input. Browser ships params as
  # `%{"filter" => %{"text_search" => v}}` (form-bracketed name attr),
  # `render_hook/3` synthetic calls use `%{"q" => v}`. Both must work.
  # Hostile bypass: oversize > 200 bytes → :error (S2 guard).
  defp extract_text_search_query(%{"filter" => %{"text_search" => q}})
       when is_binary(q) and byte_size(q) <= 200,
       do: {:ok, q}

  defp extract_text_search_query(%{"q" => q}) when is_binary(q) and byte_size(q) <= 200,
    do: {:ok, q}

  defp extract_text_search_query(_), do: :error

  # Slice 7b step 8 — slider state reset (DD10). Used by `clear_filters`,
  # `remove_distance_filter` (step 9), and `remove_user_location` (step 9
  # cascade). Keeping the helper centralised guarantees a single source
  # of truth for "filter inactive".
  defp reset_distance_filter(socket), do: assign(socket, :max_distance_index, 0)

  # Slice 7b step 7 — search dropdown state for the filter side. Two
  # assigns parallel to the slice-7a-iter2 form pattern but scoped to
  # the filter's reference-point picker.
  defp reset_user_location_search(socket) do
    socket
    |> assign(:user_location_search_results, [])
    |> assign(:user_location_search_state, :idle)
    |> assign(:user_location_search_query, "")
  end

  # Multi-shape extractor for the filter search input. Mirrors slice 7a
  # `extract_location_name/1` but on the filter assigns. The browser
  # form-shape uses the bracketed `name="filter[user_location_name]"`,
  # the test synthetic shape uses the bare `%{"name" => v}`, and any
  # other shape is hostile and routes to no-op.
  defp extract_user_location_name(%{"filter" => %{"user_location_name" => name}})
       when is_binary(name),
       do: {:ok, name}

  defp extract_user_location_name(%{"name" => name}) when is_binary(name), do: {:ok, name}
  defp extract_user_location_name(_), do: :error

  defp apply_user_location_search(socket, name) do
    # Always mirror the typed text into `@user_location_search_query` so
    # re-renders don't reset the input's `value` attribute back to "".
    socket = assign(socket, :user_location_search_query, name)

    case String.trim(name) do
      trimmed when byte_size(trimmed) < 3 ->
        {:noreply,
         socket
         |> assign(:user_location_search_results, [])
         |> assign(:user_location_search_state, :idle)}

      trimmed ->
        case Ideajar.Geocoding.search(trimmed) do
          {:ok, []} ->
            {:noreply,
             socket
             |> assign(:user_location_search_results, [])
             |> assign(:user_location_search_state, :empty)}

          {:ok, results} ->
            {:noreply,
             socket
             |> assign(:user_location_search_results, results)
             |> assign(:user_location_search_state, :results)}

          {:error, :service_unavailable} ->
            {:noreply,
             socket
             |> reset_user_location_search()
             |> put_flash(:error, "Ricerca non disponibile, riprova")}
        end
    end
  end

  # Slice 7b step 6 — defensive coordinate parser shared between the
  # geolocation hook handler and the filter search-select handler.
  # Accepts either a raw float (geolocation) or a binary (search
  # dropdown's phx-value-* params). Out-of-range values map to
  # `:error` so the calling `with` clause routes to the no-op.
  defp parse_coord(value, lo, hi) when is_number(value) do
    if value >= lo and value <= hi, do: {:ok, value * 1.0}, else: :error
  end

  defp parse_coord(value, lo, hi) when is_binary(value) do
    case Float.parse(value) do
      {n, ""} when n >= lo and n <= hi -> {:ok, n}
      _ -> :error
    end
  end

  defp parse_coord(_, _, _), do: :error

  # Decision C1 — typing in the text input after a previous successful
  # select must drop the picked lat/lng. Otherwise the form would post
  # state-(c) name+coords with a name that no longer matches the coords.
  defp maybe_clear_coords_on_text_change(%{assigns: %{selected_lat: nil}} = socket),
    do: socket

  defp maybe_clear_coords_on_text_change(socket) do
    socket
    |> assign(:selected_lat, nil)
    |> assign(:selected_lng, nil)
  end

  # Re-loads the ideas list from the context using the filter opts derived
  # from `@filter_state`, `@duration_filter` and `@cost_filter`. Called on
  # mount + after every event that may change either the filter or the
  # underlying ideas (cycle, clear, save, toggle_duration_filter,
  # toggle_budget_filter).
  defp reload_ideas(socket) do
    assign(socket, :ideas, Ideas.list_ideas(derive_filter_opts(socket)))
  end

  # Slice 7b step 8 (DD12 refactor) — collapsed `derive_filter_opts/3`
  # to `/1` taking the socket directly. Reading every assign at the
  # call site keeps the signature stable as more filter axes are
  # added (slice 8 text search would push to /5+ with the old shape).
  defp derive_filter_opts(socket) do
    %{
      assigns: %{
        filter_state: filter_state,
        duration_filter: duration_filter,
        cost_filter: cost_filter,
        max_distance_index: max_distance_index,
        user_lat: user_lat,
        user_lng: user_lng,
        text_search_query: text_search_query
      }
    } = socket

    filter_state
    |> Enum.reduce([required: [], optional: []], fn
      {id, :required}, acc -> Keyword.update!(acc, :required, &[id | &1])
      {id, :optional}, acc -> Keyword.update!(acc, :optional, &[id | &1])
    end)
    |> Keyword.put(:durations, MapSet.to_list(duration_filter))
    |> Keyword.put(:max_cost, cost_filter)
    |> Keyword.put(:max_distance_km, distance_max_km(max_distance_index))
    |> Keyword.put(:ref_lat, user_lat)
    |> Keyword.put(:ref_lng, user_lng)
    |> Keyword.put(:text_search, text_search_query)
  end

  @doc """
  Returns true when at least one filter axis is active. Used by the
  template to decide whether to render the `Mostra tutte` reset button
  and the empty-filter message.

  Arity history: slice 4 `/1`, slice 5 `/2`, slice 6 `/3`, slice 7b `/5`,
  slice 8 `/1` socket-based (DD-S8-7). The `/1` shape pattern-matches
  the assigns map at the call site so adding a new axis is a body change,
  not a signature change. Behavior-preserving refactor; the text-search
  axis was added to the body in slice 8 step 5.
  """
  def filter_active?(%{
        filter_state: filter_state,
        duration_filter: duration_filter,
        cost_filter: cost_filter,
        max_distance_index: max_distance_index,
        user_lat: user_lat,
        text_search_query: text_search_query
      }) do
    filter_state != %{} or MapSet.size(duration_filter) > 0 or not is_nil(cost_filter) or
      max_distance_index > 0 or not is_nil(user_lat) or text_search_query != ""
  end

  @doc """
  Slice 7b step 8 — slider helpers. `distance_max_km/1` resolves the
  index to the kilometre cap that `Filter.apply_post/2` consumes;
  `distance_label/1` is the source of `aria-valuetext` and the visible
  caption beneath the slider.
  """
  def distance_max_km(index) when index in 0..6, do: Map.fetch!(@distance_steps, index)
  def distance_max_km(_), do: nil

  def distance_label(index) when index in 0..6, do: Map.fetch!(@distance_labels, index)
  def distance_label(_), do: "Disattivo"

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
