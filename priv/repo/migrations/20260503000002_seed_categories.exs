defmodule Ideajar.Repo.Migrations.SeedCategories do
  @moduledoc """
  Slice 11a — re-baselined data migration. Logically identical to the
  pre-slice-11a `seed_categories` (insert_all with on_conflict :nothing
  on `:name` for idempotent re-runs). Carried forward unchanged across
  the SQLite → Postgres adapter swap because `Repo.insert_all/3` with
  `on_conflict: :nothing, conflict_target: :name` is portable.
  """
  use Ecto.Migration

  import Ecto.Query, only: [from: 2]

  @seed_categories [
    {1, "passeggiata"},
    {2, "mare"},
    {3, "museo"},
    {4, "ristorante"},
    {5, "sport"},
    {6, "cultura"},
    {7, "cinema"},
    {8, "viaggio"}
  ]

  def up do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(@seed_categories, fn {order, name} ->
        %{
          name: name,
          display_order: order,
          inserted_at: now,
          updated_at: now
        }
      end)

    repo().insert_all("categories", rows, on_conflict: :nothing, conflict_target: :name)
  end

  def down do
    names = Enum.map(@seed_categories, fn {_order, name} -> name end)
    repo().delete_all(from(c in "categories", where: c.name in ^names))
  end
end
