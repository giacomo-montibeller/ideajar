defmodule IdeajarWeb.IdeaLive.IndexTest do
  use IdeajarWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ideajar.Ideas.Idea
  alias Ideajar.Repo
  alias IdeajarWeb.IdeaLive.Index

  @authenticated_session %{"authenticated" => true}

  defp mount_authenticated(conn) do
    {:ok, view, _html} = live_isolated(conn, Index, session: @authenticated_session)
    view
  end

  defp open_form(view) do
    render_click(view, "toggle_form")
    view
  end

  defp submit(view, attrs) do
    view
    |> form("#idea-form", idea: attrs)
    |> render_submit()
  end

  defp insert_idea!(attrs, %DateTime{} = at) do
    %Idea{}
    |> Map.merge(Map.new(attrs))
    |> Map.put(:inserted_at, at)
    |> Map.put(:updated_at, at)
    |> Repo.insert!()
  end

  describe "mount/3 — auth gate" do
    # Scenario: LiveView mount with no session redirects to /login
    test "redirects to /login when the session has no :authenticated flag", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login?return_to=%2F"}}} =
               live_isolated(conn, Index, session: %{})
    end

    # Scenario: LiveView mount with tampered session is treated as no session
    test "redirects when :authenticated is false", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login?return_to=%2F"}}} =
               live_isolated(conn, Index, session: %{"authenticated" => false})
    end
  end

  describe "mount/3 — authenticated empty workspace" do
    # Scenario: Empty state shows the helpful prompt
    test "renders the add-idea button and the empty state", %{conn: conn} do
      assert {:ok, _view, html} =
               live_isolated(conn, Index, session: @authenticated_session)

      assert html =~ "+ Aggiungi idea"
      assert html =~ ~s(id="add-idea-button")
      assert html =~ "Nessuna idea ancora. Aggiungine una qui sopra."
    end

    # Scenario: Add-idea form is collapsed by default
    test "does not render the form on first mount", %{conn: conn} do
      assert {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      refute html =~ ~s(<form)
      refute html =~ "Salva"
    end

    test "exposes :ideas and :form_visible? in the assigns", %{conn: conn} do
      assert {:ok, view, _html} = live_isolated(conn, Index, session: @authenticated_session)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.ideas == []
      assert assigns.form_visible? == false
    end
  end

  describe "toggle_form / close_form" do
    # Scenario: Clicking the add button expands the form and focuses the title input
    test "expanding the form renders the inputs, the Salva button, and the close icon",
         %{conn: conn} do
      view = mount_authenticated(conn)

      html = render_click(view, "toggle_form")

      assert html =~ ~s(id="idea-title")
      assert html =~ ~s(name="idea[title]")
      assert html =~ ~s(name="idea[description]")
      assert html =~ ~s(name="idea[url]")
      assert html =~ ~s(phx-disable-with="Salvataggio…")
      assert html =~ "Salva"
      assert html =~ ~s(type="button")
      assert html =~ ~s(aria-label="Chiudi")
      assert html =~ ~s(phx-click="close_form")
    end

    # Scenario: Clicking the add button … focuses the title input (A6 push_event)
    test "expanding the form pushes a focus event to #idea-title", %{conn: conn} do
      view = mount_authenticated(conn)

      render_click(view, "toggle_form")

      assert_push_event(view, "ideajar:focus", %{to: "#idea-title"})
    end

    # Scenario: Clicking the close icon collapses the form without saving
    test "close_form hides the form and leaves ideas untouched", %{conn: conn} do
      view = mount_authenticated(conn)
      render_click(view, "toggle_form")

      html = render_click(view, "close_form")

      refute html =~ ~s(id="idea-title")
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.form_visible? == false
      assert assigns.ideas == []
    end

    # Scenario: Reopening the form after close shows empty fields (F7)
    test "re-opening the form re-binds a fresh changeset (no draft persistence)",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_click(view, "toggle_form")
      render_click(view, "close_form")

      reopened_html = render_click(view, "toggle_form")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.form_visible? == true
      assert assigns.form.source.changes == %{}
      assert assigns.form.source.data.title == nil
      assert assigns.form.source.data.description == nil
      assert assigns.form.source.data.url == nil

      # And the rendered HTML does not carry an old typed-in title.
      refute reopened_html =~ ~s(value="Mare a Sirolo")
    end

    # Idempotent toggle (RED #5) — second click is a no-op, stays open
    test "second toggle_form on an already-open form is a no-op", %{conn: conn} do
      view = mount_authenticated(conn)
      render_click(view, "toggle_form")
      assigns_after_first = :sys.get_state(view.pid).socket.assigns
      assert assigns_after_first.form_visible? == true

      html = render_click(view, "toggle_form")
      assigns_after_second = :sys.get_state(view.pid).socket.assigns

      assert assigns_after_second.form_visible? == true
      assert html =~ ~s(id="idea-title")
    end
  end

  describe "save — happy path" do
    # Scenario: Submitting valid input creates the idea, collapses the form,
    # returns focus, and shows a success flash
    test "creates the idea, hides the form, flashes success, focuses the add button",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html =
        submit(view, %{
          title: "Mare a Sirolo",
          description: "Spiaggia delle due Sorelle, partenza presto",
          url: "https://www.parcodelconero.com/sirolo/"
        })

      assert html =~ "Mare a Sirolo"
      assert html =~ "Spiaggia delle due Sorelle, partenza presto"
      assert html =~ ~s(href="https://www.parcodelconero.com/sirolo/")
      assert html =~ ~s(target="_blank")
      assert html =~ ~s(rel="noopener noreferrer")
      assert html =~ ~s(aria-label="Apri link in una nuova scheda")
      assert html =~ "break-all"

      refute html =~ ~s(id="idea-form")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.form_visible? == false
      assert length(assigns.ideas) == 1

      assert_push_event(view, "ideajar:focus", %{to: "#add-idea-button"})

      assert render(view) =~ "Idea aggiunta"
    end

    test "after a successful save, re-opening the form shows empty fields", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      submit(view, %{title: "Cinema stasera"})

      html = render_click(view, "toggle_form")
      refute html =~ ~s(value="Cinema stasera")
    end

    # Scenario: Submitting with only the title creates a minimal idea
    test "title-only idea renders without description or link blocks", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html = submit(view, %{title: "Cinema stasera"})

      assert html =~ "Cinema stasera"
      # `target="_blank"` is unique to the idea-card external link; the layout
      # links never use it, so its absence proves we did not render a link
      # block for this title-only idea.
      refute html =~ ~s(target="_blank")
      refute html =~ "whitespace-pre-wrap"
    end

    # Scenario Outline: Valid links case-insensitive (S5)
    for value <- [
          "http://example.com",
          "https://example.com",
          "HTTPS://example.com",
          "Http://Example.com"
        ] do
      test "renders the verbatim url #{inspect(value)} as the link href", %{conn: conn} do
        view = mount_authenticated(conn) |> open_form()

        html = submit(view, %{title: "Test", url: unquote(value)})

        assert html =~ ~s(href="#{unquote(value)}")
      end
    end

    test "title at the 200-char boundary is accepted", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      title = String.duplicate("a", 200)

      html = submit(view, %{title: title})

      assert html =~ title
      assigns = :sys.get_state(view.pid).socket.assigns
      assert length(assigns.ideas) == 1
    end

    test "url at the 2000-char boundary is accepted", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      url = "https://" <> String.duplicate("a", 1992)
      assert String.length(url) == 2000

      html = submit(view, %{title: "Test", url: url})

      assert html =~ ~s(href="#{url}")
    end

    # Scenario: User input in description is HTML-escaped
    test "renders <script> in description as escaped text", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html = submit(view, %{title: "x", description: "<script>alert(1)</script>"})

      assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
      refute html =~ "<script>alert(1)</script>"
    end

    # Scenario: The Salva button is disabled during submission (phx-disable-with)
    test "Salva button carries phx-disable-with=\"Salvataggio…\"", %{conn: conn} do
      view = mount_authenticated(conn)
      html = render_click(view, "toggle_form")

      assert html =~ ~s(phx-disable-with="Salvataggio…")
    end

    # Scenario: Description newlines are preserved via CSS
    test "description container carries whitespace-pre-wrap", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html = submit(view, %{title: "x", description: "riga 1\nriga 2"})

      assert html =~ "whitespace-pre-wrap"
      assert html =~ "riga 1"
      assert html =~ "riga 2"
    end
  end

  describe "save — validation errors" do
    # Scenario: Submitting an empty title shows the validation error inline
    test "empty title surfaces the canonical message and keeps the form open",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html = submit(view, %{title: ""})

      assert html =~ "Il titolo è obbligatorio"
      assert html =~ ~s(id="idea-title")
      assert html =~ ~s(aria-invalid="true")
      assert html =~ ~s(aria-describedby="idea-title-error")
      assert html =~ ~s(id="idea-title-error")

      assert_push_event(view, "ideajar:focus", %{to: "#idea-title"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.form_visible? == true
      assert assigns.ideas == []
    end

    # F6 — whitespace-only title trimmed
    test "whitespace-only title is rejected with the canonical message", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html = submit(view, %{title: "   "})

      assert html =~ "Il titolo è obbligatorio"
    end

    # Scenario: Submitting a title longer than 200 characters shows the validation error
    test "title longer than 200 chars is rejected", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html = submit(view, %{title: String.duplicate("a", 201)})

      assert html =~ "Il titolo non può superare i 200 caratteri"
    end

    # Scenario: Submitting with both invalid title and invalid url shows both errors
    test "both invalid title and invalid url surface together; focus lands on title",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html = submit(view, %{title: "", url: "ftp://x"})

      assert html =~ "Il titolo è obbligatorio"
      assert html =~ "Il link deve iniziare con http:// o https://"

      assert_push_event(view, "ideajar:focus", %{to: "#idea-title"})
    end

    # url-only invalid → focus jumps to #idea-url
    test "valid title + invalid url surfaces the link error and focuses #idea-url",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html = submit(view, %{title: "Test", url: "ftp://x"})

      assert html =~ "Il link deve iniziare con http:// o https://"
      assert html =~ ~s(id="idea-url")
      assert html =~ ~s(aria-describedby="idea-url-error")

      assert_push_event(view, "ideajar:focus", %{to: "#idea-url"})
    end

    test "url longer than 2000 chars surfaces the canonical too-long message",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html = submit(view, %{title: "Test", url: String.duplicate("h", 2001)})

      assert html =~ "Il link non può superare i 2000 caratteri"
    end

    # Whitespace-only url is trimmed → empty → optional → idea created
    test "whitespace-only url with a valid title is accepted", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html = submit(view, %{title: "Test", url: "   "})

      assert html =~ "Test"
      refute html =~ "Il link deve iniziare"

      assigns = :sys.get_state(view.pid).socket.assigns
      assert length(assigns.ideas) == 1
      assert hd(assigns.ideas).url in [nil, ""]
    end
  end

  describe "routed at /" do
    # Scenario: First visit from a fresh device redirects to /login (no session)
    test "redirects to /login when no session is present", %{conn: conn} do
      conn = get(conn, "/")

      assert redirected_to(conn) == "/login?return_to=%2F"
    end

    # Scenario: Returning device with a valid session lands on the workspace
    test "renders the LiveView home for an authenticated session", %{conn: conn} do
      {:ok, _view, html} =
        conn
        |> init_test_session(%{authenticated: true})
        |> live("/")

      assert html =~ "+ Aggiungi idea"
      assert html =~ "Nessuna idea ancora. Aggiungine una qui sopra."
    end

    # Scenario: A tampered or invalid signed cookie is treated as no session
    test "tampered signed cookie redirects to /login without leaking error info",
         %{conn: conn} do
      login_conn = post(conn, "/login", %{"password" => "correct horse battery staple"})
      assert redirected_to(login_conn) == "/"

      [valid_cookie] =
        login_conn
        |> Plug.Conn.get_resp_header("set-cookie")
        |> Enum.filter(&String.starts_with?(&1, "_ideajar_key="))

      [_, cookie_value | _] = Regex.run(~r/_ideajar_key=([^;]+)/, valid_cookie)

      tampered_value =
        cookie_value
        |> String.slice(0, byte_size(cookie_value) - 4)
        |> Kernel.<>("XXXX")

      tampered_conn =
        build_conn()
        |> Plug.Test.put_req_cookie("_ideajar_key", tampered_value)
        |> get("/")

      assert redirected_to(tampered_conn) =~ ~r{^/login}
      refute (tampered_conn.resp_body || "") =~ ~r/cookie|signature|invalid|tampered/i
    end
  end

  describe "list rendering" do
    # Scenario: Ideas are rendered newest-first
    test "renders ideas with the newest at the top", %{conn: conn} do
      _old = insert_idea!(%{title: "Vecchia"}, ~U[2026-04-26 10:00:00Z])
      _new = insert_idea!(%{title: "Recente"}, ~U[2026-04-27 10:00:00Z])

      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      [recente_at, vecchia_at] =
        for needle <- ["Recente", "Vecchia"] do
          :binary.match(html, needle) |> elem(0)
        end

      assert recente_at < vecchia_at
    end

    # Scenario: Tie-break — equal inserted_at, higher id first
    test "ideas with equal inserted_at are ordered by id descending", %{conn: conn} do
      same = ~U[2026-04-27 10:00:00Z]
      first = insert_idea!(%{title: "First"}, same)
      second = insert_idea!(%{title: "Second"}, same)
      assert second.id > first.id

      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      [second_at, first_at] =
        for needle <- ["Second", "First"] do
          :binary.match(html, needle) |> elem(0)
        end

      assert second_at < first_at
    end
  end
end
