defmodule Ideajar.Categories do
  @moduledoc """
  Domain context for the curated category vocabulary.

  Slice 3 ships eight categories seeded in migration; this module is the
  single read boundary for the rest of the app. There is no `create_category/1`,
  `update_category/2`, or `delete_category/1` — the seed is the contract,
  modifications go through migrations.
  """

  import Ecto.Query

  alias Ideajar.Categories.Category
  alias Ideajar.Repo

  @doc """
  Returns every category ordered by `display_order` ascending.
  """
  @spec list_categories() :: [Category.t()]
  def list_categories do
    Repo.all(from c in Category, order_by: [asc: c.display_order])
  end

  @doc """
  Looks up categories by id, returning all-or-nothing.

  Behaviour:

    * Casts each id to a positive integer; non-integer, non-numeric,
      negative, zero, nil, and float values reject the whole list with
      `{:error, :not_found}` (no exception).
    * Deduplicates ids **after** casting so `["1", 1]` collapse to a
      single lookup.
    * Returns `{:ok, [%Category{}, ...]}` only if every requested id
      resolved to a row; otherwise `{:error, :not_found}`.
    * Empty list returns `{:ok, []}` — caller decides whether that
      satisfies their min-1 contract.
  """
  @spec list_by_ids([any]) :: {:ok, [Category.t()]} | {:error, :not_found}
  def list_by_ids(raw_ids) when is_list(raw_ids) do
    with {:ok, ints} <- safe_cast_ints(raw_ids) do
      unique = Enum.uniq(ints)

      cats = Repo.all(from c in Category, where: c.id in ^unique)

      if length(cats) == length(unique) do
        {:ok, cats}
      else
        {:error, :not_found}
      end
    end
  end

  defp safe_cast_ints(raw) do
    raw
    |> Enum.reduce_while({:ok, []}, fn
      n, {:ok, acc} when is_integer(n) and n > 0 ->
        {:cont, {:ok, [n | acc]}}

      s, {:ok, acc} when is_binary(s) ->
        case Integer.parse(s) do
          {n, ""} when n > 0 -> {:cont, {:ok, [n | acc]}}
          _ -> {:halt, {:error, :not_found}}
        end

      _, _ ->
        {:halt, {:error, :not_found}}
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      err -> err
    end
  end
end
