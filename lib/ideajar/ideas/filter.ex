defmodule Ideajar.Ideas.Filter do
  @moduledoc """
  Filter composition for the ideas listing — **dual-layer contract**.

  The filter pipeline operates in two layers:

    1. **Query layer** — `apply/2` composes Ecto subqueries on top of
       the input `Ecto.Query.t()`, returning a new query. SQL emission
       is pinned by `Ecto.Adapters.SQL.to_sql/2`. Active across slices
       4-6 (required/optional/durations/max_cost). Cheap, indexable,
       SQL-native.
    2. **Post-query layer** — `apply_post/2` operates on the in-memory
       `[Idea.t()]` list AFTER `Repo.all` + `Repo.preload`. Reserved
       for filters that don't translate cleanly to SQL on SQLite
       without optional extensions, e.g. Haversine great-circle
       distance (slice 7b `apply_max_distance/2`). The cost is O(N)
       per query — acceptable while N is small.

  The two layers compose: `Ideas.list_ideas/1` runs `apply/2` first,
  then `Repo.all`, then `Repo.preload`, then `apply_post/2`. Each opt
  belongs to exactly one layer (no opt is consulted twice).

  ## Slice 6 R5-1 extraction history

  Previously `apply_filters/2` was private in `Ideajar.Ideas`. Promoted
  to a public module so we can:

    * unit-test each clause directly without paying a `Repo.preload`
      round-trip on every assertion (see `test/ideajar/ideas/filter_test.exs`)
    * host the 4th query clause (`apply_max_cost/2`, slice 6 step 6)
      without growing the context module past its single-responsibility
      line.

  Slice 6 step 2 was a **conservative extraction**: the 3 existing
  clauses (required, optional, durations) moved verbatim — same subquery
  shapes, same `Enum.uniq` normalization, same NULL-exclusion semantics —
  so the slice-4 SQL-emission pins (`HAVING COUNT(DISTINCT …)`) and the
  slice-5 NULL-exclusion contract (AA7) hold without test changes.

  Slice 6 step 6 adds the 4th query clause (`apply_max_cost/2`, BB8)
  with NULL-exclude semantics uniform to the slice-5 durations clause:
  an empty/nil opt is inactive (NULL-cost ideas pass through), a non-nil
  integer threshold emits `WHERE estimated_cost <= ^max AND
  estimated_cost IS NOT NULL` (NULL excluded). The four query clauses
  compose in AND across opts.

  Slice 7b step 3 introduces the post-query layer with one clause
  (`apply_max_distance/2`). Trigger to extract a dedicated
  `Ideajar.Ideas.Filter.PostQuery` module: ≥3 post-query clauses
  cohabiting (rule of 3).

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
    |> apply_text_search(Keyword.get(opts, :text_search, nil))
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

  # Slice 8 — text-search clause. Case-insensitive substring match on
  # title OR description. Active only for binaries of ≥ 3 chars (server-
  # side authoritative; UI may also debounce/min-length, but this guard
  # is the contract).
  #
  # ## NULL-description exception (DD-S8-4)
  #
  # Slice 5 (durata), 6 (budget), 7b (distanza) uniformly EXCLUDE NULL-
  # field ideas when their filter is active. Slice 8 is the documented
  # exception: a NULL `description` does not auto-exclude an idea — the
  # match can still happen on `title`. Implementation: `description IS
  # NOT NULL AND LOWER(description) LIKE ...` is gated explicitly so
  # the SQL three-valued logic is unambiguous, while `title` (NOT NULL
  # in the schema) needs no such guard. The two predicates are joined
  # with `OR` so a title-only match still passes.
  #
  # ## LIKE wildcard escape (DD-S8-3)
  #
  # User input is wrapped in `%...%` to behave as a substring search.
  # Literal `%`, `_`, and `\` characters in the input are escaped via
  # `escape_like/1` and the SQL `ESCAPE '\'` clause so they remain
  # literal characters and do NOT bypass the substring semantics.
  # Without this, a user typing `%` would match every idea.
  #
  # ## Elixir → SQL byte mapping (DD-S8-2, iter1 review B1 fix)
  #
  # Elixir source `"\\"` is 1 byte runtime `\`. SQLite ESCAPE requires
  # exactly 1 byte. The fragment template uses Elixir source
  # `"ESCAPE '\\'"` (4 chars: `'`, `\`, `\`, `'`) which produces SQL
  # `ESCAPE '\'` (escape char is the single byte `\`). Do NOT use
  # `"ESCAPE '\\\\'"` — that produces SQL `ESCAPE '\\'` (2 bytes) and
  # SQLite raises `ESCAPE expression must be a single character`.
  defp apply_text_search(query, nil), do: query

  defp apply_text_search(query, q) when is_binary(q) and byte_size(q) < 3, do: query

  defp apply_text_search(query, q) when is_binary(q) do
    pattern = "%" <> escape_like(q) <> "%"

    from i in query,
      where:
        fragment("LOWER(?) LIKE LOWER(?) ESCAPE '\\'", i.title, ^pattern) or
          fragment(
            "? IS NOT NULL AND LOWER(?) LIKE LOWER(?) ESCAPE '\\'",
            i.description,
            i.description,
            ^pattern
          )
  end

  defp apply_text_search(query, _), do: query

  # Escape order matters: `\` must be escaped first so that the
  # backslash-prefixed forms produced for `%` and `_` are NOT
  # double-escaped.
  defp escape_like(s) when is_binary(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  @doc """
  Composes every active **post-query** filter clause onto `ideas` based
  on `opts`. Operates on the in-memory list returned by `Repo.all` +
  `Repo.preload`.

  Reserved for filters that cannot be expressed cleanly in SQL on
  SQLite without optional extensions. Slice 7b's only clause is
  `apply_max_distance/2` (Haversine great-circle distance via
  `Ideajar.Ideas.Distance.km/4`).

  Accepted opts:

    * `:max_distance_km` — `integer | nil`; when an integer is given,
      keeps only ideas whose `lat`/`lng` are non-nil AND within
      `max_distance_km` of the reference point. `nil` (or omitting
      the opt) leaves the list unchanged. The reference point is
      passed via the coordinated opts `:ref_lat` / `:ref_lng`; if
      either is `nil`, the clause silently no-ops (DD5 defensive).
    * `:ref_lat` — `float | nil`; required for the distance filter
      to take effect.
    * `:ref_lng` — `float | nil`; required for the distance filter
      to take effect.

  ### NULL-exclude semantics (DD4)

  Index 0 of the slider maps to `max_distance_km: nil` → filter
  inactive, NULL-coord ideas pass through. Indices 1-5 map to a
  finite km value → filter active, NULL-coord ideas excluded.
  Index 6 maps to `1_000_000` → filter active with effectively no
  upper cap, but NULL-coord ideas STILL excluded (the difference
  between index 0 and index 6 is exactly the NULL treatment).

  Returns a new list — never executes SQL.
  """
  @spec apply_post([Ideajar.Ideas.Idea.t()], keyword()) :: [Ideajar.Ideas.Idea.t()]
  def apply_post(ideas, opts) when is_list(ideas) and is_list(opts) do
    apply_max_distance(ideas, opts)
  end

  # Post-query clause: keep only ideas whose stored coords are within
  # `max_km` of the reference point. NULL-coord ideas (lat or lng nil)
  # are excluded when the clause is active. The clause silently no-ops
  # if `max_distance_km`, `ref_lat`, or `ref_lng` is nil — the
  # LiveView's slider is disabled until a reference point is set, so
  # the no-op is the contract for both the "no slider" and "no ref
  # point" states.
  defp apply_max_distance(ideas, opts) do
    max_km = Keyword.get(opts, :max_distance_km)
    ref_lat = Keyword.get(opts, :ref_lat)
    ref_lng = Keyword.get(opts, :ref_lng)

    if is_number(max_km) and is_number(ref_lat) and is_number(ref_lng) do
      Enum.filter(ideas, fn idea ->
        is_number(idea.lat) and is_number(idea.lng) and
          Ideajar.Ideas.Distance.km(idea.lat, idea.lng, ref_lat, ref_lng) <= max_km
      end)
    else
      ideas
    end
  end
end
