defmodule IdeajarWeb.EndpointTest do
  # Acceptance F3 (cookie hardening) + O4 (redeploy survival via cookie-layer
  # round-trip — avoids OTP-level endpoint stop/start fragility per design
  # review).
  use ExUnit.Case, async: true

  describe "session_options/0 — hardening always on" do
    test "uses the cookie store" do
      assert Keyword.get(IdeajarWeb.Endpoint.session_options(), :store) == :cookie
    end

    test "marks cookies HttpOnly" do
      assert Keyword.get(IdeajarWeb.Endpoint.session_options(), :http_only) == true
    end

    test "sets SameSite=Lax" do
      assert Keyword.get(IdeajarWeb.Endpoint.session_options(), :same_site) == "Lax"
    end

    test "sets max_age to 10 years (315_360_000 seconds)" do
      assert Keyword.get(IdeajarWeb.Endpoint.session_options(), :max_age) == 315_360_000
    end

    test "uses cookie name '_ideajar_key'" do
      assert Keyword.get(IdeajarWeb.Endpoint.session_options(), :key) == "_ideajar_key"
    end

    test "has a stable signing_salt (so cookies survive deploys)" do
      salt = Keyword.get(IdeajarWeb.Endpoint.session_options(), :signing_salt)
      assert is_binary(salt)
      assert byte_size(salt) >= 8
    end
  end

  describe "production session config (read from config/prod.exs)" do
    test "config/prod.exs sets secure: true on :session_options" do
      prod_config = Config.Reader.read!("config/prod.exs", env: :prod)

      session_opts = get_in(prod_config, [:ideajar, :session_options])
      assert is_list(session_opts), "expected :session_options to be configured in prod"
      assert Keyword.get(session_opts, :secure) == true
    end
  end

  describe "redeploy survival (cookie-layer round-trip)" do
    test "session signed by one Plug.Session instance is decodable by a fresh one with the same secret_key_base and signing_salt" do
      secret = IdeajarWeb.Endpoint.config(:secret_key_base)

      # First "process": init Plug.Session, sign a session with :authenticated => true
      opts_a = Plug.Session.init(IdeajarWeb.Endpoint.session_options())

      conn_a =
        :get
        |> Phoenix.ConnTest.build_conn("/", "")
        |> Map.put(:secret_key_base, secret)
        |> Plug.Session.call(opts_a)
        |> Plug.Conn.fetch_session()
        |> Plug.Conn.put_session(:authenticated, true)
        |> Plug.Conn.send_resp(200, "")

      [set_cookie] =
        conn_a
        |> Plug.Conn.get_resp_header("set-cookie")
        |> Enum.filter(&String.starts_with?(&1, "_ideajar_key="))

      [_, cookie_value | _] = Regex.run(~r/_ideajar_key=([^;]+)/, set_cookie)

      # Second "process": completely fresh init of Plug.Session with the same
      # config and the same secret — proves the cookie does not depend on any
      # per-instance state beyond `secret_key_base` + `signing_salt`.
      opts_b = Plug.Session.init(IdeajarWeb.Endpoint.session_options())

      conn_b =
        :get
        |> Phoenix.ConnTest.build_conn("/", "")
        |> Map.put(:secret_key_base, secret)
        |> Plug.Test.put_req_cookie("_ideajar_key", cookie_value)
        |> Plug.Session.call(opts_b)
        |> Plug.Conn.fetch_session()

      assert Plug.Conn.get_session(conn_b, :authenticated) == true,
             "session signed by process A must be readable by process B with the same secret"
    end
  end
end
