defmodule Ideajar.Repo.Migrations.CreateIdeas do
  use Ecto.Migration

  def change do
    create table(:ideas) do
      add :title, :string, null: false
      add :description, :text
      add :url, :text

      timestamps(type: :utc_datetime)
    end

    create index(:ideas, [:inserted_at], name: :ideas_inserted_at_desc_idx)
  end
end
