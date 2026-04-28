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
end
