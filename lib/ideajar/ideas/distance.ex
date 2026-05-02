defmodule Ideajar.Ideas.Distance do
  @moduledoc """
  Pure Haversine great-circle distance between two coordinates.

  Returns the distance in kilometres assuming a spherical Earth of radius
  6371 km. The Haversine formula is symmetric, monotonic in angular
  separation, and well-conditioned for the small-to-medium distances we
  expect (≤ a few thousand km between user-set reference points and
  ideas in the catalog).

  Used by `Ideajar.Ideas.Filter.apply_post/2` (slice 7b) to filter the
  in-memory list of ideas after the SQL query path runs. SQLite has no
  native Haversine and the fallback fragment requires the math
  extensions (≥3.35), so doing the work in Elixir keeps the dependency
  surface flat at the price of an O(N) post-query pass — acceptable
  while N ≤ a few hundred ideas.
  """
  @earth_radius_km 6371.0

  @spec km(number(), number(), number(), number()) :: float()
  def km(lat1, lng1, lat2, lng2) do
    lat1_rad = deg_to_rad(lat1)
    lat2_rad = deg_to_rad(lat2)
    dlat = deg_to_rad(lat2 - lat1)
    dlng = deg_to_rad(lng2 - lng1)

    a =
      :math.sin(dlat / 2) ** 2 +
        :math.cos(lat1_rad) * :math.cos(lat2_rad) * :math.sin(dlng / 2) ** 2

    c = 2 * :math.asin(min(1.0, :math.sqrt(a)))

    @earth_radius_km * c
  end

  defp deg_to_rad(deg), do: deg * :math.pi() / 180.0
end
