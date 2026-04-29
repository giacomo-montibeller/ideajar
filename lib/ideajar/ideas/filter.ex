defmodule Ideajar.Ideas.Filter do
  @moduledoc """
  Pure filter composition for ideas listing.

  Slice 6 R5-1 extraction. Previously `apply_filters/2` private in
  `Ideajar.Ideas`; promoted to a public module so we can:

    * unit-test each clause directly without paying a `Repo.preload`
      round-trip on every assertion (see `test/ideajar/ideas/filter_test.exs`)
    * host the 4th clause (`apply_max_cost/2`, slice 6 step 6) without
      growing the context module past its single-responsibility line.

  Slice 6 step 2 was a **conservative extraction**: the 3 existing
  clauses (required, optional, durations) moved verbatim — same subquery
  shapes, same `Enum.uniq` normalization, same NULL-exclusion semantics —
  so the slice-4 SQL-emission pins (`HAVING COUNT(DISTINCT …)`) and the
  slice-5 NULL-exclusion contract (AA7) hold without test changes.

  Slice 6 step 6 adds the 4th clause (`apply_max_cost/2`, BB8) with
  NULL-exclude semantics uniform to the slice-5 durations clause: an
  empty/nil opt is inactive (NULL-cost ideas pass through), a non-nil
  integer threshold emits `WHERE estimated_cost <= ^max AND
  estimated_cost IS NOT NULL` (NULL excluded). The four clauses compose
  in AND across opts.

  Note on the `apply/2` name: it shadows `Kernel.apply/2` syntactically,
  but every caller uses the module-qualified form (`Filter.apply(...)`),
  so Elixir's resolution rules pick this one with no ambiguity. We keep
  the verb-only name to mirror the conventional `apply` chain idiom and
  to avoid renaming cascade across slice 5/6 callers.
  """

  import Ecto.Query

  @doc """
  Composes every active filter clause onto `query` based on `opts`.

  Each clause defaults to its inactive value (empty list, or `nil` for
  scalar opts). Inactive clauses are no-ops — the input query is
  returned unchanged at the SQL layer.

  Accepted opts:

    * `:required` — `[integer]`, AND across category ids (slice 4)
    * `:optional` — `[integer]`, OR across category ids (slice 4)
    * `:durations` — `[atom]`, OR across duration atoms; NULL-duration
      ideas are EXCLUDED when non-empty (slice 5, AA7)
    * `:max_cost` — `integer | nil`; when an integer is given, only
      ideas with `estimated_cost <= ^max AND estimated_cost IS NOT NULL`
      are returned. `nil` (or omitting the opt) leaves NULL-cost ideas
      in the result. NULL-exclude semantics uniform with `:durations`
      (slice 6, BB8).

  Returns a new query — never executes SQL.
  """
  @spec apply(Ecto.Query.t(), keyword()) :: Ecto.Query.t()
  def apply(query, opts) when is_list(opts) do
    query
    |> apply_required(Keyword.get(opts, :required, []))
    |> apply_optional(Keyword.get(opts, :optional, []))
    |> apply_durations(Keyword.get(opts, :durations, []))
    |> apply_max_cost(Keyword.get(opts, :max_cost, nil))
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

  # Cumulative max-budget clause with strict NULL exclusion (BB8).
  # `nil` is inactive (NULL-cost ideas pass through, F12 acceptance).
  # Pattern uniforme with `apply_durations/2`: NULL ideas are excluded
  # when the clause is active, so the AA7-style contract holds across
  # both filterable scalar fields.
  #
  # The `not is_nil(i.estimated_cost)` clause is technically redundant
  # in pure SQL semantics (NULL <= anything evaluates to NULL = falsy
  # in WHERE), but is **explicit for the SQL emission pin (O3)** and
  # **defensive correctness** at the read-site for slice 7+ maintainers
  # extending this clause. We keep both predicates.
  defp apply_max_cost(query, nil), do: query

  defp apply_max_cost(query, max) when is_integer(max) do
    from i in query,
      where: i.estimated_cost <= ^max and not is_nil(i.estimated_cost)
  end
end
