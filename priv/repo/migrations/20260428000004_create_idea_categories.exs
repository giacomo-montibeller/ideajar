defmodule Ideajar.Repo.Migrations.CreateIdeaCategories do
  use Ecto.Migration

  def change do
    create table(:idea_categories, primary_key: false) do
      add :idea_id,
          references(:ideas, on_delete: :delete_all),
          null: false,
          primary_key: true

      add :category_id,
          references(:categories, on_delete: :restrict),
          null: false,
          primary_key: true
    end
  end
end
