defmodule IdeajarWeb.PwaLayoutTest do
  @moduledoc """
  Slice 10 — root layout PWA discovery tags + service worker
  registration in app.js. The 3 tags live in `<head>` of
  `lib/ideajar_web/components/layouts/root.html.heex`, so any HTML
  response (including `/login`) carries them.
  """
  use IdeajarWeb.ConnCase, async: true

  describe "root layout PWA tags (slice 10)" do
    test "GET /login response body includes <link rel=\"manifest\">", %{conn: conn} do
      conn = get(conn, "/login")
      assert conn.status == 200
      assert conn.resp_body =~ ~s(<link rel="manifest" href="/manifest.json")
    end

    test "GET /login response body includes <meta name=\"theme-color\">", %{conn: conn} do
      conn = get(conn, "/login")
      assert conn.resp_body =~ ~s(<meta name="theme-color" content="#29d")
    end

    test "GET /login response body includes <link rel=\"apple-touch-icon\">", %{conn: conn} do
      conn = get(conn, "/login")
      assert conn.resp_body =~ ~s(<link rel="apple-touch-icon" href="/icons/icon-192.png")
    end

    test "out-of-scope guard: no apple-mobile-web-app-* meta tags",
         %{conn: conn} do
      conn = get(conn, "/login")
      refute conn.resp_body =~ "apple-mobile-web-app-capable"
      refute conn.resp_body =~ "apple-mobile-web-app-status-bar-style"
    end
  end

  describe "service worker registration in app.js (slice 10)" do
    test "app.js gates registration behind the serviceWorker capability check" do
      app_js = File.read!(Path.join(File.cwd!(), "assets/js/app.js"))
      assert app_js =~ ~S{if ("serviceWorker" in navigator)}
    end

    test "app.js registers /sw.js on window.load (DD-S10-5)" do
      app_js = File.read!(Path.join(File.cwd!(), "assets/js/app.js"))

      assert app_js =~ ~S{window.addEventListener("load"}
      assert app_js =~ ~S{navigator.serviceWorker.register("/sw.js")}
    end
  end
end
