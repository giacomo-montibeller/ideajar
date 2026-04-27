defmodule IdeajarWeb.LoginControllerTest do
  # Scenario: First visit from a fresh device shows the login form
  # Scenario: Login form is accessible and password-manager-friendly
  # Scenario: Already authenticated visit to /login redirects home
  # Acceptance: P3 (no DB hit on login render)
  use IdeajarWeb.ConnCase, async: true

  describe "GET /login (no session)" do
    test "renders the login form with all accessibility attributes", %{conn: conn} do
      conn = get(conn, "/login")
      response = html_response(conn, 200)

      # Page title and helper text (UI copy)
      assert response =~ "ideajar — accesso"
      assert response =~ "Inserisci la password condivisa per questo dispositivo."

      # Visible heading
      assert response =~ ~r/<h1[^>]*>\s*ideajar\s*<\/h1>/

      # Label associated with the password input
      assert response =~ ~r/<label[^>]+for="password"[^>]*>\s*Password\s*<\/label>/

      # Password input with full a11y / password-manager attributes
      assert response =~ ~r/<input[^>]*\bid="password"[^>]*>/
      assert response =~ ~r/<input[^>]*\bname="password"[^>]*>/
      assert response =~ ~r/<input[^>]*\btype="password"[^>]*>/
      assert response =~ ~r/<input[^>]*\bautocomplete="current-password"[^>]*>/
      assert response =~ ~r/<input[^>]*\bautofocus[^>]*>/
      assert response =~ ~r/<input[^>]*\brequired[^>]*>/
      assert response =~ ~r/<input[^>]*\baria-describedby="login-error"[^>]*>/

      # Error region for screen-reader announcement
      assert response =~ ~r/<[^>]+id="login-error"[^>]*role="alert"[^>]*>/

      # Submit button labelled "Entra"
      assert response =~ ~r/<button[^>]*type="submit"[^>]*>\s*Entra\s*<\/button>/

      # Form posts to /login
      assert response =~ ~r/<form[^>]*method="post"[^>]*action="\/login"[^>]*>/

      # CSRF protection
      assert response =~ ~r/<input[^>]*type="hidden"[^>]*name="_csrf_token"[^>]*>/

      # Hidden return_to with empty value (no query param)
      assert response =~ ~r/<input[^>]*type="hidden"[^>]*name="return_to"[^>]*value=""[^>]*>/
    end

    test "preserves return_to from query string in the hidden input", %{conn: conn} do
      conn = get(conn, "/login?return_to=/some/protected/path")
      response = html_response(conn, 200)

      assert response =~
               ~r/<input[^>]*name="return_to"[^>]*value="\/some\/protected\/path"[^>]*>/
    end
  end

  describe "GET /login (already authenticated)" do
    test "redirects to / without showing the form", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{authenticated: true})
        |> get("/login")

      assert redirected_to(conn) == "/"
    end
  end

  describe "GET /login — P3: no database hit" do
    test "rendering the form does not query the database", %{conn: conn} do
      test_pid = self()
      handler_id = "test-no-db-hit-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:ideajar, :repo, :query],
        fn _event, _measurements, _metadata, _config -> send(test_pid, :db_hit) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      conn = get(conn, "/login")
      assert html_response(conn, 200)
      refute_received :db_hit, 100
    end
  end

  describe "POST /login (correct password)" do
    # Scenario: Successful login grants access and persists across reloads
    test "redirects to / and marks session :authenticated", %{conn: conn} do
      conn = post(conn, "/login", %{"password" => "correct horse battery staple"})

      assert redirected_to(conn) == "/"
      assert get_session(conn, :authenticated) == true
    end

    # Scenario: Login preserves the originally requested path
    test "honors a safe return_to and redirects there", %{conn: conn} do
      conn =
        post(conn, "/login", %{
          "password" => "correct horse battery staple",
          "return_to" => "/some/protected/path"
        })

      assert redirected_to(conn) == "/some/protected/path"
      assert get_session(conn, :authenticated) == true
    end

    # Scenario Outline: return_to is rejected when it points outside the app
    test "ignores an external return_to and redirects to /", _ do
      for evil <- ["https://evil.com", "//evil.com", "http://evil.com", "javascript:alert(1)", ""] do
        conn = build_conn()

        conn =
          post(conn, "/login", %{
            "password" => "correct horse battery staple",
            "return_to" => evil
          })

        assert redirected_to(conn) == "/", "expected '/' for return_to=#{inspect(evil)}"
        assert get_session(conn, :authenticated) == true
      end
    end
  end

  describe "POST /login (wrong password)" do
    # Scenario: Wrong password shows a generic error and does not authenticate
    test "renders generic error and does not authenticate", %{conn: conn} do
      conn = post(conn, "/login", %{"password" => "wrong"})

      response = html_response(conn, 200)

      # Generic IT error inside the role=alert region
      assert response =~ "Password errata"
      assert response =~ ~r/<[^>]+id="login-error"[^>]*role="alert"[^>]*>[^<]*Password errata/

      # Form is still on the page, autofocus still on password
      assert response =~ ~r/<input[^>]*\bautofocus[^>]*>/

      # Password value MUST NOT be echoed back into the input
      refute response =~ ~r/<input[^>]*type="password"[^>]*value="wrong"/

      # No session set
      assert get_session(conn, :authenticated) == nil
    end

    # Scenario: Empty password submission is treated as a wrong password
    test "empty password is treated as wrong", %{conn: conn} do
      conn = post(conn, "/login", %{"password" => ""})

      response = html_response(conn, 200)
      assert response =~ "Password errata"
      assert get_session(conn, :authenticated) == nil
    end

    # Scenario: Repeated wrong passwords behave consistently
    test "10 wrong then 1 correct — only the 11th authenticates", _ do
      Enum.each(1..10, fn _ ->
        conn = post(build_conn(), "/login", %{"password" => "wrong#{:rand.uniform(99)}"})
        assert html_response(conn, 200) =~ "Password errata"
        assert get_session(conn, :authenticated) == nil
      end)

      conn = post(build_conn(), "/login", %{"password" => "correct horse battery staple"})
      assert redirected_to(conn) == "/"
      assert get_session(conn, :authenticated) == true
    end

    # Scenario: Wrong password is never written to logs
    test "submitted password is never written to logs", %{conn: conn} do
      sentinel = "sentinel-leakage-canary-xyz"

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          post(conn, "/login", %{"password" => sentinel})
        end)

      refute log =~ sentinel
    end
  end
end
