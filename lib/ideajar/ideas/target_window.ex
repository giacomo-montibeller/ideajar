defmodule Ideajar.Ideas.TargetWindow do
  @moduledoc """
  Slice 15 — value-object module for the optional target time window
  ("Quando") attached to an idea.

  An idea may carry zero or one target window. The window has two
  granularities:

    * `:day` — a `start_date..end_date` interval, possibly single-day.
    * `:month` — full-month boundaries (`start.day == 1` and
      `end == Date.end_of_month(end)`). The `weekend_only` flag refines
      the semantics for month-ranges only ("weekend di maggio").

  This module is the single source of truth for:

    * `format/2` — Italian user-facing label, year-omitted iff the whole
      window stays within the same year as today.
    * `validate_changeset/1` — cross-field rules (all-or-nothing, end ≥
      start, month boundaries, weekend coercion). Lives at the changeset
      boundary, parallel to slice-7a's `validate_location_consistency/1`.
    * `from_idea/1` — accessor that derives the value object from a
      `%Ideajar.Ideas.Idea{}`. Returns `nil` when no target is set; raises
      defensively on partial state (which should be unreachable once a
      validated changeset has been persisted).
    * `month_label/1` — italian lowercase month names for `1..12`.
  """

  alias Ideajar.Ideas.Idea

  @months ~w(gennaio febbraio marzo aprile maggio giugno luglio agosto settembre ottobre novembre dicembre)

  @type granularity :: :day | :month
  @type t :: %{
          start: Date.t(),
          end: Date.t(),
          granularity: granularity,
          weekend_only: boolean
        }

  # ── Public API ─────────────────────────────────────────────────────

  @doc "Italian lowercase month name for `1..12`."
  @spec month_label(1..12) :: String.t()
  def month_label(n) when is_integer(n) and n in 1..12, do: Enum.at(@months, n - 1)

  @doc """
  Derives the target-window value object from a persisted idea.

    * Returns `nil` when all 4 target fields are at their empty/default
      state (the no-target case).
    * Returns `%{start, end, granularity, weekend_only}` when the idea
      carries a fully-populated window.
    * Raises `ArgumentError` on partial state (defensive — a valid
      changeset cannot land in this state).
  """
  @spec from_idea(Idea.t()) :: t | nil
  def from_idea(%Idea{
        target_start: nil,
        target_end: nil,
        target_granularity: nil
      }),
      do: nil

  def from_idea(%Idea{
        target_start: %Date{} = s,
        target_end: %Date{} = e,
        target_granularity: g,
        target_weekend_only: w
      })
      when g in [:day, :month] and is_boolean(w) do
    %{start: s, end: e, granularity: g, weekend_only: w}
  end

  def from_idea(%Idea{} = idea) do
    raise ArgumentError,
          "partial target window on idea #{inspect(idea.id)} — fields out of sync. " <>
            "target_start=#{inspect(idea.target_start)}, target_end=#{inspect(idea.target_end)}, " <>
            "target_granularity=#{inspect(idea.target_granularity)}, " <>
            "target_weekend_only=#{inspect(idea.target_weekend_only)}"
  end

  @doc """
  Formats the target window as an Italian user-facing label.

  Year is hidden iff `start.year == end.year == today.year`. Otherwise:

    * same-year (different from today) → year suffix once at the end
    * cross-year → year on each endpoint
  """
  @spec format(t, Date.t()) :: String.t()
  def format(%{granularity: :day} = w, %Date{} = today), do: format_day(w, today)
  def format(%{granularity: :month} = w, %Date{} = today), do: format_month(w, today)

  # ── Day range ──────────────────────────────────────────────────────

  defp format_day(%{start: s, end: e}, today) do
    cond do
      s.year != e.year ->
        # Cross-year: full date on each endpoint.
        "#{s.day} #{month_label(s.month)} #{s.year} - #{e.day} #{month_label(e.month)} #{e.year}"

      s == e ->
        with_optional_year("#{s.day} #{month_label(s.month)}", s.year, today.year)

      s.month == e.month ->
        with_optional_year(
          "#{s.day}-#{e.day} #{month_label(s.month)}",
          s.year,
          today.year
        )

      true ->
        with_optional_year(
          "#{s.day} #{month_label(s.month)} - #{e.day} #{month_label(e.month)}",
          s.year,
          today.year
        )
    end
  end

  # ── Month range ────────────────────────────────────────────────────

  defp format_month(%{start: s, end: e, weekend_only: weekend?}, today) do
    cond do
      s.year != e.year ->
        format_month_cross_year(s, e, weekend?)

      s.month == e.month ->
        with_optional_year(
          if(weekend?, do: "weekend di #{month_label(s.month)}", else: month_label(s.month)),
          s.year,
          today.year
        )

      true ->
        body =
          if weekend? do
            "weekend tra #{month_label(s.month)} e #{month_label(e.month)}"
          else
            "#{month_label(s.month)}-#{month_label(e.month)}"
          end

        with_optional_year(body, s.year, today.year)
    end
  end

  defp format_month_cross_year(s, e, true) do
    "weekend tra #{month_label(s.month)} #{s.year} e #{month_label(e.month)} #{e.year}"
  end

  defp format_month_cross_year(s, e, false) do
    "#{month_label(s.month)} #{s.year} - #{month_label(e.month)} #{e.year}"
  end

  # ── Year visibility ────────────────────────────────────────────────

  defp with_optional_year(body, year, today_year) when year == today_year, do: body
  defp with_optional_year(body, year, _today_year), do: "#{body} #{year}"

  # ── Validation ─────────────────────────────────────────────────────

  @end_before_start "La data di fine deve essere uguale o successiva alla data di inizio"
  @target_invalid "Periodo non valido"

  @doc """
  Cross-field validation for the target-window tuple.

  Rules:

    * All-or-nothing on `(target_start, target_end, target_granularity)`.
      Partial state surfaces a single `:target` error.
    * `target_end >= target_start` (specific error on `:target_end`).
    * `granularity == :month` → `start.day == 1` AND
      `end == Date.end_of_month(end)` (otherwise `:target` error).
    * `granularity == :day` → `target_weekend_only` is silently coerced
      to `false` (the flag is meaningful only for month-ranges).

  Reads via `get_field/2` so it sees both persisted values and pending
  changes. Writes coercions via `put_change/3`.
  """
  @spec validate_changeset(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_changeset(%Ecto.Changeset{} = cs) do
    s = Ecto.Changeset.get_field(cs, :target_start)
    e = Ecto.Changeset.get_field(cs, :target_end)
    g = Ecto.Changeset.get_field(cs, :target_granularity)

    case {s, e, g} do
      {nil, nil, nil} ->
        cs

      {%Date{} = s, %Date{} = e, g} when g in [:day, :month] ->
        cs
        |> validate_end_after_start(s, e)
        |> validate_month_boundaries(s, e, g)
        |> coerce_weekend_only(g)

      _ ->
        Ecto.Changeset.add_error(cs, :target, @target_invalid)
    end
  end

  defp validate_end_after_start(cs, s, e) do
    if Date.compare(e, s) == :lt do
      Ecto.Changeset.add_error(cs, :target_end, @end_before_start)
    else
      cs
    end
  end

  defp validate_month_boundaries(cs, _s, _e, :day), do: cs

  defp validate_month_boundaries(cs, %Date{day: 1} = s, e, :month) do
    if e == Date.end_of_month(e) do
      cs
    else
      _ = s
      Ecto.Changeset.add_error(cs, :target, @target_invalid)
    end
  end

  defp validate_month_boundaries(cs, _s, _e, :month) do
    Ecto.Changeset.add_error(cs, :target, @target_invalid)
  end

  defp coerce_weekend_only(cs, :day),
    do: Ecto.Changeset.put_change(cs, :target_weekend_only, false)

  defp coerce_weekend_only(cs, :month), do: cs
end
