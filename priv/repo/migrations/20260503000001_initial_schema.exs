defmodule Ideajar.Repo.Migrations.InitialSchema do
  @moduledoc """
  Slice 11a — consolidated initial schema (Postgres).

  Replaces the 8 slice-by-slice SQLite migrations from slices 1..7a
  (`create_ideas`, `create_categories`, `create_idea_categories`,
  `add_duration_to_ideas`, `add_estimated_cost_to_ideas`,
  `add_location_to_ideas`, plus the `wipe_slice2_dev_ideas` one-shot
  cleanup) into a single migration that creates the final schema in
  one go. Pre-launch consolidation: there is no production data to
  preserve, so collapsing the history is the standard pattern.

  `change/0` is used so Ecto auto-derives the rollback for DDL.
  Indexes and foreign keys are explicit. ON DELETE CASCADE on the
  join table mirrors what the schema modules already document.
  """
  use Ecto.Migration

  def change do
    create table(:categories) do
      add :name, :string, null: false
      add :display_order, :integer, null: false
      timestamps()
    end

    create unique_index(:categories, [:name])
    create unique_index(:categories, [:display_order])

    create table(:ideas) do
      add :title, :text, null: false
      add :description, :text
      add :url, :text
      add :duration, :string
      add :estimated_cost, :integer
      add :location_name, :text
      add :lat, :float
      add :lng, :float
      timestamps()
    end

    create index(:ideas, [:inserted_at])

    # Many-to-many join table — Phoenix auto-builds rows via
    # `put_assoc(:categories, [...])` without setting timestamps, so
    # the columns must be omitted (not just nullable).
    create table(:idea_categories, primary_key: false) do
      # CASCADE on idea delete (slice 4 contract: deleting an idea
      # tears down its category links). RESTRICT on category delete
      # because removing a category that ideas still reference would
      # silently mutate them; surface it as a constraint error so
      # admin tooling has to clean up first.
      add :idea_id, references(:ideas, on_delete: :delete_all), primary_key: true
      add :category_id, references(:categories, on_delete: :restrict), primary_key: true
    end

    # The composite primary key already enforces uniqueness on (idea_id,
    # category_id) and provides an index on the leading column. We add
    # an explicit category_id index so reverse lookups (all ideas of a
    # category) hit an index too.
    create index(:idea_categories, [:category_id])
  end
end
