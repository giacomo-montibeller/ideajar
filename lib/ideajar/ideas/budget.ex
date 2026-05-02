defmodule Ideajar.Ideas.Budget do
  @moduledoc """
  Whitelist canonica per il campo `estimated_cost` delle idee (slice 6).

  Single source of truth condivisa da:

    * lo schema `Ideajar.Ideas.Idea` (campo `:integer` con
      `validate_inclusion(:estimated_cost, Budget.values())`),
    * il toggle del form `BudgetChip`,
    * il toggle del filter chip,
    * il catchall sulle stringhe ostili in arrivo dal client.

  Le label sono copy IT mappate per intero non possono mai contenere caratteri
  HTML speciali (vedi pin XSS-via-bucket in `BudgetTest`).

  Diversamente da `Ideajar.Ideas.Duration` (che usa `Ecto.Enum` su atom),
  qui i valori canonici sono interi: `0` per "gratis", `20-500` per i tetti
  intermedi, `1000` come bucket open-ended "oltre". La whitelist è applicata
  lato changeset via `validate_inclusion/3`; il `parse/1` di questo modulo
  serve come gate ai confini del sistema (toggle form, filter chip).
  """

  @values [0, 20, 50, 100, 200, 500, 1000]

  @labels %{
    0 => "gratis",
    20 => "fino a 20€",
    50 => "fino a 50€",
    100 => "fino a 100€",
    200 => "fino a 200€",
    500 => "fino a 500€",
    1000 => "oltre 1000€"
  }

  @doc """
  Whitelist canonica dei budget bucket nell'ordine di display.
  """
  @spec values() :: [non_neg_integer]
  def values, do: @values

  @doc """
  Tenta di convertire un input grezzo (tipicamente una stringa proveniente
  dal client) in uno degli interi canonici.

  Comportamento:

    * stringa intera positiva interamente parseabile e in whitelist → `{:ok, n}`
    * stringa numerica fuori whitelist o con suffissi non vuoti → `:error`
    * stringa non numerica, vuota, `nil`, o qualsiasi altro tipo → `:error`

  Non solleva mai: gli input ostili tornano sempre `:error` (S4).
  """
  @spec parse(any) :: {:ok, non_neg_integer} | :error
  def parse(raw) when is_binary(raw) and raw != "" do
    case Integer.parse(raw) do
      {n, ""} -> if n in @values, do: {:ok, n}, else: :error
      _ -> :error
    end
  end

  def parse(_), do: :error

  @doc """
  Restituisce la label IT user-facing per un bucket canonico.

  Solleva `KeyError` se l'intero non è in whitelist; questa è una guardia
  contro chiamanti che bypassano `parse/1`.
  """
  @spec label(non_neg_integer) :: String.t()
  def label(value) when value in @values, do: Map.fetch!(@labels, value)

  @index_to_value %{1 => 0, 2 => 20, 3 => 50, 4 => 100, 5 => 200, 6 => 500, 7 => 1000}

  @doc """
  Slice 9 — mappa l'index del budget slider 0..7 al valore canonical
  integer. Index 0 → `nil` (filter inactive / form unspecified).
  Index 1..7 → integer in `[0, 20, 50, 100, 200, 500, 1000]`.

  Out-of-range integer e qualsiasi altro tipo (binary, atom, float, ecc.)
  → `nil` (safe-fallback). NON solleva, NON ritorna `:error`. Il return
  type contract è `integer | nil` puro così che ogni caller (es.
  `derive_filter_opts/1`, `maybe_inject_budget/2`) possa passare il
  risultato direttamente a `Filter.apply_max_cost/2` o `Map.put/3` senza
  case-on-:error guards.
  """
  @spec index_to_value(any) :: integer | nil
  def index_to_value(0), do: nil
  def index_to_value(n) when is_integer(n) and n in 1..7, do: Map.fetch!(@index_to_value, n)
  def index_to_value(_), do: nil
end
