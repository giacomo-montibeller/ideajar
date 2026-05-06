defmodule Ideajar.Repo.Migrations.AddTargetWindowToIdeas do
  @moduledoc """
  Slice 15 — adds the optional target time window ("Quando") to ideas.

  Four columns:

    * `target_start` (DATE, NULL) — start of the planned window.
    * `target_end` (DATE, NULL) — end of the planned window. Cross-field
      validation (end ≥ start, month boundaries) lives at the changeset
      boundary in `Ideajar.Ideas.TargetWindow.validate_changeset/1`.
    * `target_granularity` (TEXT, NULL) — `"day"` or `"month"`. Stored as
      string; mapped in the schema via `Ecto.Enum`.
    * `target_weekend_only` (BOOLEAN, NOT NULL DEFAULT false) — meaningful
      only when `target_granularity = "month"`. The default lets existing
      rows pass the NOT NULL constraint without a backfill step.

  Down rolls all four columns back; existing rows lose the data but the
  schema returns to the pre-slice-15 shape.
  """
  use Ecto.Migration

  def up do
    alter table(:ideas) do
      add :target_start, :date
      add :target_end, :date
      add :target_granularity, :text
      add :target_weekend_only, :boolean, null: false, default: false
    end
  end

  def down do
    alter table(:ideas) do
      remove :target_start
      remove :target_end
      remove :target_granularity
      remove :target_weekend_only
    end
  end
end
