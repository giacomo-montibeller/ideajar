defmodule Ideajar.Geocoding do
  @moduledoc """
  Slice 7a UX rework — server-side forward geocoding (location search).

  Single dispatch path: delegates to `Ideajar.Geocoding.NominatimClient`.
  Test stubbing happens at the HTTP boundary via `Req.Test` (cross-process
  shared name table; works correctly with LiveViewTest's separate LV
  process).

  The full HTTP error mapping (success / empty / 404 / 5xx / network-error
  / JSON-parse / malformed-result filtering) lives in the client module.
  """

  @type result :: %{display_name: String.t(), lat: float(), lng: float()}

  @spec search(String.t()) :: {:ok, [result]} | {:error, :service_unavailable}
  defdelegate search(query), to: Ideajar.Geocoding.NominatimClient
end
