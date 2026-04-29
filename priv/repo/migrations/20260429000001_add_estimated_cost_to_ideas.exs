defmodule Ideajar.Repo.Migrations.AddEstimatedCostToIdeas do
  use Ecto.Migration

  def change do
    alter table(:ideas) do
      add :estimated_cost, :integer, null: true
    end
  end
end
