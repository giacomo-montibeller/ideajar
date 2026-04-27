defmodule IdeajarWeb.PageControllerTest do
  # Scenario: First visit from a fresh device shows the login form
  #   (via redirect from /)
  # Scenario: Returning device with a valid session skips the login form
  # Scenario: Unauthenticated POST to a protected route is rejected with 403
  # Scenario: A tampered or invalid signed cookie is treated as no session
  # Scenario: Successful login grants access and persists across reloads
  use IdeajarWeb.ConnCase, async: true

  describe "GET / (no session)" do
    test "redirects to /login with return_to=/", %{conn: conn} do
      conn = get(conn, "/")

      assert redirected_to(conn) =~ ~r{^/login\?return_to=}
      assert redirected_to(conn) == "/login?return_to=%2F"
    end
  end

  describe "GET / (authenticated)" do
    test "renders the workspace home", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{authenticated: true})
        |> get("/")

      response = html_response(conn, 200)
      assert response =~ "Workspace privato"
    end
  end

  describe "RequireAuth plug on a non-GET request without session" do
    test "responds 403 and halts (no redirect)", _ do
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

  describe "GET / with tampered signed cookie" do
    test "treats tampered cookie as no session, redirects to /login, leaks no error",
         %{conn: conn} do
      # Step 1: complete a successful login to obtain a real signed cookie.
      login_conn = post(conn, "/login", %{"password" => "correct horse battery staple"})
      assert redirected_to(login_conn) == "/"

      [valid_cookie] =
        login_conn
        |> Plug.Conn.get_resp_header("set-cookie")
        |> Enum.filter(&String.starts_with?(&1, "_ideajar_key="))

      # Extract the cookie value (between '=' and the first ';').
      [_, cookie_value | _] = Regex.run(~r/_ideajar_key=([^;]+)/, valid_cookie)

      # Step 2: tamper with the signature by flipping the last 4 chars.
      tampered_value =
        cookie_value
        |> String.slice(0, byte_size(cookie_value) - 4)
        |> Kernel.<>("XXXX")

      # Step 3: present the tampered cookie on a fresh request.
      tampered_conn =
        build_conn()
        |> Plug.Test.put_req_cookie("_ideajar_key", tampered_value)
        |> get("/")

      # Tampered cookie is silently dropped → no session → redirect to /login.
      assert redirected_to(tampered_conn) =~ ~r{^/login}
      assert tampered_conn.status == 302

      # No information leakage about cookie internals.
      body = response_body(tampered_conn)
      refute body =~ ~r/cookie|signature|invalid|tampered/i
    end

    defp response_body(conn) do
      case conn.resp_body do
        body when is_binary(body) -> body
        _ -> ""
      end
    end
  end

  describe "second device is a separate authentication" do
    # Scenario: A second device is a separate authentication
    test "device A authenticated does not authenticate device B", _ do
      device_a =
        build_conn()
        |> Plug.Test.init_test_session(%{authenticated: true})
        |> get("/")

      assert html_response(device_a, 200) =~ "Workspace privato"

      device_b = build_conn() |> get("/")

      assert redirected_to(device_b) =~ ~r{^/login}

      # Re-checking device A after device B's request: still authenticated
      device_a_again =
        build_conn()
        |> Plug.Test.init_test_session(%{authenticated: true})
        |> get("/")

      assert html_response(device_a_again, 200) =~ "Workspace privato"
    end
  end

  describe "session persistence across requests" do
    test "after successful login the cookie carries authentication to the next request",
         %{conn: conn} do
      login_conn = post(conn, "/login", %{"password" => "correct horse battery staple"})
      assert redirected_to(login_conn) == "/"

      # `recycle/1` carries cookies forward into a fresh conn (simulating a
      # second browser request that reuses the Set-Cookie from the login).
      next_conn =
        login_conn
        |> recycle()
        |> get("/")

      response = html_response(next_conn, 200)
      assert response =~ "Workspace privato"
    end
  end
end
