defmodule Ideajar.GeocodingTest do
  @moduledoc """
  Slice 7a UX rework — verifies the thin `Ideajar.Geocoding` defdelegate
  wrapper exposes `search/1` and dispatches to
  `Ideajar.Geocoding.NominatimClient` through the canonical `Req.Test`
  stubbing seam (`IdeajarStub`).
  """

  use ExUnit.Case, async: true

  describe "search/1" do
    test "is exported with arity 1" do
      Code.ensure_loaded!(Ideajar.Geocoding)
      assert function_exported?(Ideajar.Geocoding, :search, 1)
    end

    test "delegates to NominatimClient and returns parsed results via Req.Test stub" do
      Req.Test.stub(IdeajarStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!([
            %{"display_name" => "Sirolo, AN", "lat" => "43.5", "lon" => "13.6"}
          ])
        )
      end)

      assert {:ok, [%{display_name: "Sirolo, AN", lat: 43.5, lng: 13.6}]} =
               Ideajar.Geocoding.search("sirolo")
    end
  end
end
