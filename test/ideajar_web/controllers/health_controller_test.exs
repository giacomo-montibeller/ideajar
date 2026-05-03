defmodule IdeajarWeb.HealthControllerTest do
  @moduledoc """
  Slice 11b — `/health` is the endpoint Gigalixir hits as an HTTP probe.
  It must return 200 + JSON without requiring a session, so it bypasses
  the `:require_auth` pipeline. The auth-bypass invariant is pinned
  in parallel with the slice 1 `manifest.json`/`sw.js`/`icons` bypass.
  """
  use IdeajarWeb.ConnCase, async: true

  test "GET /health returns 200 + content-type application/json", %{conn: conn} do
    conn = get(conn, "/health")

    assert conn.status == 200

    [content_type | _] = Plug.Conn.get_resp_header(conn, "content-type")
    assert content_type =~ "application/json"
  end

  test "GET /health body is the canonical {\"status\":\"ok\"} JSON", %{conn: conn} do
    conn = get(conn, "/health")
    assert Jason.decode!(conn.resp_body) == %{"status" => "ok"}
  end

  test "GET /health (no session) does NOT redirect to /login (auth bypass)",
       %{conn: conn} do
    conn = get(conn, "/health")
    assert conn.status == 200
    assert conn.status != 302
    location = Plug.Conn.get_resp_header(conn, "location")
    refute Enum.any?(location, &String.contains?(&1, "/login"))
  end
end
