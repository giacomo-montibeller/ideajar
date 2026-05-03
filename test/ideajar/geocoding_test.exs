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

  describe "reverse/2 (slice 9 follow-up — geolocation reverse-geocode label)" do
    test "is exported with arity 2" do
      Code.ensure_loaded!(Ideajar.Geocoding)
      assert function_exported?(Ideajar.Geocoding, :reverse, 2)
    end

    test "200 + display_name → {:ok, display_name}" do
      Req.Test.stub(IdeajarStub, fn conn ->
        assert conn.request_path =~ "/reverse"

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "display_name" => "Sirolo, Provincia di Ancona, Marche, 60020, Italia",
            "lat" => "43.5",
            "lon" => "13.6"
          })
        )
      end)

      assert {:ok, "Sirolo, Provincia di Ancona, Marche, 60020, Italia"} =
               Ideajar.Geocoding.reverse(43.5, 13.6)
    end

    test "5xx → {:error, :service_unavailable}" do
      Req.Test.stub(IdeajarStub, fn conn ->
        Plug.Conn.send_resp(conn, 503, "down")
      end)

      assert {:error, :service_unavailable} = Ideajar.Geocoding.reverse(43.5, 13.6)
    end

    test "200 + body without display_name → {:error, :service_unavailable}" do
      Req.Test.stub(IdeajarStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"error" => "Unable to geocode"}))
      end)

      assert {:error, :service_unavailable} = Ideajar.Geocoding.reverse(43.5, 13.6)
    end

    test "missing stub or transport error → {:error, :service_unavailable} (defensive)" do
      # No stub installed — Req.Test plug will raise. The client must
      # convert the exception to the canonical error so the LV handler
      # can fall back to 'La mia posizione' without crashing.
      assert {:error, :service_unavailable} = Ideajar.Geocoding.reverse(43.5, 13.6)
    end
  end
end
