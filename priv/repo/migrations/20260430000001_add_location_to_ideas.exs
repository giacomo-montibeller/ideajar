defmodule Ideajar.Repo.Migrations.AddLocationToIdeas do
  use Ecto.Migration

  def change do
    alter table(:ideas) do
      add :location_name, :string, null: true
      add :lat, :float, null: true
      add :lng, :float, null: true
    end
  end
end
