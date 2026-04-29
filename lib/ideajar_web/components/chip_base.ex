defmodule IdeajarWeb.Components.ChipBase do
  @moduledoc """
  Shared visual base class for the chip family components.

  Slice 6 R5-2 extraction. Previously duplicated as `defp chip_base_class/0`
  in CategoryChip + DurationChip; now a single source reused by all three
  current chip families (CategoryChip, DurationChip, BudgetChip). Future
  families (e.g. distance chips slice 7+) should call this same function.
  """

  @spec chip_base_class() :: String.t()
  def chip_base_class do
    "min-h-11 min-w-11 px-3 py-2 rounded-full border-2 inline-flex items-center gap-1 text-sm"
  end
end
