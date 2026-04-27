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
end
