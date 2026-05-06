defmodule Ideajar.Repo.Migrations.AddEmojiToCategories do
  @moduledoc """
  Adds the `emoji` column to `categories` and backfills the canonical map
  on the eight seeded rows. The column is nullable for the duration of
  the backfill, then set NOT NULL — standard Postgres pattern for
  introducing a non-null column on a non-empty table.

  The mirror map for tests lives in `Ideajar.CategoriesFixtures.canonical_emojis/0`;
  if these two diverge `Ideajar.CategoriesTest` will fail and pin it.
  """
  use Ecto.Migration

  @emoji_by_name %{
    "passeggiata" => "🚶",
    "mare" => "🏖️",
    "museo" => "🏛️",
    "ristorante" => "🍽️",
    "sport" => "⚽",
    "cultura" => "🎭",
    "cinema" => "🎬",
    "viaggio" => "✈️"
  }

  def up do
    alter table(:categories) do
      add :emoji, :text
    end

    flush()

    Enum.each(@emoji_by_name, fn {name, emoji} ->
      repo().query!("UPDATE categories SET emoji = $1 WHERE name = $2", [emoji, name])
    end)

    flush()

    alter table(:categories) do
      modify :emoji, :text, null: false
    end
  end

  def down do
    alter table(:categories) do
      remove :emoji
    end
  end
end
