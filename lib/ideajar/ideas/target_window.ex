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
end
