defmodule IdeajarWeb.IdeaLive.IndexTest do
  use IdeajarWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias IdeajarWeb.IdeaLive.Index

  @authenticated_session %{"authenticated" => true}

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
end
