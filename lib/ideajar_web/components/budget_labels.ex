defmodule IdeajarWeb.Components.BudgetLabels do
  @moduledoc """
  Slice 9 — UI copy IT per il budget slider in due context.

  Il budget slider 0..7 viene renderizzato in DUE posti:

    * **filter row** (`@max_budget_index`): semantica cumulative
      (`max_cost <= X`). Le label leggono "fino a X €".
    * **form aggiunta idea** (`@form_budget_index`): semantica
      single-value (`estimated_cost = X`). Le label sono il valore
      esatto in €, senza prefisso "fino a".

  Lo stesso index ha label diversa nei due context, quindi servono
  due funzioni distinte. Razionale per il modulo nel web layer (NOT in
  `Ideajar.Ideas.Budget`): la prosa IT è UI copy delivery-side.
  Il dominio `Budget` resta puro (values + parse + canonical badge
  label `Budget.label/1`). Pattern parallel a
  `IdeajarWeb.Components.LocationBadge` (rendering) vs
  `Ideajar.Geocoding` (dominio).

  ## Safe-fallback contract

  Out-of-range index (`-1`, `99`) o tipi non-int (`"abc"`, `:atom`,
  `nil`) ritornano la label dell'index 0 (`"Disattivo"` per filter,
  `"Non specificato"` per form). Pattern parallel a
  `Budget.index_to_value/1` clamp.
  """

  @filter_labels %{
    0 => "Disattivo",
    1 => "Gratis",
    2 => "fino a 20€",
    3 => "fino a 50€",
    4 => "fino a 100€",
    5 => "fino a 200€",
    6 => "fino a 500€",
    7 => "oltre 1000€"
  }

  @form_labels %{
    0 => "Non specificato",
    1 => "Gratis",
    2 => "20€",
    3 => "50€",
    4 => "100€",
    5 => "200€",
    6 => "500€",
    7 => "1000+€"
  }

  @doc """
  Filter-context label per il budget slider — semantica cumulative
  (`max_cost <= X`).
  """
  @spec filter(any) :: String.t()
  def filter(n) when is_integer(n) and n in 0..7, do: Map.fetch!(@filter_labels, n)
  def filter(_), do: "Disattivo"

  @doc """
  Form-context label per il budget slider — semantica single-value
  (`estimated_cost = X`).
  """
  @spec form(any) :: String.t()
  def form(n) when is_integer(n) and n in 0..7, do: Map.fetch!(@form_labels, n)
  def form(_), do: "Non specificato"
end
