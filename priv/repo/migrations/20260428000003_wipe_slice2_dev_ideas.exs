defmodule Ideajar.Repo.Migrations.WipeSlice2DevIdeas do
  use Ecto.Migration

  @moduledoc """
  One-shot wipe of the slice-2 development ideas.

  Slice 3 makes a multi-category association mandatory at the changeset
  level (`validate_length(:categories, min: 1, ...)`). Existing slice-2
  ideas were inserted before that invariant existed and have no
  categories — leaving them in place would create rows that can no longer
  be re-inserted by the application code, an awkward middle state for
  any future read path that reasons about "every idea has at least one
  category".

  This migration is acceptable because slice 2 was never deployed: only
  the developer's local DBs hold rows. The first production deploy
  (slice 9) will run this migration on a still-empty `ideas` table, so
  there is nothing real to lose.

  Raw `DELETE FROM ideas` rather than `Repo.delete_all(Ideajar.Ideas.Idea)`
  so a future schema rename of `Idea` does not silently break the
  migration replay.
  """

  def up, do: execute("DELETE FROM ideas")

  # No reverse — once wiped, the ideas are gone. `down/0` exists only so
  # the migration is enumerable in `mix ecto.rollback`.
  def down, do: :ok
end
