defmodule IdeajarWeb.Components.BudgetChipTest do
  @moduledoc """
  Unit tests for the slice-6 `BudgetChip.form_chip/1` binary chip used by
  the add-idea form fieldset Budget. The chip carries
  `aria-pressed="true|false"` (single-select enforced server-side via
  `@selected_cost :: integer | nil`).

  Slice 6 step 8 will add `filter_chip/1` here with a separate ARIA
  contract. Type-level mutual exclusion (S6) is pinned in this file by
  asserting `form_chip/1` does NOT accept attr `state`.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias IdeajarWeb.Components.BudgetChip

  defp render_form_chip(assigns) do
    render_component(&BudgetChip.form_chip/1, assigns)
  end

  describe "form_chip/1 — pressed?: false" do
    test "renders aria-pressed=false, no icon, hard-coded id and phx-* wiring" do
      html = render_form_chip(%{cost: 100, pressed?: false})

      assert html =~ ~s(id="form-budget-chip-100")
      assert html =~ ~s(aria-pressed="false")
      assert html =~ ~s(phx-click="toggle_form_budget")
      assert html =~ ~s(phx-value-cost="100")
      assert html =~ ~s(type="button")
      refute html =~ "hero-check"
    end

    test "carries min-h-11 min-w-11 (>=44 CSS px target size) via ChipBase" do
      html = render_form_chip(%{cost: 100, pressed?: false})

      assert html =~ "min-h-11"
      assert html =~ "min-w-11"
    end
  end

  describe "form_chip/1 — pressed?: true" do
    test "renders aria-pressed=true and the hero-check icon" do
      html = render_form_chip(%{cost: 100, pressed?: true})

      assert html =~ ~s(aria-pressed="true")
      assert html =~ "hero-check"
    end
  end

  describe "form_chip/1 — IT labels for canonical buckets" do
    test "cost: 100 renders 'fino a 100€'" do
      html = render_form_chip(%{cost: 100, pressed?: false})
      assert html =~ "fino a 100€"
    end

    test "cost: 0 renders 'gratis' (not the integer form)" do
      html = render_form_chip(%{cost: 0, pressed?: false})

      assert html =~ "gratis"
      # The integer 0 legitimately appears in the DOM id (form-budget-chip-0)
      # and the phx-value-cost attribute; we scope the negative assertion to
      # the rendered text content between > and <.
      refute Regex.match?(~r{>\s*0\s*<}, html)
    end

    test "cost: 1000 renders 'oltre 1000€'" do
      html = render_form_chip(%{cost: 1000, pressed?: false})
      assert html =~ "oltre 1000€"
    end
  end

  describe "form_chip/1 — type-level mutual exclusion (S6)" do
    test "does NOT declare attr :state (only :cost and :pressed?)" do
      # Phoenix.Component stores attr declarations in a module attribute that
      # isn't available at runtime once compiled, but we can still verify the
      # public surface at the source level: assert the module declares only
      # `attr :cost` and `attr :pressed?` and never `attr :state` for
      # `form_chip/1`.
      src =
        File.read!(Path.join(File.cwd!(), "lib/ideajar_web/components/budget_chip.ex"))

      assert src =~ ~r/attr :cost,/
      assert src =~ ~r/attr :pressed\?,/
      refute src =~ ~r/attr :state,/

      # Behavioural pin: rendering does not leak any filter-side ARIA
      # contract attributes (the slice-6 step 8 filter_chip will use a
      # `data-budget-filter-state` instead of `aria-pressed`).
      html = render_form_chip(%{cost: 100, pressed?: false})

      refute html =~ "data-filter-state"
      refute html =~ "data-budget-filter-state"
    end
  end
end
