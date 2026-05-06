defmodule IdeajarWeb.Components.CategoryChipTest do
  @moduledoc """
  Unit tests for the `category_chip/1` (slice 3, binary form chip) and
  `filter_chip/1` (slice 4, tri-state filter chip) components.

  Direct unit coverage was added when slice 14b introduced the leading
  emoji prefix on both chip families: the chip-level rendering contract
  is the right place to pin which substring goes where (icon vs emoji
  vs name), rather than relying on LiveView integration tests that do
  not assert exact substring ordering.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias IdeajarWeb.Components.CategoryChip

  defp render_category_chip(assigns) do
    render_component(&CategoryChip.category_chip/1, assigns)
  end

  defp render_filter_chip(assigns) do
    render_component(&CategoryChip.filter_chip/1, assigns)
  end

  describe "category_chip/1 — emoji + name rendering" do
    test "renders the emoji immediately before the name (separated by a single space)" do
      html =
        render_category_chip(%{id: 2, name: "mare", emoji: "🏖️", selected?: false})

      assert html =~ "🏖️ mare"
    end

    test "preserves aria-pressed=false when not selected" do
      html =
        render_category_chip(%{id: 2, name: "mare", emoji: "🏖️", selected?: false})

      assert html =~ ~s(aria-pressed="false")
      assert html =~ ~s(data-selected="false")
      refute html =~ "hero-check"
    end

    test "preserves aria-pressed=true and renders hero-check before the emoji when selected" do
      html =
        render_category_chip(%{id: 2, name: "mare", emoji: "🏖️", selected?: true})

      assert html =~ ~s(aria-pressed="true")
      assert html =~ ~s(data-selected="true")
      assert html =~ "hero-check"

      # Order: icon → emoji → name. The hero-check svg comes first, then
      # the literal "🏖️ mare". Assert positionally so future template
      # changes that split icon/emoji/name across containers are caught.
      [check_pos, emoji_pos, name_pos] =
        Enum.map(["hero-check", "🏖️", "mare"], &index_of!(html, &1))

      assert check_pos < emoji_pos
      assert emoji_pos < name_pos
    end

    test "wires phx-click=toggle_category and phx-value-id from the id attr" do
      html =
        render_category_chip(%{id: 7, name: "cinema", emoji: "🎬", selected?: false})

      assert html =~ ~s(id="category-chip-7")
      assert html =~ ~s(phx-click="toggle_category")
      assert html =~ ~s(phx-value-id="7")
      assert html =~ ~s(type="button")
    end
  end

  defp index_of!(haystack, needle) do
    case :binary.match(haystack, needle) do
      {pos, _} -> pos
      :nomatch -> flunk("substring #{inspect(needle)} not found in rendered HTML")
    end
  end

  describe "filter_chip/1 — :off" do
    test "renders data-filter-state=off, aria-label=name, no icons" do
      html = render_filter_chip(%{id: 2, name: "mare", emoji: "🏖️", state: :off})

      assert html =~ ~s(id="filter-chip-2")
      assert html =~ ~s(data-filter-state="off")
      assert html =~ ~s(aria-label="mare")
      assert html =~ ~s(phx-click="cycle_filter")
      assert html =~ ~s(phx-value-id="2")
      refute html =~ ~s(aria-pressed)
      refute html =~ "hero-check"
      refute html =~ "hero-lock-closed"
    end

    test "renders the emoji immediately before the name" do
      html = render_filter_chip(%{id: 2, name: "mare", emoji: "🏖️", state: :off})

      assert html =~ "🏖️ mare"
    end
  end

  describe "filter_chip/1 — :optional" do
    test "renders data-filter-state=optional, aria-label='<name> opzionale', hero-check icon" do
      html = render_filter_chip(%{id: 2, name: "mare", emoji: "🏖️", state: :optional})

      assert html =~ ~s(data-filter-state="optional")
      assert html =~ ~s(aria-label="mare opzionale")
      assert html =~ "hero-check"
      refute html =~ "hero-lock-closed"
    end

    test "renders icon followed by '<emoji> <name>'" do
      html = render_filter_chip(%{id: 2, name: "mare", emoji: "🏖️", state: :optional})

      # Look for the contiguous "🏖️ mare" substring rather than the
      # standalone "mare" — the latter also appears in aria-label
      # ("mare opzionale") which is rendered before the visible label.
      assert index_of!(html, "hero-check") < index_of!(html, "🏖️ mare")
    end
  end

  describe "filter_chip/1 — :required" do
    test "renders data-filter-state=required, aria-label='<name> obbligatoria', hero-lock-closed icon" do
      html = render_filter_chip(%{id: 2, name: "mare", emoji: "🏖️", state: :required})

      assert html =~ ~s(data-filter-state="required")
      assert html =~ ~s(aria-label="mare obbligatoria")
      assert html =~ "hero-lock-closed"
      refute html =~ "hero-check"
    end

    test "renders icon followed by '<emoji> <name>'" do
      html = render_filter_chip(%{id: 2, name: "mare", emoji: "🏖️", state: :required})

      assert index_of!(html, "hero-lock-closed") < index_of!(html, "🏖️ mare")
    end
  end

  describe "filter_chip/1 — aria-label is emoji-free across all states" do
    # The screen-reader contract is name + state suffix only — never the
    # emoji. Reading "🏖️ mare opzionale" out loud creates noise; the
    # emoji is purely a visual prefix on the visible label.
    for state <- [:off, :optional, :required] do
      test "state=#{inspect(state)} aria-label does not contain the emoji" do
        html =
          render_filter_chip(%{
            id: 2,
            name: "mare",
            emoji: "🏖️",
            state: unquote(state)
          })

        [_full, aria] = Regex.run(~r/aria-label="([^"]*)"/, html)
        refute aria =~ "🏖️", "aria-label leaked the emoji: #{inspect(aria)}"
      end
    end
  end

  describe "filter_chip/1 — hit area + a11y" do
    test "carries min-h-11 min-w-11 (≥44 CSS px target size)" do
      html =
        render_filter_chip(%{id: 1, name: "passeggiata", emoji: "🚶", state: :off})

      assert html =~ "min-h-11"
      assert html =~ "min-w-11"
    end

    test "DOM id is exactly 'filter-chip-<id>' (A8.1 pin)" do
      html = render_filter_chip(%{id: 7, name: "cinema", emoji: "🎬", state: :off})

      assert html =~ ~s(id="filter-chip-7")
    end

    test "type='button' (no implicit form submit)" do
      html = render_filter_chip(%{id: 2, name: "mare", emoji: "🏖️", state: :off})

      assert html =~ ~s(type="button")
    end
  end
end
