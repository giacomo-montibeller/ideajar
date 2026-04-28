defmodule Ideajar.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:categories) do
      add :name, :string, null: false
      add :display_order, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:categories, [:name])
    create unique_index(:categories, [:display_order])
  end
end
