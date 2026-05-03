defmodule IdeajarWeb.AssetRoutingTest do
  # Scenario: PWA asset paths are not gated by authentication
  # Step 7 reserves the future PWA asset paths in Plug.Static `only:` so they
  # short-circuit before the router runs, which means they cannot be gated by
  # the :require_auth pipeline regardless of how routes are added later.
  use IdeajarWeb.ConnCase, async: true

  describe "IdeajarWeb.static_paths/0" do
    test "reserves the PWA asset prefixes for slice 9 (manifest, service worker, icons)" do
      paths = IdeajarWeb.static_paths()

      assert "manifest.json" in paths
      assert "sw.js" in paths
      assert "icons" in paths
    end
  end

  describe "PWA asset routes do not redirect to /login when unauthenticated" do
    @pwa_paths [
      "/manifest.json",
      "/sw.js",
      "/icons/icon.png"
    ]

    for path <- @pwa_paths do
      test "GET #{path} (no session) is 200 or 404, never 302 to /login", %{conn: conn} do
        conn = get(conn, unquote(path))

        assert conn.status in [200, 404],
               "expected 200 or 404 for #{unquote(path)}, got #{conn.status}"

        # The crucial property: under no circumstances does a PWA asset path
        # fall through into the :require_auth pipeline.
        assert conn.status != 302
        location = Plug.Conn.get_resp_header(conn, "location")
        refute Enum.any?(location, &String.contains?(&1, "/login"))
      end
    end
  end

  describe "manifest content (slice 10)" do
    test "priv/static/manifest.json exists and parses as valid JSON" do
      path = Path.join(Application.app_dir(:ideajar, "priv"), "static/manifest.json")
      assert File.exists?(path)

      body = File.read!(path)
      assert {:ok, _decoded} = Jason.decode(body)
    end

    test "GET /manifest.json returns 200 + application/json + canonical fields",
         %{conn: conn} do
      conn = get(conn, "/manifest.json")

      assert conn.status == 200

      [content_type | _] = Plug.Conn.get_resp_header(conn, "content-type")
      assert content_type =~ "application/json"

      body = Jason.decode!(conn.resp_body)

      # M1
      assert body["name"] == "Ideajar"
      assert body["short_name"] == "Ideajar"
      # M2
      assert body["description"] == "Idee da fare insieme"
      # M5
      assert body["lang"] == "it"
      assert body["dir"] == "ltr"
      # M3
      assert body["start_url"] == "/"
      assert body["scope"] == "/"
      assert body["display"] == "standalone"
      # M4
      assert body["theme_color"] == "#29d"
      assert body["background_color"] == "#2299dd"
    end

    test "manifest icons array has 192 + 512 maskable PNGs", %{conn: conn} do
      conn = get(conn, "/manifest.json")
      body = Jason.decode!(conn.resp_body)

      # M6
      assert is_list(body["icons"])
      assert length(body["icons"]) == 2

      icon_192 = Enum.find(body["icons"], &(&1["sizes"] == "192x192"))
      assert icon_192["src"] == "/icons/icon-192.png"
      assert icon_192["type"] == "image/png"
      assert icon_192["purpose"] == "any maskable"

      icon_512 = Enum.find(body["icons"], &(&1["sizes"] == "512x512"))
      assert icon_512["src"] == "/icons/icon-512.png"
      assert icon_512["type"] == "image/png"
      assert icon_512["purpose"] == "any maskable"
    end
  end
end
