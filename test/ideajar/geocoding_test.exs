defmodule Ideajar.GeocodingTest do
  @moduledoc """
  Slice 7a step 1 — verifies the thin `Ideajar.Geocoding` defdelegate
  wrapper exists and dispatches to `Ideajar.Geocoding.NominatimClient`
  through the canonical `Req.Test` stubbing seam (`IdeajarStub`).
  """

  use ExUnit.Case, async: true

  describe "reverse_lookup/2" do
    test "is exported with arity 2" do
      Code.ensure_loaded!(Ideajar.Geocoding)
      assert function_exported?(Ideajar.Geocoding, :reverse_lookup, 2)
    end

    test "delegates to NominatimClient and returns {:ok, name} via Req.Test stub" do
      Req.Test.stub(IdeajarStub, fn conn ->
        Plug.Conn.send_resp(conn, 200, ~s({"display_name": "Test"}))
      end)

      assert {:ok, "Test"} = Ideajar.Geocoding.reverse_lookup(43.5, 13.6)
    end
  end
end
