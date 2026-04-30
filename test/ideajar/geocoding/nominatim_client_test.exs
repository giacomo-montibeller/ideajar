defmodule Ideajar.Geocoding.NominatimClientTest do
  @moduledoc """
  Slice 7a step 2 — real Nominatim HTTP client behaviour.

  Nine canonical RED scenarios cover the spec's response contract
  (O5, S5, S6, CC1, CC3): success, empty body, 404, 5xx, network
  timeout, connect refused, invalid JSON, User-Agent header, and
  URL params. Each test installs its own `Req.Test` stub against
  the canonical `IdeajarStub` name configured in `config/test.exs`.
  """

  use ExUnit.Case, async: true

  alias Ideajar.Geocoding.NominatimClient

  describe "reverse_lookup/2" do
    test "returns {:ok, name} on 200 with display_name" do
      Req.Test.stub(IdeajarStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, ~s({"display_name": "Sirolo, AN"}))
      end)

      assert NominatimClient.reverse_lookup(43.5, 13.6) == {:ok, "Sirolo, AN"}
    end

    test "returns {:error, :no_match} on 200 with no display_name field" do
      Req.Test.stub(IdeajarStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, ~s({}))
      end)

      assert NominatimClient.reverse_lookup(43.5, 13.6) == {:error, :no_match}
    end

    test "returns {:error, :no_match} on 404" do
      Req.Test.stub(IdeajarStub, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      assert NominatimClient.reverse_lookup(43.5, 13.6) == {:error, :no_match}
    end

    test "returns {:error, :service_unavailable} on 5xx" do
      Req.Test.stub(IdeajarStub, fn conn ->
        Plug.Conn.send_resp(conn, 500, "boom")
      end)

      assert NominatimClient.reverse_lookup(43.5, 13.6) == {:error, :service_unavailable}
    end

    test "returns {:error, :service_unavailable} on network timeout" do
      Req.Test.stub(IdeajarStub, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert NominatimClient.reverse_lookup(43.5, 13.6) == {:error, :service_unavailable}
    end

    test "returns {:error, :service_unavailable} on connect refused" do
      Req.Test.stub(IdeajarStub, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert NominatimClient.reverse_lookup(43.5, 13.6) == {:error, :service_unavailable}
    end

    test "returns {:error, :service_unavailable} on invalid JSON body" do
      Req.Test.stub(IdeajarStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, "not json")
      end)

      assert NominatimClient.reverse_lookup(43.5, 13.6) == {:error, :service_unavailable}
    end

    test "sends User-Agent: ideajar/1.0 header" do
      test_pid = self()

      Req.Test.stub(IdeajarStub, fn conn ->
        send(test_pid, {:req_headers, conn.req_headers})

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, ~s({"display_name": "X"}))
      end)

      assert {:ok, "X"} = NominatimClient.reverse_lookup(43.5, 13.6)
      assert_received {:req_headers, headers}

      assert Enum.any?(headers, fn {k, v} ->
               String.downcase(k) == "user-agent" and v == "ideajar/1.0"
             end),
             "Expected User-Agent: ideajar/1.0 in #{inspect(headers)}"
    end

    test "URL contains lat, lon, format=json query params" do
      test_pid = self()

      Req.Test.stub(IdeajarStub, fn conn ->
        send(test_pid, {:request, conn.request_path, conn.query_string})

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, ~s({"display_name": "X"}))
      end)

      assert {:ok, "X"} = NominatimClient.reverse_lookup(43.5, 13.6)
      assert_received {:request, path, query}

      assert path == "/reverse"
      assert query =~ "lat=43.5"
      assert query =~ "lon=13.6"
      assert query =~ "format=json"
    end
  end
end
