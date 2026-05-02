defmodule IdeajarWeb.Components.LocationSearchInputTest do
  @moduledoc """
  Unit tests for the slice-7b step-1 `IdeajarWeb.Components.LocationSearchInput`
  shared component (DD1 pre-feature refactor). The component encapsulates
  the slice-7a-iter2 search-dropdown pattern (text input + click-away +
  listbox of result buttons) so that both the slice-7a form fieldset and
  the slice-7b filter sub-block can reuse it with their own event names.

  These tests cover the rendering contract per `search_state` value plus
  the wiring of caller-parametrised `phx-*` event names. The integration
  with the LiveView (form fieldset Posizione) is covered by the slice-7a
  regression tests in `IdeajarWeb.IdeaLive.IndexTest`.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias IdeajarWeb.Components.LocationSearchInput

  defp default_assigns(overrides) do
    Map.merge(
      %{
        id: "test-input",
        name: "test[input]",
        name_value: "",
        placeholder: "Cerca…",
        search_results: [],
        search_state: :idle,
        on_change_event: "update_x",
        on_select_event: "select_x",
        on_dismiss_event: "dismiss_x"
      },
      overrides
    )
  end

  defp render_input(assigns),
    do: render_component(&LocationSearchInput.location_search_input/1, assigns)

  describe "state: :idle" do
    test "renders the text input but no listbox" do
      html = render_input(default_assigns(%{search_state: :idle}))

      assert html =~ ~s(id="test-input")
      assert html =~ ~s(name="test[input]")
      refute html =~ ~s(role="listbox")
      refute html =~ "Cerco…"
      refute html =~ "Nessun risultato"
    end
  end

  describe "state: :searching" do
    test "renders a listbox with the searching item" do
      html = render_input(default_assigns(%{search_state: :searching}))

      assert html =~ ~s(role="listbox")
      assert html =~ "Cerco…"
    end
  end

  describe "state: :empty" do
    test "renders a listbox with the no-results item" do
      html = render_input(default_assigns(%{search_state: :empty}))

      assert html =~ ~s(role="listbox")
      assert html =~ "Nessun risultato"
    end
  end

  describe "state: :results" do
    test "renders one button per result with phx-click + phx-value-* wired" do
      results = [
        %{display_name: "Sirolo, AN", lat: "43.5", lng: "13.6"},
        %{display_name: "Roma, RM", lat: "41.9", lng: "12.5"}
      ]

      html =
        render_input(
          default_assigns(%{
            search_state: :results,
            search_results: results,
            on_select_event: "select_x"
          })
        )

      assert html =~ ~s(role="listbox")
      assert html =~ "Sirolo, AN"
      assert html =~ "Roma, RM"
      assert html =~ ~s(phx-click="select_x")
      assert html =~ ~s(phx-value-name="Sirolo, AN")
      assert html =~ ~s(phx-value-lat="43.5")
      assert html =~ ~s(phx-value-lng="13.6")
      assert html =~ ~s(phx-value-name="Roma, RM")
    end
  end

  describe "event-name parametrisation" do
    test "phx-click-away wires to on_dismiss_event" do
      html = render_input(default_assigns(%{on_dismiss_event: "dismiss_user_location_search"}))

      assert html =~ ~s(phx-click-away="dismiss_user_location_search")
    end

    test "phx-change wires to on_change_event" do
      html = render_input(default_assigns(%{on_change_event: "update_user_location_name"}))

      assert html =~ ~s(phx-change="update_user_location_name")
    end

    test "phx-click on result wires to on_select_event" do
      html =
        render_input(
          default_assigns(%{
            search_state: :results,
            search_results: [%{display_name: "X", lat: "0", lng: "0"}],
            on_select_event: "select_user_location"
          })
        )

      assert html =~ ~s(phx-click="select_user_location")
    end
  end

  describe "input attributes" do
    test "honours id, name, name_value, placeholder" do
      html =
        render_input(
          default_assigns(%{
            id: "filter-location-search",
            name: "filter_location",
            name_value: "Sirolo",
            placeholder: "Cerca punto di partenza"
          })
        )

      assert html =~ ~s(id="filter-location-search")
      assert html =~ ~s(name="filter_location")
      assert html =~ ~s(value="Sirolo")
      assert html =~ ~s(placeholder="Cerca punto di partenza")
    end
  end
end
