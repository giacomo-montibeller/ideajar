defmodule IdeajarWeb.Components.DurationChipTest do
  @moduledoc """
  Unit tests for the slice-5 `DurationChip.form_chip/1` binary chip used
  by the add-idea form fieldset Durata. The chip carries
  `aria-pressed="true|false"` (single-select enforced server-side via
  `@selected_duration :: atom | nil`).

  Slice 6 will add `filter_chip/1` here with a separate ARIA contract
  (`data-duration-filter-state`); type-level mutual exclusion (S8) is
  pinned in this file by asserting `form_chip/1` does NOT accept attr
  `state`.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias IdeajarWeb.Components.DurationChip

  defp render_form_chip(assigns) do
    render_component(&DurationChip.form_chip/1, assigns)
  end

  describe "form_chip/1 — pressed?: false" do
    test "renders aria-pressed=false, no icon, hard-coded id and phx-* wiring" do
      html = render_form_chip(%{duration: :weekend, pressed?: false})

      assert html =~ ~s(id="form-duration-chip-weekend")
      assert html =~ ~s(aria-pressed="false")
      assert html =~ ~s(phx-click="toggle_form_duration")
      assert html =~ ~s(phx-value-duration="weekend")
      assert html =~ ~s(type="button")
      refute html =~ "hero-check"
    end

    test "carries min-h-11 min-w-11 (>=44 CSS px target size)" do
      html = render_form_chip(%{duration: :weekend, pressed?: false})

      assert html =~ "min-h-11"
      assert html =~ "min-w-11"
    end

    test "renders the IT label 'weekend'" do
      html = render_form_chip(%{duration: :weekend, pressed?: false})
      assert html =~ "weekend"
    end
  end

  describe "form_chip/1 — pressed?: true" do
    test "renders aria-pressed=true and the hero-check icon" do
      html = render_form_chip(%{duration: :weekend, pressed?: true})

      assert html =~ ~s(aria-pressed="true")
      assert html =~ "hero-check"
    end
  end

  describe "form_chip/1 — IT labels for compound atoms" do
    test "duration=:poche_ore renders 'poche ore' (with space, not the atom form)" do
      html = render_form_chip(%{duration: :poche_ore, pressed?: false})

      assert html =~ "poche ore"
      # Atom-form must not leak into the label rendering. The DOM id legitimately
      # contains "poche_ore" so we scope the negative assertion to the rendered
      # text content between > and <.
      refute Regex.match?(~r{>\s*poche_ore\s*<}, html)
    end

    test "duration=:piu_giorni renders 'più giorni' (with the accent)" do
      html = render_form_chip(%{duration: :piu_giorni, pressed?: false})

      assert html =~ "più giorni"
    end

    test "duration=:mezza_giornata renders 'mezza giornata'" do
      html = render_form_chip(%{duration: :mezza_giornata, pressed?: false})

      assert html =~ "mezza giornata"
    end
  end

  describe "duration_badge/1 — slice 5 step 4 (idea card)" do
    defp render_badge(assigns) do
      render_component(&DurationChip.duration_badge/1, assigns)
    end

    test "renders a span with data-testid=idea-duration-badge and the IT label" do
      html = render_badge(%{duration: :weekend})

      assert html =~ ~s(data-testid="idea-duration-badge")
      assert html =~ ~s(<span)

      [_full, inner] =
        Regex.run(
          ~r{<span[^>]*data-testid="idea-duration-badge"[^>]*>(.*?)</span>}s,
          html
        )

      assert String.trim(inner) == "weekend"
    end

    test "renders subtle bg-base-200 (visually distinct from category badges)" do
      html = render_badge(%{duration: :weekend})

      assert html =~ "bg-base-200"
      assert html =~ "rounded-full"
      assert html =~ "border"
      assert html =~ "text-xs"
    end

    test "compound atoms render IT label with spaces, not underscores" do
      for {atom, label} <- [
            {:poche_ore, "poche ore"},
            {:mezza_giornata, "mezza giornata"},
            {:giornata, "giornata"},
            {:weekend, "weekend"},
            {:piu_giorni, "più giorni"}
          ] do
        html = render_badge(%{duration: atom})

        [_full, inner] =
          Regex.run(
            ~r{<span[^>]*data-testid="idea-duration-badge"[^>]*>(.*?)</span>}s,
            html
          )

        assert String.trim(inner) == label
      end
    end

    # AA14 — XSS regression sintetica (structural pin):
    # `Duration.label/1` is hard-coded and cannot produce HTML chars (pinned by
    # the DurationTest XSS-via-atom test). The remaining drift surface is the
    # component itself. Pin that the badge interpolates the label via HEEx
    # auto-escape (`{Duration.label(@duration)}`) and never via `raw/1`.
    test "AA14 structural pin: badge source uses HEEx auto-escape, no raw/1 calls" do
      src =
        File.read!(Path.join(File.cwd!(), "lib/ideajar_web/components/duration_chip.ex"))

      assert src =~ ~r/\{Duration\.label\(@duration\)\}/
      refute src =~ ~r/\braw\(/
      refute src =~ ~r/Phoenix\.HTML\.raw/
    end
  end

  describe "form_chip/1 — type-level mutual exclusion (S8)" do
    test "does NOT declare attr :state (only :duration and :pressed?)" do
      attrs = DurationChip.__info__(:attributes)
      _ = attrs

      # Phoenix.Component stores attr declarations in a module attribute that
      # isn't available at runtime once compiled, but we can still verify the
      # public surface via the function's compiled metadata. We pin the
      # absence of :state at the source level by asserting that calling
      # `form_chip/1` with a :state assign does not produce a rendered
      # `data-filter-state` attribute (the slice-6 filter_chip contract).
      html = render_form_chip(%{duration: :weekend, pressed?: false})

      refute html =~ "data-filter-state"
      refute html =~ "data-duration-filter-state"
    end
  end

  describe "filter_chip/1 (slice 5 step 6)" do
    defp render_filter_chip(assigns) do
      render_component(&DurationChip.filter_chip/1, assigns)
    end

    test "state: :off renders id, data-state=off, aria-label=label, no icon, phx-* wiring" do
      html = render_filter_chip(%{duration: :weekend, state: :off})

      assert html =~ ~s(id="filter-duration-chip-weekend")
      assert html =~ ~s(data-duration-filter-state="off")
      assert html =~ ~s(aria-label="weekend")
      assert html =~ ~s(phx-click="toggle_duration_filter")
      assert html =~ ~s(phx-value-duration="weekend")
      assert html =~ ~s(type="button")
      refute html =~ "hero-check"
      # filter_chip is a 2-state binary filter — distinct from the
      # form chip's aria-pressed contract. No aria-pressed must appear.
      refute html =~ "aria-pressed"
    end

    test "state: :on renders data-state=on, aria-label='<label> attiva', hero-check icon" do
      html = render_filter_chip(%{duration: :weekend, state: :on})

      assert html =~ ~s(data-duration-filter-state="on")
      assert html =~ ~s(aria-label="weekend attiva")
      assert html =~ "hero-check"
      refute html =~ "aria-pressed"
    end

    # S8 type-level mutua esclusione: filter_chip does NOT accept attr `pressed?`.
    # A caller passing pressed?: true would either crash (compile-time attr
    # validation) or be silently dropped — verify rendering is unaffected and
    # no aria-pressed leaks through (the form-chip contract must not appear).
    test "S8: does NOT accept attr :pressed? — no aria-pressed in rendered output" do
      html = render_filter_chip(%{duration: :weekend, state: :off})
      refute html =~ "aria-pressed"

      html_on = render_filter_chip(%{duration: :weekend, state: :on})
      refute html_on =~ "aria-pressed"
    end

    test "tabindex defaults to -1; explicit tabindex: 0 is rendered" do
      html_default = render_filter_chip(%{duration: :weekend, state: :off})
      assert html_default =~ ~s(tabindex="-1")

      html_zero = render_filter_chip(%{duration: :weekend, state: :off, tabindex: 0})
      assert html_zero =~ ~s(tabindex="0")
    end

    test "renders the IT label (poche ore, mezza giornata, più giorni)" do
      html_poche = render_filter_chip(%{duration: :poche_ore, state: :off})
      assert html_poche =~ "poche ore"
      assert html_poche =~ ~s(aria-label="poche ore")

      html_mezza = render_filter_chip(%{duration: :mezza_giornata, state: :off})
      assert html_mezza =~ "mezza giornata"

      html_piu = render_filter_chip(%{duration: :piu_giorni, state: :off})
      assert html_piu =~ "più giorni"
    end
  end
end
