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

  @doc """
  Slice 9 follow-up — reverse-geocode lat/lng to a Nominatim
  `display_name` for the geolocation flow. Used by `set_user_location`
  to label the reference point with the actual address instead of the
  generic "La mia posizione".

  Any failure (HTTP 5xx, malformed body, missing display_name,
  transport error, missing stub) collapses to
  `{:error, :service_unavailable}` so the caller can silently fall
  back to the generic label.
  """
  @spec reverse(float(), float()) :: {:ok, String.t()} | {:error, :service_unavailable}
  defdelegate reverse(lat, lng), to: Ideajar.Geocoding.NominatimClient
end
