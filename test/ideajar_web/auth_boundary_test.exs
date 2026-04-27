defmodule IdeajarWeb.AuthBoundaryTest do
  @moduledoc """
  Boundary tests for the `:require_auth` pipeline that don't depend on which
  page lives at `/`. They preserve invariants from slice 1 — distinct devices
  carry distinct authentication state, and a successful login persists across
  the next request — even after the home swapped from PageController to a
  LiveView.
  """

  use IdeajarWeb.ConnCase, async: true

  describe "second device is a separate authentication" do
    # Scenario: A second device is a separate authentication
    test "device A authenticated does not authenticate device B" do
      device_a =
        build_conn()
        |> Plug.Test.init_test_session(%{authenticated: true})
        |> get("/")

      assert html_response(device_a, 200) =~ "+ Aggiungi idea"

      device_b = build_conn() |> get("/")
      assert redirected_to(device_b) =~ ~r{^/login}

      device_a_again =
        build_conn()
        |> Plug.Test.init_test_session(%{authenticated: true})
        |> get("/")

      assert html_response(device_a_again, 200) =~ "+ Aggiungi idea"
    end
  end

  describe "session persistence across requests" do
    # Scenario: Successful login grants access and persists across reloads
    test "after successful login the cookie carries authentication to the next request",
         %{conn: conn} do
      login_conn = post(conn, "/login", %{"password" => "correct horse battery staple"})
      assert redirected_to(login_conn) == "/"

      next_conn =
        login_conn
        |> recycle()
        |> get("/")

      assert html_response(next_conn, 200) =~ "+ Aggiungi idea"
    end
  end

  describe "RequireAuth plug on a non-GET request without session" do
    # Scenario: Unauthenticated POST to a protected route is rejected with 403
    test "responds 403 and halts (no redirect)" do
      conn =
        :post
        |> Phoenix.ConnTest.build_conn("/", "")
        |> Plug.Test.init_test_session(%{})
        |> IdeajarWeb.RequireAuth.call([])

      assert conn.status == 403
      assert conn.halted
      refute conn.resp_body =~ ~r/cookie|signature|invalid/i
    end
  end
end
