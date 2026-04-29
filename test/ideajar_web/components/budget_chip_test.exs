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
    test "does NOT declare attr :state in the form_chip attr block" do
      # Phoenix.Component attrs bind to the next component definition. We scope
      # the source-level negative assertion to the attr block immediately
      # preceding `def form_chip(assigns)` so it doesn't catch the slice-6
      # step 8 `filter_chip/1` attr block (which legitimately declares
      # `attr :state`).
      src =
        File.read!(Path.join(File.cwd!(), "lib/ideajar_web/components/budget_chip.ex"))

      {form_chip_pos, _} = :binary.match(src, "def form_chip(assigns)")
      preceding = binary_part(src, 0, form_chip_pos)

      last_def_pos =
        case :binary.matches(preceding, "def ") do
          [] -> 0
          matches -> matches |> List.last() |> elem(0)
        end

      form_chip_attrs_block =
        binary_part(preceding, last_def_pos, byte_size(preceding) - last_def_pos)

      assert form_chip_attrs_block =~ ~r/attr :cost,/
      assert form_chip_attrs_block =~ ~r/attr :pressed\?,/
      refute form_chip_attrs_block =~ ~r/attr :state,/

      # Behavioural pin: rendering does not leak any filter-side ARIA
      # contract attributes (the slice-6 step 8 filter_chip uses a
      # `data-budget-filter-state` instead of `aria-pressed`).
      html = render_form_chip(%{cost: 100, pressed?: false})

      refute html =~ "data-filter-state"
      refute html =~ "data-budget-filter-state"
    end
  end

  describe "budget_badge/1 — slice 6 step 5" do
    defp render_budget_badge(assigns) do
      render_component(&BudgetChip.budget_badge/1, assigns)
    end

    test "cost: 100 renders <span data-testid=idea-budget-badge> with IT label" do
      html = render_budget_badge(%{cost: 100})

      assert html =~ ~s(data-testid="idea-budget-badge")

      [_full, inner] =
        Regex.run(
          ~r{<span[^>]*data-testid="idea-budget-badge"[^>]*>(.*?)</span>}s,
          html
        )

      assert String.trim(inner) == "fino a 100€"
    end

    test "cost: 0 renders the IT label 'gratis'" do
      html = render_budget_badge(%{cost: 0})

      [_full, inner] =
        Regex.run(
          ~r{<span[^>]*data-testid="idea-budget-badge"[^>]*>(.*?)</span>}s,
          html
        )

      assert String.trim(inner) == "gratis"
    end

    test "cost: 1000 renders the IT label 'oltre 1000€'" do
      html = render_budget_badge(%{cost: 1000})

      [_full, inner] =
        Regex.run(
          ~r{<span[^>]*data-testid="idea-budget-badge"[^>]*>(.*?)</span>}s,
          html
        )

      assert String.trim(inner) == "oltre 1000€"
    end

    # AA14 — XSS structural pin: the badge label must flow through HEEx
    # auto-escape via `{Budget.label(@cost)}`. Never wrap with `raw/1` or
    # `Phoenix.HTML.raw` (parallel to slice 5 DurationChip badge AA14 pin).
    test "source contains {Budget.label(@cost)} interpolation and no raw/1 calls" do
      src =
        File.read!(Path.join(File.cwd!(), "lib/ideajar_web/components/budget_chip.ex"))

      assert src =~ "{Budget.label(@cost)}"
      refute src =~ ~r/\braw\(/
      refute src =~ "Phoenix.HTML.raw"
    end
  end

  describe "filter_chip/1 (slice 6 step 8)" do
    defp render_filter_chip(assigns) do
      render_component(&BudgetChip.filter_chip/1, assigns)
    end

    test "state: :off renders id, data-state=off, aria-label=label, no icon, phx-* wiring" do
      html = render_filter_chip(%{cost: 100, state: :off})

      assert html =~ ~s(id="filter-budget-chip-100")
      assert html =~ ~s(data-budget-filter-state="off")
      assert html =~ ~s(aria-label="fino a 100€")
      assert html =~ ~s(phx-click="toggle_budget_filter")
      assert html =~ ~s(phx-value-cost="100")
      assert html =~ ~s(type="button")
      refute html =~ "hero-check"
      # filter_chip is a 2-state binary filter — distinct from the
      # form chip's aria-pressed contract. No aria-pressed must appear.
      refute html =~ "aria-pressed"
    end

    test "state: :on renders data-state=on, aria-label='<label> attiva', hero-check icon" do
      html = render_filter_chip(%{cost: 100, state: :on})

      assert html =~ ~s(data-budget-filter-state="on")
      assert html =~ ~s(aria-label="fino a 100€ attiva")
      assert html =~ "hero-check"
      refute html =~ "aria-pressed"
    end

    # S6 type-level mutua esclusione: filter_chip does NOT accept attr `pressed?`.
    test "S6: source declares no `attr :pressed?` near `def filter_chip`" do
      src =
        File.read!(Path.join(File.cwd!(), "lib/ideajar_web/components/budget_chip.ex"))

      # Locate the `def filter_chip` definition and inspect a window of source
      # lines preceding it. Phoenix.Component attaches the most recent `attr`
      # declarations to the next component definition, so we want to scope the
      # negative assertion to the attrs that target `filter_chip/1`.
      {filter_chip_pos, _} = :binary.match(src, "def filter_chip(assigns)")
      preceding = binary_part(src, 0, filter_chip_pos)

      # Inspect the trailing block since the previous `def`. This is the attr
      # block that will bind to filter_chip/1.
      last_def_pos =
        case :binary.matches(preceding, "def ") do
          [] -> 0
          matches -> matches |> List.last() |> elem(0)
        end

      filter_chip_attrs_block =
        binary_part(preceding, last_def_pos, byte_size(preceding) - last_def_pos)

      refute filter_chip_attrs_block =~ ~r/attr :pressed\?,/
    end

    test "tabindex defaults to -1; explicit tabindex: 0 is rendered" do
      html_default = render_filter_chip(%{cost: 100, state: :off})
      assert html_default =~ ~s(tabindex="-1")

      html_zero = render_filter_chip(%{cost: 100, state: :off, tabindex: 0})
      assert html_zero =~ ~s(tabindex="0")
    end

    # BB14 IT label uniformity for the 3 boundary buckets.
    test "BB14 aria-label uniformity: cost 0 → 'gratis' / 'gratis attiva'" do
      html_off = render_filter_chip(%{cost: 0, state: :off})
      assert html_off =~ ~s(aria-label="gratis")
      refute html_off =~ ~s(aria-label="gratis attiva")

      html_on = render_filter_chip(%{cost: 0, state: :on})
      assert html_on =~ ~s(aria-label="gratis attiva")
    end

    test "BB14 aria-label uniformity: cost 100 → 'fino a 100€' / 'fino a 100€ attiva'" do
      html_off = render_filter_chip(%{cost: 100, state: :off})
      assert html_off =~ ~s(aria-label="fino a 100€")
      refute html_off =~ ~s(aria-label="fino a 100€ attiva")

      html_on = render_filter_chip(%{cost: 100, state: :on})
      assert html_on =~ ~s(aria-label="fino a 100€ attiva")
    end

    test "BB14 aria-label uniformity: cost 1000 → 'oltre 1000€' / 'oltre 1000€ attiva'" do
      html_off = render_filter_chip(%{cost: 1000, state: :off})
      assert html_off =~ ~s(aria-label="oltre 1000€")
      refute html_off =~ ~s(aria-label="oltre 1000€ attiva")

      html_on = render_filter_chip(%{cost: 1000, state: :on})
      assert html_on =~ ~s(aria-label="oltre 1000€ attiva")
    end
  end
end
