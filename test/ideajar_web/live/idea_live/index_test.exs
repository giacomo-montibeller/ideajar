defmodule IdeajarWeb.IdeaLive.IndexTest do
  use IdeajarWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ideajar.Categories.Category
  alias Ideajar.CategoriesFixtures
  alias Ideajar.Ideas.Duration
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

  defp toggle_chip(view, name) do
    cat = CategoriesFixtures.category_by_name!(name)
    render_click(view, "toggle_category", %{"id" => "#{cat.id}"})
    view
  end

  # Slice-2-era tests use this helper: it pre-selects "mare" so the
  # submit satisfies the slice-3 "min: 1 category" rule without forcing
  # every test author to think about chip selection. Slice-3 tests that
  # test the categories rule itself use `submit_no_chip/2` or set their
  # own chips explicitly via `toggle_chip/2`.
  defp submit(view, attrs) do
    view
    |> toggle_chip("mare")
    |> form_submit(attrs)
  end

  defp submit_no_chip(view, attrs), do: form_submit(view, attrs)

  defp form_submit(view, attrs) do
    view
    |> form("#idea-form", idea: attrs)
    |> render_submit()
  end

  defp insert_idea_with_categories!(title, category_names, %DateTime{} = at) do
    cats = Enum.map(category_names, &CategoriesFixtures.category_by_name!/1)

    idea =
      %Idea{title: title}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:categories, cats)
      |> Repo.insert!()

    Repo.update!(
      Ecto.Changeset.change(idea, inserted_at: at, updated_at: at),
      force: true
    )
  end

  # Extract the inner HTML of the idea-categories badge list so positional
  # assertions can disambiguate badge order from chip occurrences in the
  # form. Avoids the brittleness of using List.last on raw binary matches.
  defp idea_card_badges_html(html) do
    case Regex.run(~r{<ul[^>]*data-testid="idea-categories"[^>]*>(.*?)</ul>}s, html) do
      [_, inner] -> inner
      _ -> ""
    end
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
      # Description block is gated by data-testid so we don't depend on
      # Tailwind class names for behaviour assertions.
      refute html =~ ~s(data-testid="idea-description")
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
    test "description block is rendered and preserves the newline content",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html = submit(view, %{title: "x", description: "riga 1\nriga 2"})

      assert html =~ ~s(data-testid="idea-description")
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

  describe "save — repo failure (S6)" do
    # Scenario: Repo write failure surfaces a generic flash without crashing
    test "an unexpected persistence failure shows a flash and keeps the form open",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      # Inject a deterministic failure for create_idea/1 — the LiveView
      # exposes a test seam via socket assigns that defaults to the real
      # context call.
      :sys.replace_state(view.pid, fn state ->
        socket =
          Phoenix.Component.assign(
            state.socket,
            :create_idea_fun,
            fn _attrs -> {:error, :db_unavailable} end
          )

        %{state | socket: socket}
      end)

      html =
        submit(view, %{
          title: "Mare a Sirolo",
          description: "Spiaggia",
          url: "https://example.com"
        })

      assert html =~ "Salvataggio non riuscito, riprova"
      # Phoenix scaffold renders error flashes with role="alert" — pinned
      # explicitly so a future template tweak cannot quietly downgrade it.
      assert html =~ ~s(role="alert")

      # Form remains visible and pre-populated with the user's input.
      assert html =~ ~s(id="idea-form")
      assert html =~ ~s(value="Mare a Sirolo")

      # And the LiveView is still alive.
      assert Process.alive?(view.pid)
    end

    test "the success flash sits in an aria-live polite region (A12)", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html = submit(view, %{title: "x"})

      assert html =~ "Idea aggiunta"
      assert html =~ ~s(aria-live="polite")
    end
  end

  describe "list rendering" do
    # Scenario: Ideas are rendered newest-first
    test "renders ideas with the newest at the top", %{conn: conn} do
      _old = insert_idea_with_categories!("Vecchia", ["mare"], ~U[2026-04-26 10:00:00Z])
      _new = insert_idea_with_categories!("Recente", ["mare"], ~U[2026-04-27 10:00:00Z])

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
      first_id = insert_idea_with_categories!("First", ["mare"], same).id
      second_id = insert_idea_with_categories!("Second", ["mare"], same).id
      assert second_id > first_id

      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      [second_at, first_at] =
        for needle <- ["Second", "First"] do
          :binary.match(html, needle) |> elem(0)
        end

      assert second_at < first_at
    end

    # Scenario: Idea card renders its categories in display_order
    test "idea card renders category badges in display_order ASC", %{conn: conn} do
      # cinema=7, cultura=6 → cultura should appear before cinema in the card
      insert_idea_with_categories!(
        "Cinema stasera",
        ["cinema", "cultura"],
        ~U[2026-04-27 10:00:00Z]
      )

      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      card = idea_card_badges_html(html)
      cultura_at = :binary.match(card, "cultura") |> elem(0)
      cinema_at = :binary.match(card, "cinema") |> elem(0)
      assert cultura_at < cinema_at
    end

    # Scenario: An idea with all 8 categories renders all 8 badges in display_order
    test "idea card with all 8 categories renders every badge in display_order ASC",
         %{conn: conn} do
      all_names = [
        "passeggiata",
        "mare",
        "museo",
        "ristorante",
        "sport",
        "cultura",
        "cinema",
        "viaggio"
      ]

      insert_idea_with_categories!("Tutto", all_names, ~U[2026-04-27 10:00:00Z])

      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)
      card = idea_card_badges_html(html)

      # Each name appears in the card. Take their first occurrence inside the
      # card region and assert the order matches the canonical display_order.
      positions =
        Enum.map(all_names, fn name ->
          {pos, _len} = :binary.match(card, name)
          {name, pos}
        end)

      assert Enum.map(positions, &elem(&1, 0)) == all_names
      assert positions |> Enum.map(&elem(&1, 1)) |> then(&(&1 == Enum.sort(&1)))
    end

    # Scenario: User input is HTML-escaped on render — category names too (S1)
    test "S1 — a category whose name contains HTML is escaped on render",
         %{conn: conn} do
      # Bypass the seed: insert a synthetic category with HTML-like name and
      # tag a fresh idea with it, so the render exercises the escape both in
      # the chip (form) and the badge (card).
      naughty =
        Repo.insert!(%Category{
          name: "<script>alert(1)</script>",
          display_order: 999
        })

      idea =
        %Idea{title: "Naughty"}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:categories, [naughty])
        |> Repo.insert!()

      _ = idea

      {:ok, view, html} = live_isolated(conn, Index, session: @authenticated_session)

      # Card renders the category badge: must be escaped, must NOT contain
      # the raw <script> tag.
      assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
      refute html =~ "<script>alert(1)</script>"

      # Same check inside the chip group: open the form and confirm the
      # synthetic chip name is escaped there too.
      form_html = render_click(view, "toggle_form")
      assert form_html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
      refute form_html =~ "<script>alert(1)</script>"
    end
  end

  # ── Slice 3: chip rendering and toggle ────────────────────────────
  describe "categories — chip rendering and toggle" do
    # Scenario: Opening the form shows all 8 categories as toggleable chips
    test "opening the form renders the fieldset, legend with required marker, and 8 chips",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render_click(view, "toggle_form")

      assert html =~ ~s(<legend )
      assert html =~ "Categorie"
      assert html =~ ~s(<span aria-hidden="true">*</span>)
      assert html =~ "Scegli almeno una categoria"

      for {_ord, name} <- [
            {1, "passeggiata"},
            {2, "mare"},
            {3, "museo"},
            {4, "ristorante"},
            {5, "sport"},
            {6, "cultura"},
            {7, "cinema"},
            {8, "viaggio"}
          ] do
        assert html =~ name
      end

      # Default state: all chips deselected.
      assert html =~ ~s(aria-pressed="false")
      assert html =~ ~s(data-selected="false")
      refute html =~ ~s(aria-pressed="true")
      refute html =~ ~s(data-selected="true")
    end

    # Scenario: Each chip toggles its aria-pressed state on click
    test "clicking a chip toggles aria-pressed and data-selected, and adds the check icon",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      mare = CategoriesFixtures.category_by_name!("mare")

      html = render_click(view, "toggle_category", %{"id" => "#{mare.id}"})

      assert html =~ ~s(category-chip-#{mare.id})
      assert html =~ ~s(aria-pressed="true")
      assert html =~ ~s(data-selected="true")
      # The hero-check icon appears only on selected chips.
      assert html =~ "hero-check"

      assigns = :sys.get_state(view.pid).socket.assigns
      assert MapSet.member?(assigns.selected_category_ids, mare.id)

      html2 = render_click(view, "toggle_category", %{"id" => "#{mare.id}"})

      assigns2 = :sys.get_state(view.pid).socket.assigns
      refute MapSet.member?(assigns2.selected_category_ids, mare.id)
      refute html2 =~ ~s(aria-pressed="true")
    end

    # Scenario: Multiple chips can be selected at once
    test "selecting multiple chips records each in selected_category_ids", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      view
      |> toggle_chip("mare")
      |> toggle_chip("museo")
      |> toggle_chip("viaggio")

      assigns = :sys.get_state(view.pid).socket.assigns
      ids = MapSet.to_list(assigns.selected_category_ids)
      assert length(ids) == 3
    end

    # F6 — Reset on close+reopen
    test "closing then reopening the form resets selected_category_ids", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form() |> toggle_chip("mare")

      assigns_after_select = :sys.get_state(view.pid).socket.assigns
      assert MapSet.size(assigns_after_select.selected_category_ids) == 1

      render_click(view, "close_form")
      render_click(view, "toggle_form")

      assigns_after_reopen = :sys.get_state(view.pid).socket.assigns
      assert MapSet.equal?(assigns_after_reopen.selected_category_ids, MapSet.new())
    end

    # W8: hostile / malformed phx-value-id is a silent no-op
    test "toggle_category with a non-integer id is a no-op", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      render_click(view, "toggle_category", %{"id" => "not-an-int"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert MapSet.equal?(assigns.selected_category_ids, MapSet.new())
      assert Process.alive?(view.pid)
    end
  end

  # ── Slice 3: save flow with categories ────────────────────────────
  describe "save — categories validation (slice 3)" do
    # Scenario: Submitting with no category selected shows the validation error
    test "no chip selected surfaces the canonical error and pushes focus to error region",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html = submit_no_chip(view, %{title: "Cinema stasera"})

      assert html =~ "Seleziona almeno una categoria"
      assert html =~ ~s(id="idea-categories-error")
      assert html =~ ~s(role="alert")
      # tabindex="-1" lets the server-driven focus push land here without
      # adding it to the natural Tab order.
      assert html =~ ~s(tabindex="-1")

      assert_push_event(view, "ideajar:focus", %{to: "#idea-categories-error"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.form_visible? == true
      assert assigns.ideas == []
    end

    # Scenario: Errors accumulate; focus targets #idea-title (priority)
    test "title-empty + url-invalid + no-chip surfaces all errors; focus on #idea-title",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html = submit_no_chip(view, %{title: "", url: "ftp://x"})

      assert html =~ "Il titolo è obbligatorio"
      assert html =~ "Il link deve iniziare con http:// o https://"
      assert html =~ "Seleziona almeno una categoria"

      assert_push_event(view, "ideajar:focus", %{to: "#idea-title"})
    end

    # Scenario: A toggled-then-untoggled chip submits as no category
    test "toggling a chip on then off submits as no category", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      view |> toggle_chip("mare") |> toggle_chip("mare")

      html = form_submit(view, %{title: "x"})

      assert html =~ "Seleziona almeno una categoria"
    end

    # F8 — recovery: title/url preserved between failed and successful submits
    test "categories-only error preserves title and url for the recovery submit",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html =
        submit_no_chip(view, %{title: "Sirolo", url: "https://example.com"})

      assert html =~ "Seleziona almeno una categoria"
      # The form re-render shows the user's typed values still in the inputs.
      assert html =~ ~s(value="Sirolo")
      assert html =~ ~s(value="https://example.com")

      view |> toggle_chip("mare")
      html2 = form_submit(view, %{title: "Sirolo", url: "https://example.com"})

      assert html2 =~ "Idea aggiunta"

      assigns = :sys.get_state(view.pid).socket.assigns
      assert length(assigns.ideas) == 1
      idea = hd(assigns.ideas)
      assert idea.title == "Sirolo"
      assert idea.url == "https://example.com"
      assert Enum.map(idea.categories, & &1.name) == ["mare"]
    end

    # Happy path that exercises chip selection + idea card badges
    test "submitting with two chips renders the badges in display_order on the card",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      view |> toggle_chip("mare") |> toggle_chip("viaggio")

      html = form_submit(view, %{title: "Mare a Sirolo"})

      # mare=2, viaggio=8 → mare appears first in the badges list
      assert html =~ "Mare a Sirolo"
      card = idea_card_badges_html(html)
      mare_at = :binary.match(card, "mare") |> elem(0)
      viaggio_at = :binary.match(card, "viaggio") |> elem(0)
      assert mare_at < viaggio_at
    end

    # F7 — chips reset after successful save
    test "after successful save, reopening the form clears chip selection",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      view |> toggle_chip("mare")
      form_submit(view, %{title: "Saved"})

      render_click(view, "toggle_form")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert MapSet.equal?(assigns.selected_category_ids, MapSet.new())
    end
  end

  # ── Slice 3: out-of-scope guard + auth boundary ───────────────────
  describe "out-of-scope and auth boundary" do
    # Scenario: There is no UI to manage categories
    test "the form does not expose any category management UI", %{conn: conn} do
      view = mount_authenticated(conn)
      html = render_click(view, "toggle_form")

      refute html =~ ~r/(Aggiungi|Modifica|Elimina|Gestisci) categori[ae]/i

      # Only `toggle_category` should be a categories-related phx-click.
      categories_clicks =
        Regex.scan(~r/phx-click="([^"]*categor[^"]*)"/i, html)
        |> Enum.map(&Enum.at(&1, 1))
        |> Enum.uniq()

      assert categories_clicks == ["toggle_category"]
    end

    # S4 — Auth boundary: unauthenticated mount cannot reach chip form
    test "session-empty mount redirects even with the new event handlers in place",
         %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login?return_to=%2F"}}} =
               live_isolated(conn, Index, session: %{})
    end

    # S4 — Module API surface: Categories exposes only read-only functions
    test "Ideajar.Categories module exposes only list_categories and list_by_ids" do
      exported = Ideajar.Categories.__info__(:functions) |> Enum.map(&elem(&1, 0))

      refute :create_category in exported
      refute :update_category in exported
      refute :delete_category in exported
      assert :list_categories in exported
      assert :list_by_ids in exported
    end
  end

  # Belt-and-suspenders: the schema still exposes the same module API as
  # before so a future refactor doesn't accidentally break the boundary.
  describe "Category schema is referenced via the Categories context" do
    test "Idea.__schema__(:association, :categories).related is Ideajar.Categories.Category" do
      assoc = Idea.__schema__(:association, :categories)
      assert assoc.related == Category
    end
  end

  # ── Slice 4: cycle_filter + clear_filters handlers + @filter_state ──
  describe "cycle_filter handler (slice 4)" do
    test "mount initializes @filter_state to %{}", %{conn: conn} do
      view = mount_authenticated(conn)
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.filter_state == %{}
    end

    # Scenario: Clicking a chip cycles off → optional → required → off
    test "first click sets state to :optional", %{conn: conn} do
      view = mount_authenticated(conn)
      mare = CategoriesFixtures.category_by_name!("mare")

      render_click(view, "cycle_filter", %{"id" => "#{mare.id}"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.filter_state[mare.id] == :optional
    end

    test "second click sets state to :required", %{conn: conn} do
      view = mount_authenticated(conn)
      mare = CategoriesFixtures.category_by_name!("mare")

      render_click(view, "cycle_filter", %{"id" => "#{mare.id}"})
      render_click(view, "cycle_filter", %{"id" => "#{mare.id}"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.filter_state[mare.id] == :required
    end

    test "third click removes the id (back to off)", %{conn: conn} do
      view = mount_authenticated(conn)
      mare = CategoriesFixtures.category_by_name!("mare")

      Enum.each(1..3, fn _ -> render_click(view, "cycle_filter", %{"id" => "#{mare.id}"}) end)

      assigns = :sys.get_state(view.pid).socket.assigns
      refute Map.has_key?(assigns.filter_state, mare.id)
    end

    # F6 rapid cycle pin: 5 clicks → :required (5 mod 3 = 2 transitions: off→optional→required)
    test "5 rapid consecutive clicks land on :required", %{conn: conn} do
      view = mount_authenticated(conn)
      mare = CategoriesFixtures.category_by_name!("mare")

      Enum.each(1..5, fn _ -> render_click(view, "cycle_filter", %{"id" => "#{mare.id}"}) end)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.filter_state[mare.id] == :required
    end

    # S1 hostile inputs scenario outline
    for value <- ["abc", "", "-1", "0", "1.5", "99999999"] do
      test "cycle_filter with hostile id #{inspect(value)} is a no-op", %{conn: conn} do
        view = mount_authenticated(conn)

        render_click(view, "cycle_filter", %{"id" => unquote(value)})

        assigns = :sys.get_state(view.pid).socket.assigns
        assert assigns.filter_state == %{}
        assert Process.alive?(view.pid)
      end
    end

    test "cycle_filter with no params is a no-op", %{conn: conn} do
      view = mount_authenticated(conn)
      render_click(view, "cycle_filter", %{})
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.filter_state == %{}
      assert Process.alive?(view.pid)
    end
  end

  # ── Slice 4 fixture for filter tests in LV ─────────────────────────
  defp seed_5_lv_ideas do
    %{
      sirolo:
        insert_idea_with_categories!("Sirolo", ["mare", "viaggio"], ~U[2026-04-27 10:00:00Z]),
      uffizi:
        insert_idea_with_categories!("Uffizi", ["museo", "cultura"], ~U[2026-04-27 10:01:00Z]),
      stadio: insert_idea_with_categories!("Stadio", ["sport"], ~U[2026-04-27 10:02:00Z]),
      bagno: insert_idea_with_categories!("Bagno", ["mare", "sport"], ~U[2026-04-27 10:03:00Z]),
      cinema:
        insert_idea_with_categories!("Cinema", ["cinema", "cultura"], ~U[2026-04-27 10:04:00Z])
    }
  end

  defp cycle_filter(view, name) do
    cat = CategoriesFixtures.category_by_name!(name)
    render_click(view, "cycle_filter", %{"id" => "#{cat.id}"})
    view
  end

  describe "filter row template (slice 4)" do
    # Scenario: Visiting / with no filter shows every idea
    test "renders every idea when filter is inactive", %{conn: conn} do
      _ = seed_5_lv_ideas()
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      for title <- ["Sirolo", "Uffizi", "Stadio", "Bagno", "Cinema"] do
        assert html =~ title
      end
    end

    # Scenario: Filter chip wiring
    test "renders 8 filter chips with correct phx-click and phx-value-id wiring",
         %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      # 8 filter chips with stable id pattern
      filter_chip_ids =
        Regex.scan(~r/id="(filter-chip-\d+)"/, html) |> Enum.map(&Enum.at(&1, 1))

      assert length(filter_chip_ids) == 8
      assert filter_chip_ids == Enum.uniq(filter_chip_ids)

      # Each chip has phx-click="cycle_filter"
      cycle_count = Regex.scan(~r/phx-click="cycle_filter"/, html) |> length()
      assert cycle_count == 8
    end

    # A8 — DOM id distinct: form chip and filter chip don't collide
    test "form-chip and filter-chip have distinct DOM ids when form is open",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      html = render(view)

      cat_chips = Regex.scan(~r/id="category-chip-\d+"/, html) |> length()
      flt_chips = Regex.scan(~r/id="filter-chip-\d+"/, html) |> length()
      assert cat_chips == 8
      assert flt_chips == 8

      # No id is shared between the two — collect all ids and check uniqueness
      all_ids =
        Regex.scan(~r/id="((?:category|filter)-chip-\d+)"/, html)
        |> Enum.map(&Enum.at(&1, 1))

      assert all_ids == Enum.uniq(all_ids)
      assert length(all_ids) == 16
    end

    # A7 — Discoverability helper text
    test "filter row contains the discoverability helper text", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)
      assert html =~ "Tocca per filtrare: 1× opzionale · 2× obbligatoria · 3× rimuovi"
    end

    # A17 — Visual row labels
    test "filter row has visible 'Filtra per:' label", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)
      assert html =~ "Filtra per:"
    end

    test "form retains the 'Categorie *' legend with required asterisk", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      html = render(view)
      assert html =~ ~r/Categorie\s*<span aria-hidden="true">\*</
    end
  end

  describe "filter applied to list (slice 4)" do
    test "single optional chip filters list", %{conn: conn} do
      _ = seed_5_lv_ideas()
      {:ok, view, _html} = live_isolated(conn, Index, session: @authenticated_session)

      html = view |> cycle_filter("sport") |> render()

      assert html =~ "Stadio"
      assert html =~ "Bagno"
      refute html =~ "Sirolo"
      refute html =~ "Uffizi"
    end

    test "multiple optional chips OR-combine", %{conn: conn} do
      _ = seed_5_lv_ideas()
      {:ok, view, _html} = live_isolated(conn, Index, session: @authenticated_session)

      html = view |> cycle_filter("sport") |> cycle_filter("cultura") |> render()

      assert html =~ "Stadio"
      assert html =~ "Bagno"
      assert html =~ "Uffizi"
      assert html =~ "Cinema"
      refute html =~ "Sirolo"
    end

    test "single required chip (2 cycles) filters AND", %{conn: conn} do
      _ = seed_5_lv_ideas()
      {:ok, view, _html} = live_isolated(conn, Index, session: @authenticated_session)

      html = view |> cycle_filter("mare") |> cycle_filter("mare") |> render()

      assert html =~ "Sirolo"
      assert html =~ "Bagno"
      refute html =~ "Stadio"
    end

    test "mixed required + optional applies both clauses", %{conn: conn} do
      _ = seed_5_lv_ideas()
      {:ok, view, _html} = live_isolated(conn, Index, session: @authenticated_session)

      html =
        view
        |> cycle_filter("mare")
        |> cycle_filter("mare")
        |> cycle_filter("sport")
        |> cycle_filter("cultura")
        |> render()

      assert html =~ "Bagno"
      refute html =~ "Sirolo"
      refute html =~ "Uffizi"
    end

    # Scenario: Filter matching zero ideas shows the empty-result state
    test "empty result shows 'Nessuna idea per i filtri attivi.' + funnel icon + inline Mostra tutte",
         %{conn: conn} do
      # Seed only ideas without "passeggiata" tag
      _ = seed_5_lv_ideas()
      {:ok, view, _html} = live_isolated(conn, Index, session: @authenticated_session)

      html = view |> cycle_filter("passeggiata") |> cycle_filter("passeggiata") |> render()

      assert html =~ ~s(data-testid="empty-filter-state")
      assert html =~ "Nessuna idea per i filtri attivi."
      assert html =~ "hero-funnel"
      assert html =~ ~s(id="mostra-tutte-empty")

      # The default workspace-empty state is NOT shown
      refute html =~ "Nessuna idea ancora. Aggiungine una qui sopra."
    end
  end

  describe "Mostra tutte single-instance placement (A10/F10)" do
    test "filter inactive: zero Mostra tutte buttons", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)
      count = Regex.scan(~r/Mostra tutte/, html) |> length()
      assert count == 0
    end

    test "filter active + non-empty list: exactly one Mostra tutte under filter row",
         %{conn: conn} do
      _ = seed_5_lv_ideas()
      {:ok, view, _html} = live_isolated(conn, Index, session: @authenticated_session)

      html = view |> cycle_filter("sport") |> render()

      count = Regex.scan(~r/Mostra tutte/, html) |> length()
      assert count == 1
      assert html =~ ~s(id="mostra-tutte")
      refute html =~ ~s(id="mostra-tutte-empty")
    end

    test "filter active + empty list: exactly one Mostra tutte inside empty-filter state",
         %{conn: conn} do
      _ = seed_5_lv_ideas()
      {:ok, view, _html} = live_isolated(conn, Index, session: @authenticated_session)

      html = view |> cycle_filter("passeggiata") |> cycle_filter("passeggiata") |> render()

      count = Regex.scan(~r/Mostra tutte/, html) |> length()
      assert count == 1
      assert html =~ ~s(id="mostra-tutte-empty")
      refute html =~ ~s(id="mostra-tutte")
    end

    test "click Mostra tutte resets filter and shows all ideas", %{conn: conn} do
      _ = seed_5_lv_ideas()
      {:ok, view, _html} = live_isolated(conn, Index, session: @authenticated_session)

      view |> cycle_filter("mare")
      html = render_click(view, "clear_filters")

      for title <- ["Sirolo", "Uffizi", "Stadio", "Bagno", "Cinema"] do
        assert html =~ title
      end
    end

    test "workspace-empty state is distinct from empty-filter state (A9)", %{conn: conn} do
      # No ideas seeded, no filter
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      assert html =~ "Nessuna idea ancora. Aggiungine una qui sopra."
      refute html =~ ~s(data-testid="empty-filter-state")
    end
  end

  describe "form/filter state isolation (A8)" do
    test "cycle_filter does not affect @selected_category_ids of the form", %{conn: conn} do
      _ = seed_5_lv_ideas()
      view = mount_authenticated(conn) |> open_form() |> toggle_chip("mare")

      assigns_before = :sys.get_state(view.pid).socket.assigns
      assert MapSet.size(assigns_before.selected_category_ids) == 1

      view |> cycle_filter("mare")

      assigns_after = :sys.get_state(view.pid).socket.assigns

      assert MapSet.equal?(
               assigns_after.selected_category_ids,
               assigns_before.selected_category_ids
             )

      assert assigns_after.filter_state[CategoriesFixtures.category_by_name!("mare").id] ==
               :optional
    end

    test "clear_filters does not affect form @selected_category_ids", %{conn: conn} do
      _ = seed_5_lv_ideas()
      view = mount_authenticated(conn) |> open_form() |> toggle_chip("mare")
      view |> cycle_filter("sport")

      render_click(view, "clear_filters")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert MapSet.size(assigns.selected_category_ids) == 1
      assert assigns.filter_state == %{}
    end

    # F11: Filter survives form submission
    test "submitting the form preserves @filter_state", %{conn: conn} do
      _ = seed_5_lv_ideas()
      view = mount_authenticated(conn) |> open_form()
      view |> cycle_filter("mare")

      submit(view, %{title: "Nuova"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.filter_state[CategoriesFixtures.category_by_name!("mare").id] == :optional
    end

    # F12: New idea outside filter is hidden
    test "an idea created outside the active filter is hidden in the list", %{conn: conn} do
      _ = seed_5_lv_ideas()
      view = mount_authenticated(conn) |> open_form()

      # Filter requires "mare" (2 cycles to reach :required)
      view |> cycle_filter("mare") |> cycle_filter("mare")

      # Submit a sport-only idea (mare not selected via toggle_chip)
      view |> toggle_chip("sport")
      html = form_submit(view, %{title: "SportOnly"})

      # Idea was created but NOT visible in the filtered list
      refute html =~ "SportOnly"
      assert Repo.get_by(Idea, title: "SportOnly")
    end
  end

  # ── Slice 4 Step 9 / Slice 5 Step 6 (AA13): out-of-scope guard ──
  # Slice 5 step 6 introduces `Durata` legitimately (filter sub-block label,
  # form legend, badge, …) so the negative list narrows to the still-out-of-
  # scope features. We also add a positive assertion that `Durata` is in the
  # filter row sub-block label (regression: must not be silently removed).
  describe "out-of-scope guard (slice 4 A13 + slice 5 AA13)" do
    test "no Budget/Distanza/Cerca filter UI strings appear", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)
      refute html =~ ~r/Budget|Distanza|Cerca/i
    end

    test "Durata appears as a visible sub-block label in the filter row",
         %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)
      assert html =~ ~r{<p[^>]*class="[^"]*text-xs[^"]*"[^>]*>\s*Durata\s*</p>}
    end
  end

  describe "filter chip XSS regression (slice 4 S2)" do
    test "a category whose name contains <script> is escaped on the filter chip",
         %{conn: conn} do
      Repo.insert!(%Category{
        name: "<script>alert(1)</script>",
        display_order: 999
      })

      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
      refute html =~ "<script>alert(1)</script>"
    end
  end

  describe "live-region count + last action (slice 4)" do
    test "initial render includes a polite live-region with id filter-status",
         %{conn: conn} do
      _ = seed_5_lv_ideas()
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      assert html =~ ~s(id="filter-status")
      assert html =~ ~s(role="status")
      assert html =~ ~s(aria-live="polite")
      assert html =~ "5 idee"
    end

    test "no filter active: live-region has no action prefix", %{conn: conn} do
      _ = seed_5_lv_ideas()
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      assert html =~ extract_filter_status(html)
      status = extract_filter_status(html)
      assert status == "5 idee"
    end

    test "cycle to optional adds 'opzionale,' prefix and updates count",
         %{conn: conn} do
      _ = seed_5_lv_ideas()
      {:ok, view, _html} = live_isolated(conn, Index, session: @authenticated_session)

      html = view |> cycle_filter("mare") |> render()
      assert extract_filter_status(html) == "mare opzionale, 2 idee"
    end

    test "cycle to required swaps the prefix to 'obbligatoria,'", %{conn: conn} do
      _ = seed_5_lv_ideas()
      {:ok, view, _html} = live_isolated(conn, Index, session: @authenticated_session)

      view |> cycle_filter("mare")
      html = view |> cycle_filter("mare") |> render()
      assert extract_filter_status(html) == "mare obbligatoria, 2 idee"
    end

    test "cycle back to off uses 'rimossa,' prefix", %{conn: conn} do
      _ = seed_5_lv_ideas()
      {:ok, view, _html} = live_isolated(conn, Index, session: @authenticated_session)

      view |> cycle_filter("mare") |> cycle_filter("mare")
      html = view |> cycle_filter("mare") |> render()
      assert extract_filter_status(html) == "mare rimossa, 5 idee"
    end

    test "Mostra tutte produces 'Filtri rimossi,' prefix", %{conn: conn} do
      _ = seed_5_lv_ideas()
      {:ok, view, _html} = live_isolated(conn, Index, session: @authenticated_session)

      view |> cycle_filter("mare")
      html = render_click(view, "clear_filters")
      assert extract_filter_status(html) == "Filtri rimossi, 5 idee"
    end

    test "singular boundary: filter producing 1 result shows '1 idea'",
         %{conn: conn} do
      _ = seed_5_lv_ideas()
      {:ok, view, _html} = live_isolated(conn, Index, session: @authenticated_session)

      # mare required + sport required → only Bagno (1 idea)
      view |> cycle_filter("mare") |> cycle_filter("mare")
      html = view |> cycle_filter("sport") |> cycle_filter("sport") |> render()
      assert extract_filter_status(html) == "sport obbligatoria, 1 idea"
    end

    test "DOM node identity stable across cycles", %{conn: conn} do
      _ = seed_5_lv_ideas()
      {:ok, view, _html} = live_isolated(conn, Index, session: @authenticated_session)

      for _ <- 1..3 do
        html = view |> cycle_filter("mare") |> render()
        # Exactly one filter-status element in every render
        count = Regex.scan(~r/id="filter-status"/, html) |> length()
        assert count == 1
      end
    end

    # F11/A16 lifecycle: form save success resets @last_filter_action to nil
    test "form save success clears last action prefix from the live-region",
         %{conn: conn} do
      _ = seed_5_lv_ideas()
      view = mount_authenticated(conn) |> open_form()
      view |> cycle_filter("mare")

      # Sanity: prefix is present after cycle
      pre_save_html = render(view)
      assert extract_filter_status(pre_save_html) =~ "opzionale,"

      # Submit: idea is created, prefix is cleared
      submit(view, %{title: "Nuova"})
      post_save_html = render(view)

      status = extract_filter_status(post_save_html)
      refute status =~ "opzionale,"
      refute status =~ "obbligatoria,"
      refute status =~ "rimossa,"
      refute status =~ "Filtri rimossi,"
    end
  end

  defp extract_filter_status(html) do
    case Regex.run(~r{<div[^>]*id="filter-status"[^>]*>(.*?)</div>}s, html) do
      [_, inner] -> inner |> String.trim()
      _ -> nil
    end
  end

  describe "clear_filters handler (slice 4)" do
    # Scenario: "Mostra tutte" resets the filter state but leaves chips visible
    test "clear_filters resets @filter_state to %{}", %{conn: conn} do
      view = mount_authenticated(conn)
      mare = CategoriesFixtures.category_by_name!("mare")
      sport = CategoriesFixtures.category_by_name!("sport")

      render_click(view, "cycle_filter", %{"id" => "#{mare.id}"})
      render_click(view, "cycle_filter", %{"id" => "#{sport.id}"})
      render_click(view, "cycle_filter", %{"id" => "#{sport.id}"})

      render_click(view, "clear_filters")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.filter_state == %{}
    end

    test "clear_filters on already-empty filter is idempotent (S3)", %{conn: conn} do
      view = mount_authenticated(conn)

      render_click(view, "clear_filters")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.filter_state == %{}
      assert Process.alive?(view.pid)
    end
  end

  # ── Slice 5 Step 1: roving tabindex hook + filter row sub-grouping ──
  describe "roving tabindex sub-group (slice 5 step 1)" do
    # AA21: aria-label is "Filtra per categoria" not bare "Categorie" to
    # avoid a future SR-collision with the form fieldset's <legend>Durata</legend>.
    test "renders <div role=\"group\"> wrapper around filter chips, nested in filter <section>",
         %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      # Locate the role=group wrapper opening tag (attribute order is not
      # part of the contract; we assert each attribute is present on the
      # same opening <div> element).
      [group_open] =
        Regex.run(
          ~r{<div[^>]*id="filter-categories-group"[^>]*>},
          html
        ) || [nil] |> List.wrap()

      assert group_open, "Expected <div id=\"filter-categories-group\"> to be rendered"
      assert group_open =~ ~s(role="group")
      assert group_open =~ ~s(aria-label="Filtra per categoria")
      assert group_open =~ ~s(data-roving-tabindex-group="filter-categories")
      assert group_open =~ ~s(phx-hook="RovingTabindex")

      # And the wrapper sits inside the <section aria-label="Filtra per:">
      # block (AA21 + AA11: nested role=group under the section's label).
      section_match =
        Regex.run(
          ~r{<section[^>]*aria-label="Filtra per:".*?</section>}s,
          html
        )

      assert section_match,
             "Expected the filter <section aria-label=\"Filtra per:\"> to be present"

      [section_html] = section_match
      assert section_html =~ ~s(id="filter-categories-group")
      assert section_html =~ ~s(role="group")
      assert section_html =~ ~s(aria-label="Filtra per categoria")
    end

    # AA10: server pre-paints the initial roving tabindex distribution so
    # the first chip is the only Tab stop; the JS hook takes over arrow keys
    # at the client. Exactly 1× tabindex="0" + 7× tabindex="-1" across the
    # 8 filter-chip-N buttons.
    test "filter chip buttons: only the first has tabindex=0, the other 7 have tabindex=-1",
         %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      filter_chip_buttons =
        Regex.scan(~r{<button id="filter-chip-\d+"[^>]*>}, html) |> Enum.map(&hd/1)

      assert length(filter_chip_buttons) == 8

      tabindex_zero =
        filter_chip_buttons |> Enum.filter(&(&1 =~ ~r/tabindex="0"/)) |> length()

      tabindex_minus_one =
        filter_chip_buttons |> Enum.filter(&(&1 =~ ~r/tabindex="-1"/)) |> length()

      assert tabindex_zero == 1, "Expected exactly 1 filter chip with tabindex=\"0\""
      assert tabindex_minus_one == 7, "Expected exactly 7 filter chips with tabindex=\"-1\""
    end

    # Slice-3 regression guard: the form-side category chips (<button id=
    # "category-chip-N">) MUST NOT carry an explicit `tabindex` attribute —
    # they keep the natural Tab order. Roving tabindex is filter-row-only.
    test "form category chips have no explicit tabindex attribute (slice 3 regression)",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      html = render(view)

      offenders =
        Regex.scan(~r{<button id="category-chip-\d+"[^>]*tabindex[^>]*>}, html)

      assert offenders == []
    end

    # AA10: the JS hook must be wired into the LiveSocket hooks config.
    # Static read of app.js — pinned as a hook-registration regression so a
    # future refactor cannot quietly drop the import.
    test "app.js registers the RovingTabindex hook on the LiveSocket" do
      app_js = File.read!(Path.join(File.cwd!(), "assets/js/app.js"))
      assert app_js =~ "RovingTabindex"
    end

    # R5-4 prevention (post-step-6 inversion): the visible sub-label `Categorie`
    # was absent in step 1 but is REQUIRED from step 6 onward (when the durata
    # sub-block appears: AA1/AA11 — visible sub-labels distinguish two sibling
    # role=group blocks). Asserted positively here. The `Durata` sub-label is
    # asserted in the step-6 describe block.
    test "renders the visible 'Categorie' sub-label above the filter chips (step 6)",
         %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      assert html =~ ~r{<p[^>]*class="[^"]*text-xs[^"]*"[^>]*>\s*Categorie\s*</p>}
    end
  end

  # ── Slice 5 Step 3: form duration field (chip + handler + persistence) ──
  describe "form duration field (slice 5 step 3)" do
    test "fieldset legend Durata is hidden until the form is opened", %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

      # The string "Durata" appears legitimately in the filter row sub-block
      # label and in the helper text (slice 5 step 6); we scope this assertion
      # to the form's <legend> tag, which is what slice 3/5 controls via
      # form_visible?.
      refute html =~ ~r{<legend[^>]*>\s*Durata\s*</legend>}
    end

    test "opening the form renders <legend>Durata</legend> with NO asterisk and 5 chips",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render_click(view, "toggle_form")

      assert html =~ "<legend"
      assert html =~ "Durata"

      [duration_legend] =
        Regex.run(~r{<legend[^>]*>\s*Durata\s*</legend>}, html) || [nil] |> List.wrap()

      assert duration_legend, "Expected <legend>Durata</legend> to be rendered"
      refute duration_legend =~ "*"

      # 5 form-duration-chip buttons in display order with their IT labels.
      for label <- ["poche ore", "mezza giornata", "giornata", "weekend", "più giorni"] do
        assert html =~ label
      end

      ids =
        Regex.scan(~r{id="(form-duration-chip-\w+)"}, html) |> Enum.map(&Enum.at(&1, 1))

      assert ids == [
               "form-duration-chip-poche_ore",
               "form-duration-chip-mezza_giornata",
               "form-duration-chip-giornata",
               "form-duration-chip-weekend",
               "form-duration-chip-piu_giorni"
             ]
    end

    test "after open, @selected_duration is nil and all chips are aria-pressed=false",
         %{conn: conn} do
      view = mount_authenticated(conn)
      _ = render_click(view, "toggle_form")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_duration == nil

      html = render(view)

      duration_chip_buttons =
        Regex.scan(~r{<button[^>]*id="form-duration-chip-\w+"[^>]*>}, html)
        |> Enum.map(&hd/1)

      assert length(duration_chip_buttons) == 5

      for btn <- duration_chip_buttons do
        assert btn =~ ~s(aria-pressed="false")
      end
    end

    test "click weekend chip sets @selected_duration=:weekend and chip aria-pressed=true",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html = render_click(view, "toggle_form_duration", %{"duration" => "weekend"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_duration == :weekend

      [weekend_btn] =
        Regex.run(~r{<button[^>]*id="form-duration-chip-weekend"[^>]*>}, html) ||
          [nil] |> List.wrap()

      assert weekend_btn
      assert weekend_btn =~ ~s(aria-pressed="true")

      # Other 4 are still pressed=false.
      others =
        ~w(poche_ore mezza_giornata giornata piu_giorni)
        |> Enum.map(fn d ->
          [m] =
            Regex.run(~r{<button[^>]*id="form-duration-chip-#{d}"[^>]*>}, html) ||
              [nil] |> List.wrap()

          m
        end)

      for btn <- others, do: assert(btn =~ ~s(aria-pressed="false"))
    end

    test "click weekend twice toggles back to nil (deselect)", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      render_click(view, "toggle_form_duration", %{"duration" => "weekend"})
      html = render_click(view, "toggle_form_duration", %{"duration" => "weekend"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_duration == nil

      duration_chip_buttons =
        Regex.scan(~r{<button[^>]*id="form-duration-chip-\w+"[^>]*>}, html)
        |> Enum.map(&hd/1)

      for btn <- duration_chip_buttons, do: assert(btn =~ ~s(aria-pressed="false"))
    end

    test "click giornata when weekend is pressed swaps single selection",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      render_click(view, "toggle_form_duration", %{"duration" => "weekend"})
      html = render_click(view, "toggle_form_duration", %{"duration" => "giornata"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_duration == :giornata

      [weekend_btn] =
        Regex.run(~r{<button[^>]*id="form-duration-chip-weekend"[^>]*>}, html) ||
          [nil] |> List.wrap()

      [giornata_btn] =
        Regex.run(~r{<button[^>]*id="form-duration-chip-giornata"[^>]*>}, html) ||
          [nil] |> List.wrap()

      assert weekend_btn =~ ~s(aria-pressed="false")
      assert giornata_btn =~ ~s(aria-pressed="true")
    end

    test "save success WITH duration persists duration and resets @selected_duration to nil",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      render_click(view, "toggle_form_duration", %{"duration" => "weekend"})

      html = submit(view, %{title: "Sirolo weekend"})

      assert html =~ "Idea aggiunta"

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_duration == nil
      assert length(assigns.ideas) == 1

      idea = hd(assigns.ideas)
      assert idea.duration == :weekend
    end

    test "save success WITHOUT duration persists duration: nil", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      submit(view, %{title: "Cinema stasera"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert length(assigns.ideas) == 1
      idea = hd(assigns.ideas)
      assert idea.duration == nil
    end

    test "close_form resets @selected_duration to nil", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      render_click(view, "toggle_form_duration", %{"duration" => "weekend"})

      pre =
        :sys.get_state(view.pid).socket.assigns

      assert pre.selected_duration == :weekend

      render_click(view, "close_form")

      post = :sys.get_state(view.pid).socket.assigns
      assert post.form_visible? == false
      assert post.selected_duration == nil
    end

    test "open_form resets @selected_duration to nil even after close+reopen with prior pick",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      render_click(view, "toggle_form_duration", %{"duration" => "weekend"})
      render_click(view, "close_form")
      render_click(view, "toggle_form")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.form_visible? == true
      assert assigns.selected_duration == nil
    end

    # S3 / B2 — hostile toggle_form_duration uniform list (5 strings + 3 non-strings).
    for value <- ["schifoso", "", "WEEKEND", "poche_ora", "poche ore"] do
      test "toggle_form_duration with hostile string #{inspect(value)} is a no-op",
           %{conn: conn} do
        view = mount_authenticated(conn) |> open_form()

        # Pre-state: nil
        render_click(view, "toggle_form_duration", %{"duration" => unquote(value)})

        assigns = :sys.get_state(view.pid).socket.assigns
        assert assigns.selected_duration == nil
        assert Process.alive?(view.pid)
      end
    end

    for value <- [42, [], %{}] do
      test "toggle_form_duration with hostile non-string #{inspect(value)} is a no-op",
           %{conn: conn} do
        view = mount_authenticated(conn) |> open_form()

        render_click(view, "toggle_form_duration", %{"duration" => unquote(Macro.escape(value))})

        assigns = :sys.get_state(view.pid).socket.assigns
        assert assigns.selected_duration == nil
        assert Process.alive?(view.pid)
      end
    end

    # S4 — Save with hostile duration string surfaces "Durata non valida" + nothing persists.
    test "save with hostile duration string surfaces 'Durata non valida' and does not persist",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      mare = CategoriesFixtures.category_by_name!("mare")
      render_click(view, "toggle_category", %{"id" => "#{mare.id}"})

      pre_count = length(Ideajar.Ideas.list_ideas([]))

      # The Durata chip does not render a hidden form input — it lives
      # outside `<form>` (chip is server-state, not an HTML form control).
      # To exercise the S4 hostile-duration path we submit the save event
      # directly with a tampered "duration" key that bypasses the chip
      # (mimics a DevTools/curl payload). The LV save handler must let the
      # raw value reach the changeset, where the Ecto.Enum cast rejects it
      # and `override_duration_error/1` rewrites the message.
      html =
        render_submit(view, "save", %{
          "idea" => %{
            "title" => "X",
            "description" => "",
            "url" => "",
            "duration" => "<script>"
          }
        })

      assert html =~ "Durata non valida"
      assert length(Ideajar.Ideas.list_ideas([])) == pre_count
      assert Process.alive?(view.pid)
    end

    # AA18 / A11 — DOM id distinctness across the 3 chip families.
    test "with form open, total chip ids = 5 form-duration + 8 filter-chip + 8 category-chip",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      html = render(view)

      ids =
        Regex.scan(
          ~r{id="(form-duration-chip-\w+|filter-chip-\d+|category-chip-\d+)"},
          html
        )
        |> Enum.map(&Enum.at(&1, 1))

      assert length(ids) == 21
      assert ids == Enum.uniq(ids)
    end

    # A8 — form chip durata: no roving-tabindex hook, no explicit tabindex.
    test "form duration fieldset has no RovingTabindex hook and chips have no explicit tabindex",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      html = render(view)

      # Pin the durata fieldset block via the legend, then assert the
      # surrounding HTML up to the next closing </fieldset> contains neither
      # a phx-hook="RovingTabindex" nor a data-roving-tabindex-group.
      [durata_block] =
        Regex.run(~r{<legend[^>]*>\s*Durata\s*</legend>.*?</fieldset>}s, html) ||
          [nil] |> List.wrap()

      assert durata_block, "Expected the durata fieldset block to be present"
      refute durata_block =~ "RovingTabindex"
      refute durata_block =~ "data-roving-tabindex-group"

      # No form-duration-chip-* button carries an explicit tabindex attribute.
      offenders =
        Regex.scan(~r{<button[^>]*id="form-duration-chip-\w+"[^>]*tabindex[^>]*>}, html)

      assert offenders == []
    end
  end

  describe "idea card duration badge (slice 5 step 4)" do
    # F13 — present: an idea with a duration renders a badge with the IT label.
    test "idea with duration: :weekend renders <span data-testid=idea-duration-badge> with IT label",
         %{conn: conn} do
      mare = CategoriesFixtures.category_by_name!("mare")

      assert {:ok, _idea} =
               Ideajar.Ideas.create_idea(%{
                 title: "Sirolo",
                 category_ids: [mare.id],
                 duration: "weekend"
               })

      {:ok, _view, html} =
        live_isolated(conn, Index, session: @authenticated_session)

      [_full, inner] =
        Regex.run(
          ~r{<span[^>]*data-testid="idea-duration-badge"[^>]*>(.*?)</span>}s,
          html
        )

      assert String.trim(inner) == "weekend"
    end

    # F13 — absent: an idea without duration renders no badge for it.
    test "idea with duration: nil renders NO data-testid=idea-duration-badge element",
         %{conn: conn} do
      mare = CategoriesFixtures.category_by_name!("mare")

      assert {:ok, _idea} =
               Ideajar.Ideas.create_idea(%{
                 title: "Cinema stasera",
                 category_ids: [mare.id]
               })

      {:ok, _view, html} =
        live_isolated(conn, Index, session: @authenticated_session)

      refute html =~ ~s(data-testid="idea-duration-badge")
    end

    # Multiple ideas: only the duration-bearing one shows a badge.
    test "two ideas (one with :weekend, one without) render exactly one badge",
         %{conn: conn} do
      mare = CategoriesFixtures.category_by_name!("mare")

      assert {:ok, _} =
               Ideajar.Ideas.create_idea(%{
                 title: "Sirolo",
                 category_ids: [mare.id],
                 duration: "weekend"
               })

      assert {:ok, _} =
               Ideajar.Ideas.create_idea(%{
                 title: "Cinema",
                 category_ids: [mare.id]
               })

      {:ok, _view, html} =
        live_isolated(conn, Index, session: @authenticated_session)

      badges = Regex.scan(~r/data-testid="idea-duration-badge"/, html)
      assert length(badges) == 1
    end

    # Each canonical duration label appears in the badge — parametric pin.
    for duration <- Duration.values() do
      label = Duration.label(duration)

      test "duration #{inspect(duration)} renders the IT label #{inspect(label)} in the badge",
           %{conn: conn} do
        mare = CategoriesFixtures.category_by_name!("mare")

        assert {:ok, _} =
                 Ideajar.Ideas.create_idea(%{
                   title: "T-#{unquote(Atom.to_string(duration))}",
                   category_ids: [mare.id],
                   duration: unquote(Atom.to_string(duration))
                 })

        {:ok, _view, html} =
          live_isolated(conn, Index, session: @authenticated_session)

        [_full, inner] =
          Regex.run(
            ~r{<span[^>]*data-testid="idea-duration-badge"[^>]*>(.*?)</span>}s,
            html
          )

        assert String.trim(inner) == unquote(label)
      end
    end

    # Position pin — the badge appears AFTER <ul aria-label="Categorie"> in DOM source order.
    test "badge appears after <ul aria-label=\"Categorie\"> within the idea card",
         %{conn: conn} do
      mare = CategoriesFixtures.category_by_name!("mare")

      assert {:ok, _} =
               Ideajar.Ideas.create_idea(%{
                 title: "Sirolo",
                 category_ids: [mare.id],
                 duration: "weekend"
               })

      {:ok, _view, html} =
        live_isolated(conn, Index, session: @authenticated_session)

      # Single-card scenario: the only `<ul aria-label="Categorie">` and the
      # only badge in the document both belong to the same card. Scan the
      # full HTML for source-order positions; the position-pin invariant is
      # that the badge is rendered AFTER the categories list, never before.
      categories_pos =
        case :binary.match(html, ~s(aria-label="Categorie")) do
          {pos, _} -> pos
          :nomatch -> nil
        end

      badge_pos =
        case :binary.match(html, ~s(data-testid="idea-duration-badge")) do
          {pos, _} -> pos
          :nomatch -> nil
        end

      assert is_integer(categories_pos)
      assert is_integer(badge_pos)
      assert categories_pos < badge_pos
    end
  end

  # ── Slice 5 Step 6: duration filter sub-block ─────────────────────────
  defp insert_idea_with_categories_and_duration!(
         title,
         category_names,
         duration,
         %DateTime{} = at
       ) do
    cats = Enum.map(category_names, &CategoriesFixtures.category_by_name!/1)

    idea =
      %Idea{title: title, duration: duration}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:categories, cats)
      |> Repo.insert!()

    Repo.update!(
      Ecto.Changeset.change(idea, inserted_at: at, updated_at: at),
      force: true
    )
  end

  defp seed_6_lv_ideas_with_durations do
    %{
      sirolo:
        insert_idea_with_categories_and_duration!(
          "Sirolo",
          ["mare", "viaggio"],
          :weekend,
          ~U[2026-04-27 10:00:00Z]
        ),
      uffizi:
        insert_idea_with_categories_and_duration!(
          "Uffizi",
          ["museo", "cultura"],
          :giornata,
          ~U[2026-04-27 10:01:00Z]
        ),
      stadio:
        insert_idea_with_categories_and_duration!(
          "Stadio",
          ["sport"],
          :poche_ore,
          ~U[2026-04-27 10:02:00Z]
        ),
      bagno_improvviso:
        insert_idea_with_categories_and_duration!(
          "Bagno improvviso",
          ["mare", "sport"],
          nil,
          ~U[2026-04-27 10:03:00Z]
        ),
      cinema:
        insert_idea_with_categories_and_duration!(
          "Cinema",
          ["cinema", "cultura"],
          :mezza_giornata,
          ~U[2026-04-27 10:04:00Z]
        ),
      bivacco:
        insert_idea_with_categories_and_duration!(
          "Bivacco",
          ["sport"],
          :poche_ore,
          ~U[2026-04-27 10:05:00Z]
        )
    }
  end

  defp cycle_duration(view, atom) do
    render_click(view, "toggle_duration_filter", %{"duration" => Atom.to_string(atom)})
    view
  end

  describe "duration filter sub-block (slice 5 step 6)" do
    # 1. Sub-block durata reso (AA11/AA21)
    test "renders <div role=group aria-label='Filtra per durata'> with hook + 5 chip buttons",
         %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      [group_open] =
        Regex.run(~r{<div[^>]*id="filter-durations-group"[^>]*>}, html) ||
          [nil] |> List.wrap()

      assert group_open,
             "Expected <div id=\"filter-durations-group\"> to be rendered"

      assert group_open =~ ~s(role="group")
      assert group_open =~ ~s(aria-label="Filtra per durata")
      assert group_open =~ ~s(data-roving-tabindex-group="filter-durations")
      assert group_open =~ ~s(phx-hook="RovingTabindex")

      filter_duration_buttons =
        Regex.scan(~r{<button[^>]*id="filter-duration-chip-\w+"[^>]*>}, html)
        |> Enum.map(&hd/1)

      assert length(filter_duration_buttons) == 5
    end

    # 2. Visible sub-labels on BOTH groups (AA1/AA11)
    test "renders visible 'Categorie' AND 'Durata' sub-labels in the filter section",
         %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      assert html =~ ~r{<p[^>]*class="[^"]*text-xs[^"]*"[^>]*>\s*Categorie\s*</p>}
      assert html =~ ~r{<p[^>]*class="[^"]*text-xs[^"]*"[^>]*>\s*Durata\s*</p>}
    end

    # 3. Helper text NULL-exclusion (AA19/A12)
    test "renders the NULL-exclusion helper text exactly once, between sub-label and chip group",
         %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      helper_text = "Le idee senza durata sono nascoste quando un filtro è attivo."

      occurrences =
        Regex.scan(~r{Le idee senza durata sono nascoste quando un filtro è attivo\.}, html)
        |> length()

      assert occurrences == 1, "Expected the helper text to appear exactly once"

      durata_label_pos =
        case Regex.run(
               ~r{<p[^>]*class="[^"]*text-xs[^"]*"[^>]*>\s*Durata\s*</p>},
               html,
               return: :index
             ) do
          [{pos, _len}] -> pos
          _ -> nil
        end

      helper_pos =
        case :binary.match(html, helper_text) do
          {pos, _} -> pos
          :nomatch -> nil
        end

      first_chip_pos =
        case :binary.match(html, ~s(id="filter-duration-chip-poche_ore")) do
          {pos, _} -> pos
          :nomatch -> nil
        end

      assert is_integer(durata_label_pos)
      assert is_integer(helper_pos)
      assert is_integer(first_chip_pos)

      assert durata_label_pos < helper_pos,
             "Helper text must appear AFTER the 'Durata' sub-label"

      assert helper_pos < first_chip_pos,
             "Helper text must appear BEFORE the first duration chip"
    end

    # 4. Step 1 sub-block aria-label invariate.
    test "categorie sub-block keeps aria-label='Filtra per categoria'", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)
      assert html =~ ~s(aria-label="Filtra per categoria")
    end

    # 5. Secondo rover: only 1 tabindex=0 on filter-duration-chip-*.
    test "secondo rover: only first duration chip (poche_ore) has tabindex=0",
         %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      duration_chip_buttons =
        Regex.scan(~r{<button[^>]*id="filter-duration-chip-\w+"[^>]*>}, html)
        |> Enum.map(&hd/1)

      assert length(duration_chip_buttons) == 5

      tabindex_zero =
        duration_chip_buttons |> Enum.filter(&(&1 =~ ~r/tabindex="0"/)) |> length()

      tabindex_minus_one =
        duration_chip_buttons |> Enum.filter(&(&1 =~ ~r/tabindex="-1"/)) |> length()

      assert tabindex_zero == 1
      assert tabindex_minus_one == 4

      [poche_ore_btn] =
        Regex.run(
          ~r{<button[^>]*id="filter-duration-chip-poche_ore"[^>]*>},
          html
        ) || [nil] |> List.wrap()

      assert poche_ore_btn =~ ~r/tabindex="0"/
    end

    # 6. Cycle 2-state on (F11)
    test "cycle weekend on: @duration_filter == MapSet.new([:weekend]); chip flipped to :on",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      html = view |> cycle_duration(:weekend) |> render()

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.duration_filter == MapSet.new([:weekend])

      [weekend_btn] =
        Regex.run(
          ~r{<button[^>]*id="filter-duration-chip-weekend"[^>]*>},
          html
        ) || [nil] |> List.wrap()

      assert weekend_btn
      assert weekend_btn =~ ~s(data-duration-filter-state="on")
      assert weekend_btn =~ ~s(aria-label="weekend attiva")
      # Hero-check icon present in the rendered chip
      [_full, inner] =
        Regex.run(
          ~r{<button[^>]*id="filter-duration-chip-weekend"[^>]*>(.*?)</button>}s,
          html
        )

      assert inner =~ "hero-check"
    end

    # 7. Cycle 2-state off (F11)
    test "cycle weekend twice: returns @duration_filter to empty; chip back to :off",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      view |> cycle_duration(:weekend)
      html = view |> cycle_duration(:weekend) |> render()

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.duration_filter == MapSet.new()

      [weekend_btn] =
        Regex.run(
          ~r{<button[^>]*id="filter-duration-chip-weekend"[^>]*>},
          html
        ) || [nil] |> List.wrap()

      assert weekend_btn
      assert weekend_btn =~ ~s(data-duration-filter-state="off")
      assert weekend_btn =~ ~s(aria-label="weekend")
      refute weekend_btn =~ ~s(aria-label="weekend attiva")
    end

    # 8. Filter matching (F7)
    test "cycle weekend on: list contains only :weekend ideas; NULL excluded",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      html = view |> cycle_duration(:weekend) |> render()

      assert html =~ "Sirolo"
      refute html =~ "Uffizi"
      refute html =~ "Stadio"
      refute html =~ "Bagno improvviso"
      refute html =~ "Cinema"
      refute html =~ "Bivacco"
    end

    # 9. Multi-OR (F8)
    test "cycle weekend + giornata: list contains union (Sirolo + Uffizi)",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      html =
        view
        |> cycle_duration(:weekend)
        |> cycle_duration(:giornata)
        |> render()

      assert html =~ "Sirolo"
      assert html =~ "Uffizi"
      refute html =~ "Stadio"
      refute html =~ "Bagno improvviso"
      refute html =~ "Cinema"
      refute html =~ "Bivacco"
    end

    # 10. Empty result with duration filter only (no piu_giorni in DB)
    test "cycle piu_giorni on a DB without piu_giorni ideas: empty-filter state",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      html = view |> cycle_duration(:piu_giorni) |> render()

      assert html =~ "Nessuna idea per i filtri attivi."
      assert html =~ "Mostra tutte"

      [piu_giorni_btn] =
        Regex.run(
          ~r{<button[^>]*id="filter-duration-chip-piu_giorni"[^>]*>},
          html
        ) || [nil] |> List.wrap()

      assert piu_giorni_btn
      assert piu_giorni_btn =~ ~s(data-duration-filter-state="on")
    end

    # 11. Live-region prefix on, no compound (A5)
    test "live-region: cycle weekend on, no category filter → 'weekend attiva, 1 idea'",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      html = view |> cycle_duration(:weekend) |> render()

      assert extract_filter_status(html) == "weekend attiva, 1 idea"
    end

    # 12. Live-region prefix off
    test "live-region: cycle weekend off → 'weekend rimossa, 6 idee'", %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      view |> cycle_duration(:weekend)
      html = view |> cycle_duration(:weekend) |> render()

      assert extract_filter_status(html) == "weekend rimossa, 6 idee"
    end

    # 13. Compound suffix on durata-action (A13/AA20)
    test "live-region compound: category mare required + cycle weekend on → suffix 'filtri categoria attivi'",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      # Cycle mare to required (twice through cycle_filter)
      view |> cycle_filter("mare") |> cycle_filter("mare")
      html = view |> cycle_duration(:weekend) |> render()

      assert extract_filter_status(html) ==
               "weekend attiva, 1 idea, filtri categoria attivi"
    end

    # 14. Compound suffix on categoria-action (A13/AA20)
    test "live-region compound: duration weekend on + cycle category mare to required → suffix 'filtri durata attivi'",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      view |> cycle_duration(:weekend)
      view |> cycle_filter("mare")
      html = view |> cycle_filter("mare") |> render()

      assert extract_filter_status(html) ==
               "mare obbligatoria, 1 idea, filtri durata attivi"
    end

    # 15. Filtri rimossi no suffix
    test "live-region: with both groups active, click 'Mostra tutte' → 'Filtri rimossi, 6 idee' (no suffix)",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      view |> cycle_duration(:weekend) |> cycle_filter("mare")
      html = render_click(view, "clear_filters")

      assert extract_filter_status(html) == "Filtri rimossi, 6 idee"
    end

    # 16. Hostile filter duration uniform list (S1, S2)
    for value <- ["schifoso", "", "WEEKEND", "poche_ora", "poche ore"] do
      test "toggle_duration_filter with hostile string #{inspect(value)} is a no-op",
           %{conn: conn} do
        view = mount_authenticated(conn)

        render_click(view, "toggle_duration_filter", %{"duration" => unquote(value)})

        assigns = :sys.get_state(view.pid).socket.assigns
        assert assigns.duration_filter == MapSet.new()
        assert Process.alive?(view.pid)
      end
    end

    for value <- [42, [], %{}] do
      test "toggle_duration_filter with hostile non-string #{inspect(value)} is a no-op",
           %{conn: conn} do
        view = mount_authenticated(conn)

        render_click(view, "toggle_duration_filter", %{
          "duration" => unquote(Macro.escape(value))
        })

        assigns = :sys.get_state(view.pid).socket.assigns
        assert assigns.duration_filter == MapSet.new()
        assert Process.alive?(view.pid)
      end
    end

    # 17. Form/filter durata ARIA non collide
    test "form open + filter weekend on: both form-duration-chip-weekend and filter-duration-chip-weekend rendered",
         %{conn: conn} do
      view = mount_authenticated(conn)
      view |> cycle_duration(:weekend)
      _ = render_click(view, "toggle_form")
      html = render(view)

      [form_weekend] =
        Regex.run(
          ~r{<button[^>]*id="form-duration-chip-weekend"[^>]*>},
          html
        ) || [nil] |> List.wrap()

      [filter_weekend] =
        Regex.run(
          ~r{<button[^>]*id="filter-duration-chip-weekend"[^>]*>},
          html
        ) || [nil] |> List.wrap()

      assert form_weekend
      assert filter_weekend

      assert form_weekend =~ "aria-pressed"
      refute form_weekend =~ "aria-label"

      assert filter_weekend =~ "aria-label"
      refute filter_weekend =~ "aria-pressed"
    end
  end

  # ── Slice 5 Step 7: clear_filters extension + combined filter scenarios ──
  #
  # Pins F9 (combined AND), F12 (clear_filters resets BOTH groups), S7
  # (idempotency on already-empty filters), and slice-4 F10 extended to the
  # combined-filter case (`Mostra tutte` rendered exactly once).
  describe "clear_filters and combined filters (slice 5 step 7)" do
    # 1. F12 — clear_filters resets BOTH @filter_state and @duration_filter,
    # the list returns to all 6 ideas, and the live-region announces the
    # canonical 'Filtri rimossi, 6 idee' with NO compound suffix.
    test "clear_filters resets both filter_state (categoria) and duration_filter (durata)",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)
      mare = CategoriesFixtures.category_by_name!("mare")

      # Activate both groups: weekend duration on + mare required (2 cycles).
      view |> cycle_duration(:weekend)
      view |> cycle_filter("mare") |> cycle_filter("mare")

      # Sanity: both groups are non-empty pre-clear.
      pre = :sys.get_state(view.pid).socket.assigns
      assert pre.duration_filter == MapSet.new([:weekend])
      assert pre.filter_state == %{mare.id => :required}

      html = render_click(view, "clear_filters")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.filter_state == %{}
      assert assigns.duration_filter == MapSet.new()

      # Every seeded idea is back in the list.
      for title <- ["Sirolo", "Uffizi", "Stadio", "Bagno improvviso", "Cinema", "Bivacco"] do
        assert html =~ title, "Expected #{title} after clear_filters"
      end

      assert extract_filter_status(html) == "Filtri rimossi, 6 idee"
    end

    # 2. S7 — idempotency: calling clear_filters when both groups are already
    # empty must not crash and must leave both at their empty representation.
    test "clear_filters is idempotent when both groups are already empty (S7)",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      pre = :sys.get_state(view.pid).socket.assigns
      assert pre.filter_state == %{}
      assert pre.duration_filter == MapSet.new()

      render_click(view, "clear_filters")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.filter_state == %{}
      assert assigns.duration_filter == MapSet.new()
      assert Process.alive?(view.pid)
    end

    # 3. F9 — combined filters compose as AND across categoria + durata.
    # Sirolo (viaggio + :weekend) is the ONLY match. Bagno improvviso (NULL
    # duration) is excluded by the durata filter; Uffizi/Stadio/Cinema/Bivacco
    # lack the viaggio category.
    test "cycle category viaggio required + duration weekend on → only Sirolo (F9)",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      view |> cycle_filter("viaggio") |> cycle_filter("viaggio")
      html = view |> cycle_duration(:weekend) |> render()

      assert html =~ "Sirolo"
      refute html =~ "Uffizi"
      refute html =~ "Stadio"
      refute html =~ "Bagno improvviso"
      refute html =~ "Cinema"
      refute html =~ "Bivacco"
    end

    # 4. Combined filter with zero matches → empty-filter state, NOT
    # workspace-empty. No idea in the fixture has the passeggiata category,
    # so passeggiata-required already empties the list; adding the weekend
    # duration on top keeps it empty.
    test "passeggiata required + weekend on → empty-filter state (combined)",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      view |> cycle_filter("passeggiata") |> cycle_filter("passeggiata")
      html = view |> cycle_duration(:weekend) |> render()

      assert html =~ "Nessuna idea per i filtri attivi."
      assert html =~ ~s(data-testid="empty-filter-state")
      assert html =~ "Mostra tutte"
      # Workspace-empty copy must NOT appear when at least one filter is on.
      refute html =~ "Nessuna idea ancora. Aggiungine una qui sopra."
    end

    # 5a. Slice-4 F10 extended: combined filter active + non-empty list →
    # exactly ONE Mostra tutte under the filter row, none inside the empty-
    # message (the list isn't empty).
    test "combined filter active + non-empty list: exactly one Mostra tutte under filter row",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      # mare required (2 cycles) + weekend on → Sirolo matches
      view |> cycle_filter("mare") |> cycle_filter("mare")
      html = view |> cycle_duration(:weekend) |> render()

      count = Regex.scan(~r/Mostra tutte/, html) |> length()
      assert count == 1
      assert html =~ ~s(id="mostra-tutte")
      refute html =~ ~s(id="mostra-tutte-empty")
    end

    # 5b. Combined filter active + empty list → exactly ONE Mostra tutte
    # INSIDE the empty-message, none under the filter row.
    test "combined filter active + empty list: exactly one Mostra tutte inside empty-filter state",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      view |> cycle_filter("passeggiata") |> cycle_filter("passeggiata")
      html = view |> cycle_duration(:weekend) |> render()

      count = Regex.scan(~r/Mostra tutte/, html) |> length()
      assert count == 1
      assert html =~ ~s(id="mostra-tutte-empty")
      refute html =~ ~s(id="mostra-tutte")
    end

    # 5c. No filter active anywhere → zero Mostra tutte buttons (regression
    # against the helper signature change).
    test "no filter active: zero Mostra tutte buttons", %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      {:ok, _view, html} = live_isolated(conn, Index, session: @authenticated_session)

      count = Regex.scan(~r/Mostra tutte/, html) |> length()
      assert count == 0
    end

    # 6. Regression for slice-4 F10: Mostra tutte must render when ONLY the
    # durata filter is active (slice-4 F10 only covered category-only).
    test "duration-only filter active + non-empty list: Mostra tutte rendered under filter row",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      html = view |> cycle_duration(:weekend) |> render()

      count = Regex.scan(~r/Mostra tutte/, html) |> length()
      assert count == 1
      assert html =~ ~s(id="mostra-tutte")
      refute html =~ ~s(id="mostra-tutte-empty")
    end

    # 7. AA20 regression: clear_filters live-region NEVER carries a compound
    # suffix because both groups are empty by construction post-clear.
    test "clear_filters live-region has no compound suffix even when both groups were active",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      view |> cycle_duration(:weekend)
      view |> cycle_filter("mare") |> cycle_filter("mare")

      html = render_click(view, "clear_filters")

      status = extract_filter_status(html)
      assert status == "Filtri rimossi, 6 idee"
      refute status =~ "filtri categoria attivi"
      refute status =~ "filtri durata attivi"
    end
  end

  # ── Slice 5 Step 8: form/filter isolation + new-idea-outside-filter ──
  #
  # Each test in this block is a regression pin: the architecture already
  # guarantees the invariant (separate assigns, no cross-handler state
  # mutation). The tests prevent future drift — they should pass on the
  # current implementation without any GREEN code.
  describe "form/filter isolation and new-idea-outside-filter (slice 5 step 8)" do
    # F14 — filter durata survives form submit. Pinning: cycle weekend on,
    # submit a valid idea with a *different* duration; @duration_filter must
    # remain MapSet.new([:weekend]) and the new idea must be persisted but
    # absent from the filtered render.
    test "F14: filter durata survives form submit (regression pin)", %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      view |> cycle_duration(:weekend)
      pre = :sys.get_state(view.pid).socket.assigns
      assert pre.duration_filter == MapSet.new([:weekend])

      view |> open_form()
      render_click(view, "toggle_form_duration", %{"duration" => "giornata"})
      html = submit(view, %{title: "GiornataIdea"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.duration_filter == MapSet.new([:weekend])
      assert Repo.get_by(Idea, title: "GiornataIdea")
      refute html =~ "GiornataIdea"
    end

    # F15 — new idea outside duration filter is hidden. Pinning: pre-submit
    # only Sirolo matches (the seeded :weekend idea); after creating a
    # :giornata idea the filtered list is unchanged and the live-region
    # count tracks length(@ideas) post-save (still 1, prefix reset to nil).
    test "F15: new :giornata idea hidden when :weekend filter active (regression pin)",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      pre_html = view |> cycle_duration(:weekend) |> render()
      assert pre_html =~ "Sirolo"
      pre_assigns = :sys.get_state(view.pid).socket.assigns
      pre_count = length(pre_assigns.ideas)
      assert pre_count == 1

      view |> open_form()
      render_click(view, "toggle_form_duration", %{"duration" => "giornata"})
      html = submit(view, %{title: "GiornataExtra"})

      # Filter still active, list unchanged: only Sirolo visible.
      assert html =~ "Sirolo"
      refute html =~ "GiornataExtra"

      assigns = :sys.get_state(view.pid).socket.assigns
      assert length(assigns.ideas) == pre_count
      # handle_save_result/3 resets the action prefix; live-region just shows
      # the post-save count (1 idea), proving it was NOT incremented.
      assert extract_filter_status(html) == "1 idea"
      assert Repo.get_by(Idea, title: "GiornataExtra")
    end

    # F16 — new idea with NULL duration hidden when filter active. Pinning:
    # AA7 NULL exclusion holds for ideas created *while* the filter is on,
    # not just for pre-existing seeded ones.
    test "F16: new NULL-duration idea hidden when :weekend filter active (regression pin)",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      view |> cycle_duration(:weekend)
      total_before = length(Ideajar.Ideas.list_ideas([]))

      view |> open_form()
      # No form-duration chip pressed → @selected_duration stays nil →
      # maybe_inject_duration leaves params untouched → idea persisted with
      # duration: nil.
      html = submit(view, %{title: "SenzaDurata"})

      total_after = length(Ideajar.Ideas.list_ideas([]))
      assert total_after == total_before + 1

      persisted = Repo.get_by(Idea, title: "SenzaDurata")
      assert persisted
      assert persisted.duration == nil

      refute html =~ "SenzaDurata"

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.duration_filter == MapSet.new([:weekend])
    end

    # Isolation #4 — clear_filters does NOT touch @selected_duration nor the
    # form chip's aria-pressed state. Form duration belongs to the form;
    # @duration_filter belongs to the filter row; clear_filters only acts
    # on the latter.
    test "isolation: clear_filters does not touch form @selected_duration (regression pin)",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn) |> open_form()
      render_click(view, "toggle_form_duration", %{"duration" => "weekend"})

      pre_assigns = :sys.get_state(view.pid).socket.assigns
      assert pre_assigns.selected_duration == :weekend

      view |> cycle_duration(:giornata)
      html = render_click(view, "clear_filters")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_duration == :weekend
      assert assigns.duration_filter == MapSet.new()

      [weekend_form_btn] =
        Regex.run(
          ~r{<button[^>]*id="form-duration-chip-weekend"[^>]*>},
          html
        ) || [nil] |> List.wrap()

      assert weekend_form_btn
      assert weekend_form_btn =~ ~s(aria-pressed="true")
    end

    # Isolation #5 — toggle_duration_filter does NOT touch the form's
    # @selected_duration. The two state slots live side by side and never
    # cross.
    test "isolation: toggle_duration_filter does not touch form @selected_duration (regression pin)",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn) |> open_form()
      render_click(view, "toggle_form_duration", %{"duration" => "weekend"})

      pre_assigns = :sys.get_state(view.pid).socket.assigns
      assert pre_assigns.selected_duration == :weekend

      html = view |> cycle_duration(:giornata) |> render()

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_duration == :weekend
      assert assigns.duration_filter == MapSet.new([:giornata])

      [weekend_form_btn] =
        Regex.run(
          ~r{<button[^>]*id="form-duration-chip-weekend"[^>]*>},
          html
        ) || [nil] |> List.wrap()

      assert weekend_form_btn
      assert weekend_form_btn =~ ~s(aria-pressed="true")

      [giornata_filter_btn] =
        Regex.run(
          ~r{<button[^>]*id="filter-duration-chip-giornata"[^>]*>},
          html
        ) || [nil] |> List.wrap()

      assert giornata_filter_btn
      assert giornata_filter_btn =~ ~s(data-duration-filter-state="on")
    end

    # Refresh — @duration_filter is process-local state. A fresh mount
    # (simulating a page refresh) starts with both @duration_filter and
    # @filter_state empty. Parallel to slice 4 F9 for filter_state.
    test "refresh resets @duration_filter to MapSet.new() (regression pin)", %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)
      view |> cycle_duration(:weekend)
      pre = :sys.get_state(view.pid).socket.assigns
      assert pre.duration_filter == MapSet.new([:weekend])

      # Fresh mount via a brand-new live_isolated call — equivalent to a
      # page refresh from the user's perspective.
      {:ok, fresh_view, _html} =
        live_isolated(conn, Index, session: @authenticated_session)

      assigns = :sys.get_state(fresh_view.pid).socket.assigns
      assert assigns.duration_filter == MapSet.new()
      assert assigns.filter_state == %{}
    end

    # F14 + clear_filters cycle — submitting a valid idea while a duration
    # filter is on persists the idea but hides it; a subsequent
    # clear_filters then surfaces it (and every other seeded idea).
    test "F14 + clear_filters: hidden new idea reappears after Mostra tutte (regression pin)",
         %{conn: conn} do
      _ = seed_6_lv_ideas_with_durations()
      view = mount_authenticated(conn)

      view |> cycle_duration(:weekend)
      view |> open_form()
      render_click(view, "toggle_form_duration", %{"duration" => "giornata"})
      hidden_html = submit(view, %{title: "PostFilterIdea"})

      refute hidden_html =~ "PostFilterIdea"
      assert Repo.get_by(Idea, title: "PostFilterIdea")

      cleared_html = render_click(view, "clear_filters")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.duration_filter == MapSet.new()
      assert assigns.filter_state == %{}

      assert cleared_html =~ "PostFilterIdea"
      # All seeded ideas plus the new one are visible after Mostra tutte.
      for title <- ["Sirolo", "Uffizi", "Stadio", "Bagno improvviso", "Cinema", "Bivacco"] do
        assert cleared_html =~ title, "Expected #{title} to reappear after clear_filters"
      end
    end
  end

  describe "form budget field (slice 6 step 4)" do
    test "mount: @selected_cost is nil before the form is opened",
         %{conn: conn} do
      view = mount_authenticated(conn)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_cost == nil
    end

    test "opening the form renders <legend>Budget</legend> with NO asterisk and 7 chips",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render_click(view, "toggle_form")

      [budget_legend] =
        Regex.run(~r{<legend[^>]*>\s*Budget\s*</legend>}, html) || [nil] |> List.wrap()

      assert budget_legend, "Expected <legend>Budget</legend> to be rendered"
      refute budget_legend =~ "*"

      # 7 form-budget-chip buttons in canonical Budget.values() order.
      ids =
        Regex.scan(~r{id="(form-budget-chip-\d+)"}, html) |> Enum.map(&Enum.at(&1, 1))

      assert ids == [
               "form-budget-chip-0",
               "form-budget-chip-20",
               "form-budget-chip-50",
               "form-budget-chip-100",
               "form-budget-chip-200",
               "form-budget-chip-500",
               "form-budget-chip-1000"
             ]
    end

    test "after open, @selected_cost is nil and all chips are aria-pressed=false",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_cost == nil

      html = render(view)

      budget_chip_buttons =
        Regex.scan(~r{<button[^>]*id="form-budget-chip-\d+"[^>]*>}, html)
        |> Enum.map(&hd/1)

      assert length(budget_chip_buttons) == 7

      for btn <- budget_chip_buttons do
        assert btn =~ ~s(aria-pressed="false")
      end
    end

    test "click cost=100 sets @selected_cost=100 and chip aria-pressed=true",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html = render_click(view, "toggle_form_budget", %{"cost" => "100"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_cost == 100

      [hundred_btn] =
        Regex.run(~r{<button[^>]*id="form-budget-chip-100"[^>]*>}, html) ||
          [nil] |> List.wrap()

      assert hundred_btn
      assert hundred_btn =~ ~s(aria-pressed="true")

      # Other 6 are still pressed=false.
      others =
        ~w(0 20 50 200 500 1000)
        |> Enum.map(fn c ->
          [m] =
            Regex.run(~r{<button[^>]*id="form-budget-chip-#{c}"[^>]*>}, html) ||
              [nil] |> List.wrap()

          m
        end)

      for btn <- others, do: assert(btn =~ ~s(aria-pressed="false"))
    end

    test "click cost=100 twice toggles back to nil (deselect)", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      render_click(view, "toggle_form_budget", %{"cost" => "100"})
      html = render_click(view, "toggle_form_budget", %{"cost" => "100"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_cost == nil

      budget_chip_buttons =
        Regex.scan(~r{<button[^>]*id="form-budget-chip-\d+"[^>]*>}, html)
        |> Enum.map(&hd/1)

      assert length(budget_chip_buttons) == 7
      for btn <- budget_chip_buttons, do: assert(btn =~ ~s(aria-pressed="false"))
    end

    test "click cost=200 when 100 is pressed swaps single selection",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      render_click(view, "toggle_form_budget", %{"cost" => "100"})
      html = render_click(view, "toggle_form_budget", %{"cost" => "200"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_cost == 200

      [hundred_btn] =
        Regex.run(~r{<button[^>]*id="form-budget-chip-100"[^>]*>}, html) ||
          [nil] |> List.wrap()

      [twohundred_btn] =
        Regex.run(~r{<button[^>]*id="form-budget-chip-200"[^>]*>}, html) ||
          [nil] |> List.wrap()

      assert hundred_btn =~ ~s(aria-pressed="false")
      assert twohundred_btn =~ ~s(aria-pressed="true")
    end

    test "click cost=0 (gratis) sets @selected_cost=0 and chip aria-pressed=true",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      html = render_click(view, "toggle_form_budget", %{"cost" => "0"})

      assigns = :sys.get_state(view.pid).socket.assigns
      # 0 is a valid bucket value (not nil): the chip must be in the
      # pressed state, not deselected.
      assert assigns.selected_cost == 0

      [zero_btn] =
        Regex.run(~r{<button[^>]*id="form-budget-chip-0"[^>]*>}, html) ||
          [nil] |> List.wrap()

      assert zero_btn =~ ~s(aria-pressed="true")
    end

    test "save success WITH budget=100 persists estimated_cost=100 and resets @selected_cost to nil",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      render_click(view, "toggle_form_budget", %{"cost" => "100"})

      html = submit(view, %{title: "Sirolo cento"})

      assert html =~ "Idea aggiunta"

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_cost == nil
      assert assigns.form_visible? == false
      assert length(assigns.ideas) == 1

      idea = hd(assigns.ideas)
      assert idea.estimated_cost == 100
    end

    test "save success WITHOUT budget persists estimated_cost: nil",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      submit(view, %{title: "Cinema stasera"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert length(assigns.ideas) == 1
      idea = hd(assigns.ideas)
      assert idea.estimated_cost == nil
    end

    test "save success WITH budget=0 (gratis) persists estimated_cost=0",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      render_click(view, "toggle_form_budget", %{"cost" => "0"})

      submit(view, %{title: "Passeggiata"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert length(assigns.ideas) == 1
      idea = hd(assigns.ideas)
      assert idea.estimated_cost == 0
    end

    test "save success WITH budget=1000 (oltre) persists estimated_cost=1000",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      render_click(view, "toggle_form_budget", %{"cost" => "1000"})

      submit(view, %{title: "Crociera"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert length(assigns.ideas) == 1
      idea = hd(assigns.ideas)
      assert idea.estimated_cost == 1000
    end

    test "close_form resets @selected_cost to nil", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      render_click(view, "toggle_form_budget", %{"cost" => "100"})

      pre = :sys.get_state(view.pid).socket.assigns
      assert pre.selected_cost == 100

      render_click(view, "close_form")

      post = :sys.get_state(view.pid).socket.assigns
      assert post.form_visible? == false
      assert post.selected_cost == nil
    end

    test "open_form resets @selected_cost to nil even after close+reopen with prior pick",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      render_click(view, "toggle_form_budget", %{"cost" => "100"})
      render_click(view, "close_form")
      render_click(view, "toggle_form")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.form_visible? == true
      assert assigns.selected_cost == nil
    end

    # S2 — hostile toggle_form_budget uniform list (5 strings + 3 non-strings).
    for value <- ["175", "-50", "abc", "", "<script>"] do
      test "toggle_form_budget with hostile string #{inspect(value)} is a no-op",
           %{conn: conn} do
        view = mount_authenticated(conn) |> open_form()

        render_click(view, "toggle_form_budget", %{"cost" => unquote(value)})

        assigns = :sys.get_state(view.pid).socket.assigns
        assert assigns.selected_cost == nil
        assert Process.alive?(view.pid)
      end
    end

    for value <- [42, [], %{}] do
      test "toggle_form_budget with hostile non-string #{inspect(value)} is a no-op",
           %{conn: conn} do
        view = mount_authenticated(conn) |> open_form()

        render_click(view, "toggle_form_budget", %{
          "cost" => unquote(Macro.escape(value))
        })

        assigns = :sys.get_state(view.pid).socket.assigns
        assert assigns.selected_cost == nil
        assert Process.alive?(view.pid)
      end
    end

    # S3 — Save with hostile cost string surfaces "Budget non valido" + nothing persists.
    test "save with hostile cost '175' surfaces 'Budget non valido' and does not persist",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      mare = CategoriesFixtures.category_by_name!("mare")
      render_click(view, "toggle_category", %{"id" => "#{mare.id}"})

      pre_count = length(Ideajar.Ideas.list_ideas([]))

      html =
        render_submit(view, "save", %{
          "idea" => %{
            "title" => "X",
            "description" => "",
            "url" => "",
            "estimated_cost" => "175"
          }
        })

      assert html =~ "Budget non valido"
      assert length(Ideajar.Ideas.list_ideas([])) == pre_count
      assert Process.alive?(view.pid)
    end

    test "save with hostile cost 'abc' surfaces 'Budget non valido' (cast failure path)",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      mare = CategoriesFixtures.category_by_name!("mare")
      render_click(view, "toggle_category", %{"id" => "#{mare.id}"})

      pre_count = length(Ideajar.Ideas.list_ideas([]))

      html =
        render_submit(view, "save", %{
          "idea" => %{
            "title" => "X",
            "description" => "",
            "url" => "",
            "estimated_cost" => "abc"
          }
        })

      assert html =~ "Budget non valido"
      assert length(Ideajar.Ideas.list_ideas([])) == pre_count
      assert Process.alive?(view.pid)
    end

    # BB17 / A10 — DOM id distinctness across the 4 (eventually 5) chip families.
    test "with form open, chip ids across all families are distinct",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      html = render(view)

      ids =
        Regex.scan(
          ~r{id="(form-budget-chip-\d+|form-duration-chip-\w+|category-chip-\d+|filter-chip-\d+|filter-duration-chip-\w+)"},
          html
        )
        |> Enum.map(&Enum.at(&1, 1))

      assert ids == Enum.uniq(ids)

      # Sanity: each family is present with the expected count.
      assert length(Enum.filter(ids, &String.starts_with?(&1, "form-budget-chip-"))) == 7

      assert length(Enum.filter(ids, &String.starts_with?(&1, "form-duration-chip-"))) ==
               5

      assert length(Enum.filter(ids, &String.starts_with?(&1, "filter-duration-chip-"))) ==
               5
    end

    # A7 — form chip budget: no roving-tabindex hook, no explicit tabindex.
    test "form budget fieldset has no RovingTabindex hook and chips have no explicit tabindex",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      html = render(view)

      [budget_block] =
        Regex.run(~r{<legend[^>]*>\s*Budget\s*</legend>.*?</fieldset>}s, html) ||
          [nil] |> List.wrap()

      assert budget_block, "Expected the budget fieldset block to be present"
      refute budget_block =~ "RovingTabindex"
      refute budget_block =~ "data-roving-tabindex-group"

      # No form-budget-chip-* button carries an explicit tabindex attribute.
      offenders =
        Regex.scan(~r{<button[^>]*id="form-budget-chip-\d+"[^>]*tabindex[^>]*>}, html)

      assert offenders == []
    end
  end
end
