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

  Slice 6 step 2 (R5-1) extracts that composer into the dedicated
  `Ideajar.Ideas.Filter` module so the 4th clause (`apply_max_cost/2`,
  slice 6 step 6) can land without growing this context past its
  single-responsibility line. Behaviour is identical — the 3 clauses
  moved verbatim.

  Slice 6 step 6 adds the `:max_cost` opt to `list_ideas/1` (BB8). When
  an integer is given, only ideas with `estimated_cost <= ^max AND
  estimated_cost IS NOT NULL` are returned (NULL-exclude uniforme con
  AA7 durations). `nil` (or omitting the opt) leaves NULL-cost ideas
  in the result.

  Slice 12 adds `delete_idea/1` (hard delete by id) plus the `@doc false`
  helper `delete_struct_safe/1`. The cascade on the `idea_categories`
  join table is delegated to the FK `on_delete: :delete_all` declared in
  the initial migration; this context does not touch the join. A bare
  `rescue Ecto.StaleEntryError -> {:error, :not_found}` closes the race
  window where two processes both pass `Repo.get/2` and only one wins
  the delete — the loser is mapped to `:not_found` since the row is no
  longer there from the caller's perspective.
  """

  import Ecto.Query

  alias Ideajar.Categories
  alias Ideajar.Ideas.Filter
  alias Ideajar.Ideas.Idea
  alias Ideajar.Repo

  @doc """
  Returns every idea ordered by `inserted_at` descending, with `id`
  descending as a deterministic tie-breaker. Each idea has its
  `:categories` association preloaded and sorted by `display_order` ASC.

  Accepted opts (each defaults to its inactive value):

    * `:required` — `[integer]`, AND across category ids (slice 4)
    * `:optional` — `[integer]`, OR across category ids (slice 4)
    * `:durations` — `[atom]`, OR across duration atoms (slice 5).
      When non-empty, ideas with `duration: nil` are EXCLUDED — see AA7.
      An empty list (or omitting the opt) leaves NULL ideas in the result.
    * `:max_cost` — `integer | nil`, cumulative budget cap (slice 6).
      When an integer is given, only ideas with `estimated_cost <= ^max
      AND estimated_cost IS NOT NULL` are returned (NULL-exclude uniforme
      con AA7). `nil` (or omitting the opt) leaves NULL-cost ideas in
      the result.
    * `:max_distance_km` — `integer | nil`, great-circle radius cap (slice 7b).
      Coordinated with `:ref_lat`/`:ref_lng`. When all three are given,
      keeps only ideas with non-nil `lat`/`lng` and great-circle distance
      ≤ `max_distance_km` from the reference point. Any of the three
      being `nil` makes the clause inactive (NULL-coord ideas pass
      through). Implemented in the post-query layer (`Filter.apply_post/2`)
      because SQLite has no native Haversine without optional math
      extensions.
    * `:ref_lat` — `float | nil`, paired with `:max_distance_km`/`:ref_lng`.
    * `:ref_lng` — `float | nil`, paired with `:max_distance_km`/`:ref_lat`.
    * `:text_search` — `String.t() | nil`, case-insensitive substring on
      `title` OR `description` (slice 8). Inactive when `nil` or shorter
      than 3 chars. NULL-`description` ideas still match if their title
      matches — documented exception to the slice 5/6/7b uniform
      NULL-exclude pattern (DD-S8-4). LIKE wildcards `%`/`_`/`\` in user
      input are escaped to literal characters via `escape_like/1`.

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
    |> Filter.apply_post(opts)
  end

  @doc false
  # Test seam: returns the composed Ecto query before `Repo.all` runs so
  # tests can pin the emitted SQL via `Repo.to_sql/2`. Parallel to
  # `create_idea_fun` in `IdeaLive.Index`. Not part of the public API.
  @spec build_query(keyword()) :: Ecto.Query.t()
  def build_query(opts) when is_list(opts) do
    base_query = from i in Idea, order_by: [desc: i.inserted_at, desc: i.id]
    Filter.apply(base_query, opts)
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
    case change_idea_with_categories(%Idea{}, attrs) do
      {:ok, changeset} ->
        with {:ok, idea} <- Repo.insert(changeset) do
          # `force: true` is load-bearing: the changeset's `put_assoc`
          # already populated `idea.categories` in the order returned by
          # `Categories.list_by_ids/1` (Postgres heap order, no
          # ORDER BY), so a non-forced preload would no-op and leave the
          # association unordered. Mirrors the symmetric `force: true`
          # in `persist_idea_update/1`.
          {:ok, Repo.preload(idea, [categories: Categories.preload_query()], force: true)}
        end

      {:error, :invalid_categories} ->
        {:error, build_invalid_categories_changeset(attrs)}
    end
  end

  # Slice 14: shared helper between `create_idea/1` and `update_idea/2`.
  # Resolves the submitted `category_ids` via `Categories.list_by_ids/1`
  # (returns `{:error, :not_found}` if any id is unknown) and builds the
  # `Idea.changeset/2` against the given `base` (an `%Idea{}` for create,
  # the loaded idea for update). The atom error `:invalid_categories`
  # lets each caller wrap with its own controlled error changeset (which
  # for create starts from `%Idea{}` and for update preserves the loaded
  # idea's other fields, so the form re-render stays useful).
  @spec change_idea_with_categories(Idea.t(), map()) ::
          {:ok, Ecto.Changeset.t()} | {:error, :invalid_categories}
  defp change_idea_with_categories(%Idea{} = base, attrs) do
    case attrs |> fetch_raw_category_ids() |> Categories.list_by_ids() do
      {:ok, cats} ->
        {:ok, Idea.changeset(base, inject_resolved_categories(attrs, cats))}

      {:error, :not_found} ->
        {:error, :invalid_categories}
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

  @doc """
  Updates the idea identified by `id` with the given attributes.

  Slice 14. Wraps the lookup + category resolution + `Idea.changeset/2`
  + `Repo.update` in a single `Repo.transaction` so any failure (lookup
  miss, invalid category id, validation error) rolls back atomically.

  Last-write-wins between devices: there is no `expected_updated_at`
  token. The only race surfaced explicitly is `:not_found`
  (delete-vs-edit) — see slice 12 parity.

  Returns:
    * `{:ok, idea}` with `:categories` preloaded fresh on success.
    * `{:error, :not_found}` if the id does not match any row.
    * `{:error, %Ecto.Changeset{}}` for validation failures, including
      the controlled "Categoria non valida" message when a submitted
      `category_id` does not resolve in `Categories.list_by_ids/1`.
  """
  @spec update_idea(integer(), map()) ::
          {:ok, Idea.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update_idea(id, attrs) when is_integer(id) and is_map(attrs) do
    Repo.transaction(fn -> do_update_idea(id, attrs) end)
  end

  defp do_update_idea(id, attrs) do
    case Repo.get(Idea, id) do
      nil -> Repo.rollback(:not_found)
      idea -> apply_idea_update(idea, attrs)
    end
  end

  defp apply_idea_update(%Idea{} = idea, attrs) do
    idea = Repo.preload(idea, categories: Categories.preload_query())

    case change_idea_with_categories(idea, attrs) do
      {:ok, changeset} ->
        persist_idea_update(changeset)

      {:error, :invalid_categories} ->
        Repo.rollback(build_invalid_categories_changeset(idea, attrs))
    end
  end

  defp persist_idea_update(changeset) do
    case Repo.update(changeset) do
      {:ok, updated} ->
        Repo.preload(updated, [categories: Categories.preload_query()], force: true)

      {:error, cs} ->
        Repo.rollback(cs)
    end
  end

  @doc """
  Deletes the idea identified by `id`.

  The cascade on `idea_categories` is delegated to the FK
  `on_delete: :delete_all` declared in the initial migration; we do not
  touch the join table here. Returns `{:error, :not_found}` for both
  "the row never existed" and "another process already deleted it"
  (the latter via `delete_struct_safe/1`'s rescue).
  """
  @spec delete_idea(integer()) ::
          {:ok, Idea.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def delete_idea(id) when is_integer(id) do
    case Repo.get(Idea, id) do
      nil -> {:error, :not_found}
      idea -> delete_struct_safe(idea)
    end
  end

  @doc false
  # Test seam exposed for slice 12 F12: lets the test feed two stale
  # `%Idea{}` references (simulating two processes that both passed
  # `Repo.get/2`) so the rescue branch is genuinely exercised. Going
  # through `delete_idea/1` would re-fetch via `Repo.get/2` and short-
  # circuit into the nil-guard, never reaching `Repo.delete/1` on a
  # stale struct.
  @spec delete_struct_safe(Idea.t()) ::
          {:ok, Idea.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def delete_struct_safe(%Idea{} = idea) do
    Repo.delete(idea)
  rescue
    Ecto.StaleEntryError -> {:error, :not_found}
  end

  # Builds a changeset that surfaces ONLY the controlled "Categoria non
  # valida" error on :categories, while preserving title / description /
  # url so the LV re-render shows what the user typed. We deliberately
  # avoid running `Idea.changeset/2` here — its
  # `validate_at_least_one_category` would add a second error on the
  # same field.
  #
  # `base` defaults to `%Idea{}` for the create path and is the loaded
  # idea for the update path (slice 14), so the form re-render keeps the
  # other fields the user did not retype (duration, budget, location).
  defp build_invalid_categories_changeset(attrs),
    do: build_invalid_categories_changeset(%Idea{}, attrs)

  defp build_invalid_categories_changeset(%Idea{} = base, attrs) do
    base
    |> Ecto.Changeset.cast(attrs, [:title, :description, :url])
    |> Ecto.Changeset.add_error(:categories, Categories.invalid_message())
  end
end
