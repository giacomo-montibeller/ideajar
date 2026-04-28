defmodule IdeajarWeb.Components.CategoryChipTest do
  @moduledoc """
  Unit tests for the new `filter_chip/1` tri-state component (slice 4).
  Slice-3 binary `category_chip/1` remains covered by integration tests in
  the LiveView suite — we deliberately avoid duplicating that coverage here.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias IdeajarWeb.Components.CategoryChip

  defp render_filter_chip(assigns) do
    render_component(&CategoryChip.filter_chip/1, assigns)
  end

  describe "filter_chip/1 — :off" do
    test "renders data-filter-state=off, aria-label=name, no icons" do
      html = render_filter_chip(%{id: 2, name: "mare", state: :off})

      assert html =~ ~s(id="filter-chip-2")
      assert html =~ ~s(data-filter-state="off")
      assert html =~ ~s(aria-label="mare")
      assert html =~ ~s(phx-click="cycle_filter")
      assert html =~ ~s(phx-value-id="2")
      refute html =~ ~s(aria-pressed)
      refute html =~ "hero-check"
      refute html =~ "hero-lock-closed"
    end
  end

  describe "filter_chip/1 — :optional" do
    test "renders data-filter-state=optional, aria-label='<name> opzionale', hero-check icon" do
      html = render_filter_chip(%{id: 2, name: "mare", state: :optional})

      assert html =~ ~s(data-filter-state="optional")
      assert html =~ ~s(aria-label="mare opzionale")
      assert html =~ "hero-check"
      refute html =~ "hero-lock-closed"
    end
  end

  describe "filter_chip/1 — :required" do
    test "renders data-filter-state=required, aria-label='<name> obbligatoria', hero-lock-closed icon" do
      html = render_filter_chip(%{id: 2, name: "mare", state: :required})

      assert html =~ ~s(data-filter-state="required")
      assert html =~ ~s(aria-label="mare obbligatoria")
      assert html =~ "hero-lock-closed"
      refute html =~ "hero-check"
    end
  end

  describe "filter_chip/1 — hit area + a11y" do
    test "carries min-h-11 min-w-11 (≥44 CSS px target size)" do
      html = render_filter_chip(%{id: 1, name: "passeggiata", state: :off})

      assert html =~ "min-h-11"
      assert html =~ "min-w-11"
    end

    test "DOM id is exactly 'filter-chip-<id>' (A8.1 pin)" do
      html = render_filter_chip(%{id: 7, name: "cinema", state: :off})

      assert html =~ ~s(id="filter-chip-7")
    end

    test "type='button' (no implicit form submit)" do
      html = render_filter_chip(%{id: 2, name: "mare", state: :off})

      assert html =~ ~s(type="button")
    end
  end
end
