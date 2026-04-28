defmodule Ideajar.Ideas do
  @moduledoc """
  Domain context for ideas.

  Slice 2 exposed only what the LiveView needed: list and create. Slice 3
  extends `create_idea/1` to take `category_ids` and validate them via the
  `Ideajar.Categories` boundary, and extends `list_ideas/0` to preload
  the `:categories` association ordered by `display_order`.

  Slice 5 adds the `durations: [atom]` filter clause to `list_ideas/1`
  (NULL ideas excluded when the clause is non-empty — see AA7) and
  refactors the three `apply_*` private helpers behind a single
  `apply_filters/2` private composer (AA8, rule of 3 fires).
  """

  import Ecto.Query

  alias Ideajar.Categories
  alias Ideajar.Ideas.Idea
  alias Ideajar.Repo

  @doc """
  Returns every idea ordered by `inserted_at` descending, with `id`
  descending as a deterministic tie-breaker. Each idea has its
  `:categories` association preloaded and sorted by `display_order` ASC.

  Accepted opts (each defaults to an empty list = clause inactive):

    * `:required` — `[integer]`, AND across category ids (slice 4)
    * `:optional` — `[integer]`, OR across category ids (slice 4)
    * `:durations` — `[atom]`, OR across duration atoms (slice 5).
      When non-empty, ideas with `duration: nil` are EXCLUDED — see AA7.
      An empty list (or omitting the opt) leaves NULL ideas in the result.

  `list_ideas/0` and `list_ideas([])` are equivalent (regression-pinned).
  """
  @spec list_ideas() :: [Idea.t()]
  @spec list_ideas(keyword()) :: [Idea.t()]
  def list_ideas(opts \\ []) when is_list(opts) do
    Keyword.keyword?(opts) ||
      raise ArgumentError,
            "list_ideas/1 expects a keyword list, got: #{inspect(opts)}"

    opts
    |> build_query()
    |> Repo.all()
    |> Repo.preload(categories: Categories.preload_query())
  end

  @doc false
  # Test seam: returns the composed Ecto query before `Repo.all` runs so
  # tests can pin the emitted SQL via `Repo.to_sql/2`. Parallel to
  # `create_idea_fun` in `IdeaLive.Index`. Not part of the public API.
  @spec build_query(keyword()) :: Ecto.Query.t()
  def build_query(opts) when is_list(opts) do
    base_query = from i in Idea, order_by: [desc: i.inserted_at, desc: i.id]
    apply_filters(base_query, opts)
  end

  # Single composer for every filter clause. Rule of 3 fires (required,
  # optional, durations) — slice 6+ would extract this into a dedicated
  # `Ideajar.Ideas.Filter` module if a fourth clause lands (see R5-1).
  defp apply_filters(query, opts) do
    query
    |> apply_required(Keyword.get(opts, :required, []))
    |> apply_optional(Keyword.get(opts, :optional, []))
    |> apply_durations(Keyword.get(opts, :durations, []))
  end

  # AND clause: an idea passes only if every required category id is
  # present on it. Implemented via subquery with `HAVING COUNT(DISTINCT
  # category_id)` equal to the unique-id count, which is the SQL-emission
  # we pin via `Ecto.Adapters.SQL.to_sql/2` in tests.
  defp apply_required(query, []), do: query

  defp apply_required(query, ids) do
    unique = Enum.uniq(ids)
    count = length(unique)

    subq =
      from ic in "idea_categories",
        where: ic.category_id in ^unique,
        group_by: ic.idea_id,
        having: count(fragment("DISTINCT ?", ic.category_id)) == ^count,
        select: ic.idea_id

    from i in query, where: i.id in subquery(subq)
  end

  # OR clause: an idea passes if any of the optional ids is present on
  # it. Implemented via subquery `WHERE category_id IN ^optional`. An
  # empty list is a no-op (no filter applied). Duplicates are
  # normalized via Enum.uniq before the query is built.
  defp apply_optional(query, []), do: query

  defp apply_optional(query, ids) do
    subq =
      from ic in "idea_categories",
        where: ic.category_id in ^Enum.uniq(ids),
        select: ic.idea_id

    from i in query, where: i.id in subquery(subq)
  end

  # OR clause across duration atoms with strict NULL exclusion (AA7).
  # An empty list is a no-op (clause inactive, NULL ideas pass through).
  # When non-empty, the emitted SQL is `WHERE "duration" IN (...)` with
  # no `OR IS NULL`, so ideas without a stored duration are filtered out
  # by SQL three-valued logic. Duplicates are normalized via Enum.uniq
  # to keep the parameter list compact.
  defp apply_durations(query, []), do: query

  defp apply_durations(query, durations) do
    from i in query, where: i.duration in ^Enum.uniq(durations)
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
