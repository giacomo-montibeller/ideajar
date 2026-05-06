defmodule Ideajar.CategoriesFixtures do
  @moduledoc """
  Test fixtures for the canonical seeded categories.

  Lives outside `Ideajar.DataCase` so tests opt in explicitly. Slice 4
  (filter) and slice 8 (search) will reuse these helpers.
  """

  alias Ideajar.Categories
  alias Ideajar.Categories.Category
  alias Ideajar.Repo

  @doc """
  Returns the Category struct for the canonical seeded category with the
  given name (e.g. "mare", "viaggio"). The seed migration runs as part of
  `mix ecto.migrate` so all 8 are available in tests.
  """
  @spec category_by_name!(String.t()) :: Category.t()
  def category_by_name!(name), do: Repo.get_by!(Category, name: name)

  @doc """
  Returns all 8 seeded categories ordered by `display_order` ASC.
  """
  @spec all_canonical_categories() :: [Category.t()]
  def all_canonical_categories, do: Categories.list_categories()

  @canonical_emojis %{
    "passeggiata" => "🚶",
    "mare" => "🏖️",
    "museo" => "🏛️",
    "ristorante" => "🍽️",
    "sport" => "⚽",
    "cultura" => "🎭",
    "cinema" => "🎬",
    "viaggio" => "✈️"
  }

  @doc """
  Single source of truth for the canonical category emojis in tests.

  Mirrors the values written by the `add_emoji_to_categories` migration —
  if those drift, the corresponding `Ideajar.CategoriesTest` assertion
  fails and pins the divergence. Tests must read emoji strings from this
  function rather than hard-coding them inline, to avoid drift on the
  variation-selector forms (e.g. `🏖️` is U+1F3D6 + U+FE0F).
  """
  @spec canonical_emojis() :: %{String.t() => String.t()}
  def canonical_emojis, do: @canonical_emojis
end
