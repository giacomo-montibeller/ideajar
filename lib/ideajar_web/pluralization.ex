defmodule IdeajarWeb.Pluralization do
  @moduledoc """
  Tiny Italian pluralization helpers — purposely much smaller than gettext.

  For a 2-user IT-only workspace the canonical UI copy table in
  `docs/conventions.md` is the source of truth; this module only handles
  inflection forms that depend on a runtime count (0/1/many).

  When (if) a non-IT user is added, swap to gettext as a dedicated slice.
  """

  @doc """
  Returns the localized count + noun pair for "ideas" in Italian:

      idee_count(0) #=> "0 idee"
      idee_count(1) #=> "1 idea"
      idee_count(7) #=> "7 idee"

  Raises `FunctionClauseError` for negative integers — counts are
  non-negative by domain.
  """
  @spec idee_count(non_neg_integer()) :: String.t()
  def idee_count(1), do: "1 idea"
  def idee_count(n) when is_integer(n) and n >= 0, do: "#{n} idee"
end
