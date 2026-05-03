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

  describe "icons binary (slice 10)" do
    # PNG chunk-scan parser (DD-S10-2). Robust vs PNG variants that
    # may interleave ancillary chunks (tEXt/iTXt/pHYs) before IHDR.
    # Spec: 8-byte magic, then a sequence of chunks {len::32, type::4-bytes,
    # data::size(len)-bytes, crc::32}. IHDR is always 13 bytes wide:
    # width::32 + height::32 + 5 bytes of bit-depth/color-type/etc.
    defp png_dimensions(<<137, 80, 78, 71, 13, 10, 26, 10, rest::binary>>),
      do: find_ihdr(rest)

    defp find_ihdr(<<13::32, "IHDR", w::32, h::32, _crc::32, _::binary>>),
      do: {w, h}

    defp find_ihdr(<<len::32, _type::4-bytes, _data::size(len)-bytes, _crc::32, rest::binary>>),
      do: find_ihdr(rest)

    defp icon_path(name) do
      Path.join(Application.app_dir(:ideajar, "priv"), "static/icons/#{name}")
    end

    test "icon-192.png exists with PNG magic + 192×192 dimensions" do
      path = icon_path("icon-192.png")
      assert File.exists?(path)

      data = File.read!(path)
      assert byte_size(data) > 0
      # A8 magic
      assert <<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>> = data
      # A8 dimensions via chunk scan
      assert {192, 192} = png_dimensions(data)
    end

    test "icon-512.png exists with PNG magic + 512×512 dimensions" do
      path = icon_path("icon-512.png")
      assert File.exists?(path)

      data = File.read!(path)
      assert byte_size(data) > 0
      assert <<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>> = data
      assert {512, 512} = png_dimensions(data)
    end

    test "GET /icons/icon-192.png returns 200 + image/png", %{conn: conn} do
      conn = get(conn, "/icons/icon-192.png")
      assert conn.status == 200
      [content_type | _] = Plug.Conn.get_resp_header(conn, "content-type")
      assert content_type =~ "image/png"
    end

    test "GET /icons/icon-512.png returns 200 + image/png", %{conn: conn} do
      conn = get(conn, "/icons/icon-512.png")
      assert conn.status == 200
      [content_type | _] = Plug.Conn.get_resp_header(conn, "content-type")
      assert content_type =~ "image/png"
    end

    test "priv/scripts/generate_icons.sh exists and is executable" do
      path = Path.join(File.cwd!(), "priv/scripts/generate_icons.sh")
      assert File.exists?(path)

      stat = File.stat!(path)
      # Owner-execute bit (mode & 0o100 != 0).
      assert Bitwise.band(stat.mode, 0o100) != 0
    end
  end
end
