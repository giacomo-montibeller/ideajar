defmodule Ideajar.Ideas.DistanceTest do
  @moduledoc """
  Slice 7b step 2 — boundary tests for the pure-Elixir Haversine
  distance calculator (`Ideajar.Ideas.Distance.km/4`). Pins same-point
  zero, equator/meridian degree-to-km baseline, pole-to-pole, antipodal
  half-circumference, real-world city pairs, commutativity, and finite-
  result guarantee on extreme inputs.
  """
  use ExUnit.Case, async: true

  alias Ideajar.Ideas.Distance

  describe "km/4" do
    test "returns 0 for the same point" do
      assert Distance.km(43.5, 13.6, 43.5, 13.6) == 0.0
    end

    test "≈ 111.32 km for 1 degree at the equator (E-W)" do
      assert_in_delta Distance.km(0.0, 0.0, 0.0, 1.0), 111.32, 0.5
    end

    test "≈ 111.32 km for 1 degree of latitude on the meridian (N-S)" do
      assert_in_delta Distance.km(0.0, 0.0, 1.0, 0.0), 111.32, 0.5
    end

    test "≈ 20015 km for pole-to-pole (great circle half)" do
      assert_in_delta Distance.km(90.0, 0.0, -90.0, 0.0), 20_015.0, 10.0
    end

    test "≈ 200 km for Sirolo↔Roma (real-world pair)" do
      # Sirolo (43.5, 13.6) to Roma (41.9, 12.5) ≈ 200 km
      assert_in_delta Distance.km(43.5, 13.6, 41.9, 12.5), 200.0, 10.0
    end

    test "≈ 1050 km for Sirolo↔Parigi (real-world pair)" do
      # Sirolo (43.5, 13.6) to Parigi (48.85, 2.35) ≈ 1050 km great-circle
      assert_in_delta Distance.km(43.5, 13.6, 48.85, 2.35), 1050.0, 50.0
    end

    test "is commutative — km(a,b,c,d) == km(c,d,a,b)" do
      a = Distance.km(43.5, 13.6, 41.9, 12.5)
      b = Distance.km(41.9, 12.5, 43.5, 13.6)

      assert_in_delta a, b, 0.0001
    end

    test "antipodal pair ≈ 20015 km (half of Earth's circumference) and returns finite float" do
      # (0, 0) and (0, 180) are antipodal points on the equator.
      result = Distance.km(0.0, 0.0, 0.0, 180.0)

      assert is_float(result)
      assert_in_delta result, 20_015.0, 10.0
    end
  end
end
