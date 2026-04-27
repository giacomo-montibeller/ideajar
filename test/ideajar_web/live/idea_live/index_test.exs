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
