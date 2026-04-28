defmodule Ideajar.Ideas.Duration do
  @moduledoc """
  Whitelist canonica per il campo `duration` delle idee (slice 5).

  Single source of truth condivisa da:

    * lo schema `Ideajar.Ideas.Idea` (campo `Ecto.Enum, values: Duration.values()`),
    * il toggle del form `DurationChip`,
    * il toggle del filter chip,
    * il catchall sulle stringhe ostili in arrivo dal client.

  Le label sono copy IT risolte per atom; non possono mai contenere caratteri
  HTML speciali (vedi pin XSS-via-atom in `DurationTest`).

  Compile-order: questo modulo deve compilare prima di `Ideajar.Ideas.Idea`,
  che chiama `Duration.values/0` a compile-time per parametrizzare l'enum.
  L'ordine è gestito automaticamente dal grafo di dipendenze del compiler
  Elixir.
  """

  @values [:poche_ore, :mezza_giornata, :giornata, :weekend, :piu_giorni]

  @labels %{
    poche_ore: "poche ore",
    mezza_giornata: "mezza giornata",
    giornata: "giornata",
    weekend: "weekend",
    piu_giorni: "più giorni"
  }

  @doc """
  Whitelist canonica delle durate nell'ordine di display.
  """
  @spec values() :: [atom]
  def values, do: @values

  @doc """
  Tenta di convertire un input grezzo (tipicamente una stringa proveniente
  dal client) in uno degli atom canonici.

  Comportamento:

    * stringa non vuota appartenente alla whitelist → `{:ok, atom}`
    * stringa non vuota che NON è un atom esistente o non è in whitelist → `:error`
    * stringa vuota, `nil`, o qualsiasi altro tipo → `:error`

  Usa `String.to_existing_atom/1` dentro `try/rescue` per non sollevare se
  l'attaccante invia una stringa che non corrisponde a nessun atom in
  memoria.
  """
  @spec parse(any) :: {:ok, atom} | :error
  def parse(raw) when is_binary(raw) and raw != "" do
    atom = String.to_existing_atom(raw)
    if atom in @values, do: {:ok, atom}, else: :error
  rescue
    ArgumentError -> :error
  end

  def parse(_), do: :error

  @doc """
  Restituisce la label IT user-facing per un atom canonico.

  Solleva `KeyError` se l'atom non è in whitelist; questa è una guardia
  contro chiamanti che bypassano `parse/1`.
  """
  @spec label(atom) :: String.t()
  def label(atom) when atom in @values, do: Map.fetch!(@labels, atom)
end
