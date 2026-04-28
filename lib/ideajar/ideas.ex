defmodule Ideajar.Ideas do
  @moduledoc """
  Domain context for ideas.

  Slice 2 exposed only what the LiveView needed: list and create. Slice 3
  extends `create_idea/1` to take `category_ids` and validate them via the
  `Ideajar.Categories` boundary, and extends `list_ideas/0` to preload
  the `:categories` association ordered by `display_order`.
  """

  import Ecto.Query

  alias Ideajar.Categories
  alias Ideajar.Ideas.Idea
  alias Ideajar.Repo

  @doc """
  Returns every idea ordered by `inserted_at` descending, with `id`
  descending as a deterministic tie-breaker. Each idea has its
  `:categories` association preloaded and sorted by `display_order` ASC.

  Slice 4 extends with optional `:required` and `:optional` keyword
  filter clauses. `list_ideas/0` and `list_ideas([])` are equivalent
  (regression-pinned).
  """
  @spec list_ideas() :: [Idea.t()]
  @spec list_ideas(keyword()) :: [Idea.t()]
  def list_ideas(opts \\ []) when is_list(opts) do
    Keyword.keyword?(opts) ||
      raise ArgumentError,
            "list_ideas/1 expects a keyword list, got: #{inspect(opts)}"

    Repo.all(from i in Idea, order_by: [desc: i.inserted_at, desc: i.id])
    |> Repo.preload(categories: Categories.preload_query())
  end

  @doc """
  Builds a changeset from `attrs` and inserts it.

  `attrs` may be atom-keyed (domain callers) or string-keyed (LiveView form
  submissions). When `category_ids` is present, ids are resolved through
  `Categories.list_by_ids/1` (safe int cast, dedupe POST cast,
  all-or-nothing). On invalid ids the function builds a minimal error
  changeset with exactly one error on `:categories`
  (`Categories.invalid_message/0`) — it does NOT fall through
  `Idea.changeset/2`, so the canonical "Seleziona almeno una categoria"
  message does not pile on top.

  Returns the persisted idea (with `:categories` preloaded ordered) on
  success or the invalid changeset on failure (no I/O performed when the
  changeset is invalid).
  """
  @spec create_idea(map()) :: {:ok, Idea.t()} | {:error, Ecto.Changeset.t()}
  def create_idea(attrs) when is_map(attrs) do
    raw_ids = fetch_raw_category_ids(attrs)

    case Categories.list_by_ids(raw_ids) do
      {:ok, cats} ->
        attrs
        |> inject_resolved_categories(cats)
        |> insert_idea()

      {:error, :not_found} ->
        {:error, build_invalid_categories_changeset(attrs)}
    end
  end

  defp fetch_raw_category_ids(attrs) do
    Map.get(attrs, "category_ids") || Map.get(attrs, :category_ids) || []
  end

  # Inject the resolved Category structs using the same key style the
  # caller used. We probe the actual key shape rather than hard-coding a
  # specific key name so that adding new fields elsewhere doesn't break
  # the detection.
  defp inject_resolved_categories(attrs, cats) do
    if string_keyed?(attrs) do
      Map.put(attrs, "categories", cats)
    else
      Map.put(attrs, :categories, cats)
    end
  end

  defp string_keyed?(attrs) do
    Enum.any?(Map.keys(attrs), &is_binary/1)
  end

  defp insert_idea(attrs) do
    with {:ok, idea} <- %Idea{} |> Idea.changeset(attrs) |> Repo.insert() do
      {:ok, Repo.preload(idea, categories: Categories.preload_query())}
    end
  end

  # Builds a changeset that surfaces ONLY the controlled "Categoria non
  # valida" error on :categories, while preserving title / description /
  # url so the LV re-render shows what the user typed. We deliberately
  # avoid running `Idea.changeset/2` here — its
  # `validate_at_least_one_category` would add a second error on the
  # same field.
  defp build_invalid_categories_changeset(attrs) do
    %Idea{}
    |> Ecto.Changeset.cast(attrs, [:title, :description, :url])
    |> Ecto.Changeset.add_error(:categories, Categories.invalid_message())
  end
end
