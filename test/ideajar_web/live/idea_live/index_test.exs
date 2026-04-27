defmodule IdeajarWeb.IdeaLive.IndexTest do
  use IdeajarWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias IdeajarWeb.IdeaLive.Index

  @authenticated_session %{"authenticated" => true}

  defp mount_authenticated(conn) do
    {:ok, view, _html} = live_isolated(conn, Index, session: @authenticated_session)
    view
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
end
