defmodule IdeajarWeb.Components.ChipBaseTest do
  @moduledoc """
  Unit tests for the slice-6 `IdeajarWeb.Components.ChipBase` shared
  helper module (R5-2 extraction). The class string is the single source
  of truth for the chip family visual base; previously duplicated as
  `defp chip_base_class/0` in `CategoryChip` + `DurationChip`. This file
  also pins the deletion of the private duplicates as a regression
  invariant (BB12) so a future contributor cannot accidentally
  reintroduce a local override that would silently shadow the shared
  helper.
  """
  use ExUnit.Case, async: true

  alias IdeajarWeb.Components.ChipBase

  describe "chip_base_class/0" do
    test "returns the verbatim shared chip class string" do
      assert ChipBase.chip_base_class() ==
               "min-h-11 min-w-11 px-3 py-2 rounded-full border-2 inline-flex items-center gap-1 text-sm"
    end
  end

  describe "BB12 — private duplicates deleted post-extraction" do
    test "lib/ideajar_web/components/category_chip.ex does NOT contain `defp chip_base_class`" do
      source = File.read!("lib/ideajar_web/components/category_chip.ex")
      refute source =~ "defp chip_base_class"
    end

    test "lib/ideajar_web/components/duration_chip.ex does NOT contain `defp chip_base_class`" do
      source = File.read!("lib/ideajar_web/components/duration_chip.ex")
      refute source =~ "defp chip_base_class"
    end
  end
end
