defmodule Ideajar.Geocoding.NominatimClientTest do
  @moduledoc """
  Slice 7a UX rework — real Nominatim HTTP client behaviour for the
  forward-search endpoint.

  Each test installs its own `Req.Test` stub against the canonical
  `IdeajarStub` name configured in `config/test.exs`. Scenarios cover:
  multi-result success, empty array, 404 → empty, 5xx → service
  unavailable, transport timeout/refused → service unavailable, invalid
  JSON, malformed result filtering, User-Agent header, and URL params.
  """

  use ExUnit.Case, async: true

  alias Ideajar.Geocoding.NominatimClient

  describe "search/1" do
    test "returns {:ok, results} on 200 with multiple well-formed entries" do
      payload =
        Jason.encode!([
          %{"display_name" => "Sirolo, AN", "lat" => "43.5", "lon" => "13.6"},
          %{"display_name" => "Numana, AN", "lat" => "43.51", "lon" => "13.62"},
          %{"display_name" => "Ancona, AN", "lat" => "43.62", "lon" => "13.51"}
        ])

      Req.Test.stub(IdeajarStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, payload)
      end)

      assert {:ok, results} = NominatimClient.search("ancona")
      assert length(results) == 3

      assert Enum.at(results, 0) == %{display_name: "Sirolo, AN", lat: 43.5, lng: 13.6}
      assert Enum.at(results, 1) == %{display_name: "Numana, AN", lat: 43.51, lng: 13.62}
      assert Enum.at(results, 2) == %{display_name: "Ancona, AN", lat: 43.62, lng: 13.51}
    end

    test "returns {:ok, []} on 200 with empty JSON array" do
      Req.Test.stub(IdeajarStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, "[]")
      end)

      assert NominatimClient.search("zzznoresults") == {:ok, []}
    end

    test "returns {:ok, []} on 404 (treat as no results)" do
      Req.Test.stub(IdeajarStub, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      assert NominatimClient.search("anything") == {:ok, []}
    end

    test "returns {:error, :service_unavailable} on 5xx" do
      Req.Test.stub(IdeajarStub, fn conn ->
        Plug.Conn.send_resp(conn, 500, "boom")
      end)

      assert NominatimClient.search("sirolo") == {:error, :service_unavailable}
    end

    test "returns {:error, :service_unavailable} on network timeout" do
      Req.Test.stub(IdeajarStub, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert NominatimClient.search("sirolo") == {:error, :service_unavailable}
    end

    test "returns {:error, :service_unavailable} on connect refused" do
      Req.Test.stub(IdeajarStub, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert NominatimClient.search("sirolo") == {:error, :service_unavailable}
    end

    test "returns {:error, :service_unavailable} on invalid JSON body" do
      Req.Test.stub(IdeajarStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, "not json")
      end)

      assert NominatimClient.search("sirolo") == {:error, :service_unavailable}
    end

    test "filters out results with missing display_name/lat/lon, keeps valid ones" do
      payload =
        Jason.encode!([
          %{"display_name" => "Sirolo, AN", "lat" => "43.5", "lon" => "13.6"},
          # Missing display_name
          %{"lat" => "44.0", "lon" => "14.0"},
          # Missing lat
          %{"display_name" => "X", "lon" => "14.0"},
          # Missing lon
          %{"display_name" => "Y", "lat" => "44.0"},
          %{"display_name" => "Numana, AN", "lat" => "43.51", "lon" => "13.62"}
        ])

      Req.Test.stub(IdeajarStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, payload)
      end)

      assert {:ok, results} = NominatimClient.search("partial")

      assert results == [
               %{display_name: "Sirolo, AN", lat: 43.5, lng: 13.6},
               %{display_name: "Numana, AN", lat: 43.51, lng: 13.62}
             ]
    end

    test "filters out results with non-numeric lat/lon silently" do
      payload =
        Jason.encode!([
          %{"display_name" => "Bad lat", "lat" => "not-a-number", "lon" => "13.6"},
          %{"display_name" => "Bad lon", "lat" => "43.5", "lon" => "abc"},
          %{"display_name" => "Sirolo, AN", "lat" => "43.5", "lon" => "13.6"}
        ])

      Req.Test.stub(IdeajarStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, payload)
      end)

      assert {:ok, results} = NominatimClient.search("mixed")
      assert results == [%{display_name: "Sirolo, AN", lat: 43.5, lng: 13.6}]
    end

    test "sends User-Agent: ideajar/1.0 header" do
      test_pid = self()

      Req.Test.stub(IdeajarStub, fn conn ->
        send(test_pid, {:req_headers, conn.req_headers})

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, "[]")
      end)

      assert {:ok, []} = NominatimClient.search("sirolo")
      assert_received {:req_headers, headers}

      assert Enum.any?(headers, fn {k, v} ->
               String.downcase(k) == "user-agent" and v == "ideajar/1.0"
             end),
             "Expected User-Agent: ideajar/1.0 in #{inspect(headers)}"
    end

    test "URL params include q, format=json, limit=5, accept-language=it with proper encoding" do
      test_pid = self()

      Req.Test.stub(IdeajarStub, fn conn ->
        send(test_pid, {:request, conn.request_path, conn.query_string})

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, "[]")
      end)

      assert {:ok, []} = NominatimClient.search("sirolo conero")
      assert_received {:request, path, query}

      assert path == "/search"
      # Spaces in `q` are URL-encoded by Req's params encoder. Accept either
      # `+` or `%20` to be encoder-agnostic.
      assert query =~ "q=sirolo+conero" or query =~ "q=sirolo%20conero"
      assert query =~ "format=json"
      assert query =~ "limit=5"
      assert query =~ "accept-language=it"
    end
  end
end
