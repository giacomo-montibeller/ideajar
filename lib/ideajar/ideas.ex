defmodule Ideajar.Ideas do
  @moduledoc """
  Domain context for ideas.

  Slice 2 exposes only what the LiveView needs: list and create. Edit and
  delete are deliberately out of scope. There is no `change_idea/2`: the
  LiveView builds its initial form straight from `Idea.changeset/2`, since
  the wrapper added nothing beyond a thin re-export (decision A3 in the
  slice-2 plan).
  """

  import Ecto.Query

  alias Ideajar.Ideas.Idea
  alias Ideajar.Repo

  @doc """
  Returns every idea ordered by `inserted_at` descending, with `id`
  descending as a deterministic tie-breaker.
  """
  @spec list_ideas() :: [Idea.t()]
  def list_ideas do
    Repo.all(from i in Idea, order_by: [desc: i.inserted_at, desc: i.id])
  end

  @doc """
  Builds a changeset from `attrs` and inserts it. Returns the persisted
  idea on success, or the invalid changeset (no I/O performed) on failure.
  """
  @spec create_idea(map()) :: {:ok, Idea.t()} | {:error, Ecto.Changeset.t()}
  def create_idea(attrs) when is_map(attrs) do
    %Idea{}
    |> Idea.changeset(attrs)
    |> Repo.insert()
  end
end
