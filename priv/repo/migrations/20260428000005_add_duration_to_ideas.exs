defmodule Ideajar.Repo.Migrations.AddDurationToIdeas do
  use Ecto.Migration

  def change do
    alter table(:ideas) do
      add :duration, :string, null: true
    end
  end
end
