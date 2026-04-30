defmodule Ideajar.Geocoding do
  @moduledoc """
  Slice 7a — server-side reverse geocoding wrapper.

  Single dispatch path: delegates to `Ideajar.Geocoding.NominatimClient`.
  Test stubbing happens at the HTTP boundary via `Req.Test` (cross-process
  shared name table; works correctly with LiveViewTest's separate LV
  process).

  The full HTTP error mapping (success / no-match / 5xx / network-error /
  JSON-parse) lands in step 2 of slice 7a. Step 1 only wires up the
  module surface and the `Req.Test` plug seam used by the rest of the
  slice.
  """

  @spec reverse_lookup(float, float) ::
          {:ok, String.t()} | {:error, :no_match | :service_unavailable}
  defdelegate reverse_lookup(lat, lng), to: Ideajar.Geocoding.NominatimClient
end
