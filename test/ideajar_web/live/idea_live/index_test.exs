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
    # Slice 9 follow-up — the filter row collapses to a compact header
    # by default. Existing tests assert sub-block content at mount, so
    # this helper auto-expands. Use `mount_authenticated_collapsed/1`
    # for tests that exercise the collapse behaviour itself.
    render_click(view, "toggle_filters")
    view
  end

  defp mount_authenticated_collapsed(conn) do
    {:ok, view, _html} = live_isolated(conn, Index, session: @authenticated_session)
    view
  end

  # Slice 7a iter2: the location text input triggers a synchronous
  # `Ideajar.Geocoding.search/1` call when the query has ≥ 3 characters.
  # In tests the real HTTP boundary is replaced by `Req.Test` keyed under
  # `IdeajarStub` (see config/test.exs). LV runs in a separate process so
  # we must `allow/3` it to use the stub installed by the test process.
  # Default stub here returns `[]` so existing slice 7a step 4 tests that
  # fire `update_location_name` with ≥ 3 chars stay green without caring
  # about the dropdown; tests that exercise the dropdown install their
  # own stub before calling `allow_geocoding!/1`.
  defp stub_geocoding_empty!(view) do
    Req.Test.stub(IdeajarStub, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.send_resp(200, "[]")
    end)

    Req.Test.allow(IdeajarStub, self(), view.pid)
    view
  end

  defp allow_geocoding!(view) do
    Req.Test.allow(IdeajarStub, self(), view.pid)
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

    # Scenario: Add-idea form is collapsed by default. Slice 7b step 8
    # added two filter forms in the distance sub-block (search input +
    # slider), which are unrelated to the add-idea form gated on
    # `@form_visible?`. The assertion below targets the add-idea form
    # specifically (id="idea-form" + the "Salva" submit button).
    test "does not render the form on first mount", %{conn: conn} do
      assert view = mount_authenticated(conn)
      html = render(view)

      refute html =~ ~s(id="idea-form")
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
      # The idea-card external link carries a distinctive aria-label
      # ("Apri link in una nuova scheda") — no other link in the layout
      # uses it, so its absence proves we did not render a link block
      # for this title-only idea. (We can no longer use `target="_blank"`
      # as the proxy because slice 7a step 6 added an OSM attribution
      # link in the location-map dialog that legitimately uses it.)
      refute html =~ ~s(aria-label="Apri link in una nuova scheda")
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

      view = mount_authenticated(conn)
      html = render(view)

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

      view = mount_authenticated(conn)
      html = render(view)

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

      view = mount_authenticated(conn)
      html = render(view)

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

      view = mount_authenticated(conn)
      html = render(view)
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
      view = mount_authenticated(conn)
      html = render(view)

      for title <- ["Sirolo", "Uffizi", "Stadio", "Bagno", "Cinema"] do
        assert html =~ title
      end
    end

    # Scenario: Filter chip wiring
    test "renders 8 filter chips with correct phx-click and phx-value-id wiring",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

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
      view = mount_authenticated(conn)
      html = render(view)
      assert html =~ "Tocca per filtrare: 1× opzionale · 2× obbligatoria · 3× rimuovi"
    end

    # A17 — Visual row labels
    test "filter row has visible 'Filtra per:' label", %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)
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
      view = mount_authenticated(conn)
      html = render(view)
      count = Regex.scan(~r/Mostra tutte/, html) |> length()
      assert count == 0
    end

    test "filter active + non-empty list: exactly one Mostra tutte under filter row",
         %{conn: conn} do
      _ = seed_5_lv_ideas()
      view = mount_authenticated(conn)

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
      view = mount_authenticated(conn)
      html = render(view)

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

  # ── Slice 4 A13 / Slice 5 AA13 / Slice 6 BB18 / Slice 7b D5 / Slice 8 D5: out-of-scope guard ──
  # Slice 5 step 6 introduced `Durata`; slice 6 step 8 `Budget`; slice
  # 7b step 8 `Distanza` (+ scoped `Cerca punto di partenza`); slice 8
  # step 5 `Testo` (+ scoped `Cerca idee`). The guard now narrows to
  # the next out-of-scope feature placeholders. Positive assertions
  # pin all five sub-block labels.
  describe "out-of-scope guard (slice 4 A13 / 5 AA13 / 6 BB18 / 7b D5 / 8 D5)" do
    test "scoped 'Cerca punto di partenza' + 'Cerca idee' are the only Cerca-* strings",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

      # Two legitimate `Cerca…` strings: slice-7b reference search
      # placeholder and slice-8 text search placeholder.
      assert html =~ "Cerca punto di partenza"
      assert html =~ "Cerca idee"

      # Strip both legitimate strings and ensure no other `Cerca…`
      # string survives. Word-boundary regex avoids false positives
      # on `ricerca` inside the slice-8 helper text.
      stripped =
        html
        |> String.replace("Cerca punto di partenza", "")
        |> String.replace("Cerca idee", "")

      refute stripped =~ ~r/\bCerca\b/i
    end

    test "Durata appears as a visible sub-block label in the filter row",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)
      assert html =~ ~r{<p[^>]*class="[^"]*text-xs[^"]*"[^>]*>\s*Durata\s*</p>}
    end

    test "Budget appears as a visible sub-block label in the filter row (BB18)",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)
      assert html =~ ~r{<p[^>]*class="[^"]*text-xs[^"]*"[^>]*>\s*Budget\s*</p>}
    end

    test "Distanza appears as a visible sub-block label in the filter row (slice 7b D5)",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)
      assert html =~ ~r{<p[^>]*class="[^"]*text-xs[^"]*"[^>]*>\s*Distanza\s*</p>}
    end
  end

  describe "filter chip XSS regression (slice 4 S2)" do
    test "a category whose name contains <script> is escaped on the filter chip",
         %{conn: conn} do
      Repo.insert!(%Category{
        name: "<script>alert(1)</script>",
        display_order: 999
      })

      view = mount_authenticated(conn)
      html = render(view)

      assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
      refute html =~ "<script>alert(1)</script>"
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
      view = mount_authenticated(conn)
      html = render(view)

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
      view = mount_authenticated(conn)
      html = render(view)

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
      view = mount_authenticated(conn)
      html = render(view)

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

  describe "idea card budget badge (slice 6 step 5)" do
    # F17 — present: an idea with estimated_cost renders a badge with the IT
    # label.
    test "idea with estimated_cost: 100 renders <span data-testid=idea-budget-badge> with 'fino a 100€'",
         %{conn: conn} do
      mare = CategoriesFixtures.category_by_name!("mare")

      assert {:ok, _idea} =
               Ideajar.Ideas.create_idea(%{
                 title: "Sirolo",
                 category_ids: [mare.id],
                 estimated_cost: "100"
               })

      {:ok, _view, html} =
        live_isolated(conn, Index, session: @authenticated_session)

      [_full, inner] =
        Regex.run(
          ~r{<span[^>]*data-testid="idea-budget-badge"[^>]*>(.*?)</span>}s,
          html
        )

      assert String.trim(inner) == "fino a 100€"
    end

    # F17 — absent: an idea without estimated_cost renders no badge for it.
    test "idea without estimated_cost renders NO data-testid=idea-budget-badge element",
         %{conn: conn} do
      mare = CategoriesFixtures.category_by_name!("mare")

      assert {:ok, _idea} =
               Ideajar.Ideas.create_idea(%{
                 title: "Bagno improvviso",
                 category_ids: [mare.id]
               })

      {:ok, _view, html} =
        live_isolated(conn, Index, session: @authenticated_session)

      refute html =~ ~s(data-testid="idea-budget-badge")
    end

    # F17 — gratis (cost = 0) is NOT NULL and must render the badge.
    # This is the critical edge case: `:if={idea.estimated_cost}` would still
    # render in HEEx because `0` is truthy in Elixir, but using
    # `:if={not is_nil(idea.estimated_cost)}` makes the intent explicit and
    # robust against future template helper boolean-coercion changes.
    test "idea with estimated_cost: 0 (gratis) DOES render the badge",
         %{conn: conn} do
      mare = CategoriesFixtures.category_by_name!("mare")

      assert {:ok, _idea} =
               Ideajar.Ideas.create_idea(%{
                 title: "Caffè al volo",
                 category_ids: [mare.id],
                 estimated_cost: "0"
               })

      {:ok, _view, html} =
        live_isolated(conn, Index, session: @authenticated_session)

      [_full, inner] =
        Regex.run(
          ~r{<span[^>]*data-testid="idea-budget-badge"[^>]*>(.*?)</span>}s,
          html
        )

      assert String.trim(inner) == "gratis"
    end

    # Multiple ideas: only those with estimated_cost set render a badge.
    # 3 ideas (cost=100, cost=0, no cost) → exactly 2 budget badges.
    test "three ideas (cost=100, cost=0, no cost) render exactly two budget badges",
         %{conn: conn} do
      mare = CategoriesFixtures.category_by_name!("mare")

      assert {:ok, _} =
               Ideajar.Ideas.create_idea(%{
                 title: "Sirolo",
                 category_ids: [mare.id],
                 estimated_cost: "100"
               })

      assert {:ok, _} =
               Ideajar.Ideas.create_idea(%{
                 title: "Caffè al volo",
                 category_ids: [mare.id],
                 estimated_cost: "0"
               })

      assert {:ok, _} =
               Ideajar.Ideas.create_idea(%{
                 title: "Bagno improvviso",
                 category_ids: [mare.id]
               })

      {:ok, _view, html} =
        live_isolated(conn, Index, session: @authenticated_session)

      badges = Regex.scan(~r/data-testid="idea-budget-badge"/, html)
      assert length(badges) == 2
    end

    # F18 — each canonical Budget bucket renders its IT label in the badge.
    for cost <- Ideajar.Ideas.Budget.values() do
      label = Ideajar.Ideas.Budget.label(cost)

      test "estimated_cost #{inspect(cost)} renders the IT label #{inspect(label)} in the badge",
           %{conn: conn} do
        mare = CategoriesFixtures.category_by_name!("mare")

        assert {:ok, _} =
                 Ideajar.Ideas.create_idea(%{
                   title: "T-#{unquote(Integer.to_string(cost))}",
                   category_ids: [mare.id],
                   estimated_cost: unquote(Integer.to_string(cost))
                 })

        {:ok, _view, html} =
          live_isolated(conn, Index, session: @authenticated_session)

        [_full, inner] =
          Regex.run(
            ~r{<span[^>]*data-testid="idea-budget-badge"[^>]*>(.*?)</span>}s,
            html
          )

        assert String.trim(inner) == unquote(label)
      end
    end

    # Position pin — the budget badge appears AFTER <.duration_badge> in the
    # idea card DOM source order (parallel to slice 5 step 4 position pin
    # which placed the duration badge after the categories list).
    test "budget badge appears after duration badge within the idea card",
         %{conn: conn} do
      mare = CategoriesFixtures.category_by_name!("mare")

      assert {:ok, _} =
               Ideajar.Ideas.create_idea(%{
                 title: "Sirolo",
                 category_ids: [mare.id],
                 duration: "weekend",
                 estimated_cost: "200"
               })

      {:ok, _view, html} =
        live_isolated(conn, Index, session: @authenticated_session)

      duration_pos =
        case :binary.match(html, ~s(data-testid="idea-duration-badge")) do
          {pos, _} -> pos
          :nomatch -> nil
        end

      budget_pos =
        case :binary.match(html, ~s(data-testid="idea-budget-badge")) do
          {pos, _} -> pos
          :nomatch -> nil
        end

      assert is_integer(duration_pos)
      assert is_integer(budget_pos)
      assert duration_pos < budget_pos
    end
  end

  describe "idea card location badge (slice 7a step 5)" do
    # F16 — present (state b: name only, no coords). The badge surfaces on
    # idea cards whenever `idea.location_name != nil`, regardless of whether
    # coords are also set. Slice 7b's distance filter will use coords; this
    # slice only renders the name with a 📍 prefix.
    test "idea with location_name: \"Sirolo, AN\" renders <span data-testid=idea-location-badge> with '📍 Sirolo, AN'",
         %{conn: conn} do
      mare = CategoriesFixtures.category_by_name!("mare")

      assert {:ok, _idea} =
               Ideajar.Ideas.create_idea(%{
                 title: "Sirolo",
                 category_ids: [mare.id],
                 location_name: "Sirolo, AN"
               })

      {:ok, _view, html} =
        live_isolated(conn, Index, session: @authenticated_session)

      [_full, inner] =
        Regex.run(
          ~r{<span[^>]*data-testid="idea-location-badge"[^>]*>(.*?)</span>}s,
          html
        )

      assert String.trim(inner) == "📍 Sirolo, AN"
    end

    # F16 — absent: an idea without location_name renders no location badge.
    test "idea without location_name renders NO data-testid=idea-location-badge element",
         %{conn: conn} do
      mare = CategoriesFixtures.category_by_name!("mare")

      assert {:ok, _idea} =
               Ideajar.Ideas.create_idea(%{
                 title: "Cinema stasera",
                 category_ids: [mare.id]
               })

      {:ok, _view, html} =
        live_isolated(conn, Index, session: @authenticated_session)

      refute html =~ ~s(data-testid="idea-location-badge")
    end

    # State (b) name-only is the canonical "no map yet" path: utente scrive
    # "Casa di nonna" senza pin. Badge shown anyway.
    test "idea with location_name set and lat/lng nil (state b) DOES render the badge",
         %{conn: conn} do
      mare = CategoriesFixtures.category_by_name!("mare")

      assert {:ok, idea} =
               Ideajar.Ideas.create_idea(%{
                 title: "Picnic",
                 category_ids: [mare.id],
                 location_name: "Casa di nonna"
               })

      assert idea.location_name == "Casa di nonna"
      assert idea.lat == nil
      assert idea.lng == nil

      {:ok, _view, html} =
        live_isolated(conn, Index, session: @authenticated_session)

      [_full, inner] =
        Regex.run(
          ~r{<span[^>]*data-testid="idea-location-badge"[^>]*>(.*?)</span>}s,
          html
        )

      assert String.trim(inner) == "📍 Casa di nonna"
    end

    # Multiple ideas: only those with location_name set render a badge.
    # 2 ideas (one with name, one without) → exactly 1 location badge.
    test "two ideas (one with location_name, one without) render exactly one location badge",
         %{conn: conn} do
      mare = CategoriesFixtures.category_by_name!("mare")

      assert {:ok, _} =
               Ideajar.Ideas.create_idea(%{
                 title: "Sirolo",
                 category_ids: [mare.id],
                 location_name: "Sirolo, AN"
               })

      assert {:ok, _} =
               Ideajar.Ideas.create_idea(%{
                 title: "Cinema stasera",
                 category_ids: [mare.id]
               })

      {:ok, _view, html} =
        live_isolated(conn, Index, session: @authenticated_session)

      badges = Regex.scan(~r/data-testid="idea-location-badge"/, html)
      assert length(badges) == 1
    end

    # S2 — XSS regression: location_name flows through HEEx auto-escape.
    # A `<script>` payload persisted via `create_idea/1` (it's a plain
    # string field, no character whitelist) must surface as escaped text
    # in the rendered HTML — never as an executable script tag.
    test "idea with hostile location_name <script> renders escaped, NOT raw <script>",
         %{conn: conn} do
      mare = CategoriesFixtures.category_by_name!("mare")

      assert {:ok, _idea} =
               Ideajar.Ideas.create_idea(%{
                 title: "Hostile",
                 category_ids: [mare.id],
                 location_name: "<script>alert(1)</script>"
               })

      {:ok, _view, html} =
        live_isolated(conn, Index, session: @authenticated_session)

      [_full, inner] =
        Regex.run(
          ~r{<span[^>]*data-testid="idea-location-badge"[^>]*>(.*?)</span>}s,
          html
        )

      assert inner =~ "&lt;script&gt;"
      assert inner =~ "&lt;/script&gt;"
      refute inner =~ "<script>"
      refute inner =~ "</script>"
    end

    # Position pin — the location badge appears AFTER <BudgetChip.budget_badge>
    # in the idea card DOM source order, and BEFORE the closing </li> of the
    # card (parallel to slice 6 step 5 position pin which placed the budget
    # badge after the duration badge).
    test "location badge appears after budget badge within the idea card",
         %{conn: conn} do
      mare = CategoriesFixtures.category_by_name!("mare")

      assert {:ok, _} =
               Ideajar.Ideas.create_idea(%{
                 title: "Sirolo",
                 category_ids: [mare.id],
                 estimated_cost: "200",
                 location_name: "Sirolo, AN"
               })

      {:ok, _view, html} =
        live_isolated(conn, Index, session: @authenticated_session)

      budget_pos =
        case :binary.match(html, ~s(data-testid="idea-budget-badge")) do
          {pos, _} -> pos
          :nomatch -> nil
        end

      location_pos =
        case :binary.match(html, ~s(data-testid="idea-location-badge")) do
          {pos, _} -> pos
          :nomatch -> nil
        end

      # Find the FIRST `</li>` that closes the idea card — i.e. the first
      # one that occurs at or after `location_pos`. The earlier `</li>`
      # occurrences in the HTML close the inner category-badge list items
      # (`<ul data-testid="idea-categories">`), not the idea card itself.
      end_of_card_pos =
        :binary.matches(html, "</li>")
        |> Enum.find_value(fn {pos, _} ->
          if pos >= location_pos, do: pos, else: nil
        end)

      assert is_integer(budget_pos)
      assert is_integer(location_pos)
      assert is_integer(end_of_card_pos)
      assert budget_pos < location_pos
      assert location_pos < end_of_card_pos
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

  # Slice 9 step 2 — bridge helper. Pre-slice-9 the budget filter was a
  # chip toggle; tests called `cycle_budget(view, 100)` to set the
  # filter to "fino a 100€". Slice 9 replaced the chips with an index
  # slider (0..7), so this helper now translates the legacy cost
  # argument to the slider event so the slice-6 step-9 integration
  # tests keep working unchanged. Cost → index mapping mirrors
  # `Budget.index_to_value/1` inverse.
  @cost_to_index %{0 => 1, 20 => 2, 50 => 3, 100 => 4, 200 => 5, 500 => 6, 1000 => 7}
  defp cycle_budget(view, cost) when is_integer(cost) and is_map_key(@cost_to_index, cost) do
    index = Map.fetch!(@cost_to_index, cost)
    render_hook(view, "update_max_budget", %{"value" => Integer.to_string(index)})
    view
  end

  describe "duration filter sub-block (slice 5 step 6)" do
    # 1. Sub-block durata reso (AA11/AA21)
    test "renders <div role=group aria-label='Filtra per durata'> with hook + 5 chip buttons",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

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
      view = mount_authenticated(conn)
      html = render(view)

      assert html =~ ~r{<p[^>]*class="[^"]*text-xs[^"]*"[^>]*>\s*Categorie\s*</p>}
      assert html =~ ~r{<p[^>]*class="[^"]*text-xs[^"]*"[^>]*>\s*Durata\s*</p>}
    end

    # 3. Helper text NULL-exclusion (AA19/A12)
    test "renders the NULL-exclusion helper text exactly once, between sub-label and chip group",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

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
      view = mount_authenticated(conn)
      html = render(view)
      assert html =~ ~s(aria-label="Filtra per categoria")
    end

    # 5. Secondo rover: only 1 tabindex=0 on filter-duration-chip-*.
    test "secondo rover: only first duration chip (poche_ore) has tabindex=0",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

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
    # and the list returns to all 6 ideas. (Slice 6 step 7 removed the
    # live-region; the assigns + DOM list re-render are the substantive
    # invariants.)
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
      view = mount_authenticated(conn)
      html = render(view)

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
    # :giornata idea the filtered list is unchanged. (Slice 6 step 7 removed
    # the live-region; @ideas length and DOM contents carry the invariant.)
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

  # ── Slice 6 Step 7: filter-status live-region removal cascade ──
  #
  # The slice-4/slice-5 `<div role="status" aria-live="polite" id="filter-status">`
  # is removed entirely (BB9, A5, D-LR1). The chip aria-pressed state and the
  # `Mostra tutte` affordance carry the announce-the-filter-state burden;
  # the redundant live-region was over-engineered for a 2-user IT-only app.
  #
  # These tests are positive-of-absence: they assert the live-region is NOT
  # present at mount, after cycle_filter, after toggle_duration_filter, and
  # after clear_filters. The filter-row aria-live="polite" (slice 2 success
  # flash sits in its own live-region — unrelated) is NOT asserted against.
  describe "filter-status live-region removed (slice 6 step 7)" do
    test "mount: no element with id=\"filter-status\" exists in the DOM",
         %{conn: conn} do
      _ = seed_5_lv_ideas()
      view = mount_authenticated(conn)
      html = render(view)

      refute html =~ ~r/id="filter-status"/
    end

    test "mount: no role=\"status\" element appears inside the filter-row section",
         %{conn: conn} do
      _ = seed_5_lv_ideas()
      view = mount_authenticated(conn)
      html = render(view)

      [filter_row] =
        Regex.run(
          ~r{<section[^>]*data-testid="filter-row".*?</section>}s,
          html
        ) || [nil] |> List.wrap()

      assert filter_row
      refute filter_row =~ ~r/role="status"/
      refute filter_row =~ ~r/aria-live="polite"/
    end

    test "after cycle_filter: no filter-status live-region appears", %{conn: conn} do
      _ = seed_5_lv_ideas()
      view = mount_authenticated(conn)

      html = view |> cycle_filter("mare") |> render()
      refute html =~ ~r/id="filter-status"/
    end

    test "after toggle_duration_filter: no filter-status live-region appears",
         %{conn: conn} do
      _ = seed_5_lv_ideas()
      view = mount_authenticated(conn)

      html = view |> cycle_duration(:weekend) |> render()
      refute html =~ ~r/id="filter-status"/
    end

    test "after clear_filters: no filter-status live-region nor 'Filtri rimossi' appears",
         %{conn: conn} do
      _ = seed_5_lv_ideas()
      view = mount_authenticated(conn)

      html = render_click(view, "clear_filters")
      refute html =~ ~r/id="filter-status"/
      refute html =~ "Filtri rimossi"
    end
  end

  # ── Slice 6 Step 9: clear_filters extension + combined 3-way + isolation ──
  #
  # Most tests in this block are regression pins: the architecture is already
  # correct from steps 6–8 (combined AND in `Ideas.list_ideas/1`, separate
  # form/filter assigns, `filter_active?/3` covering all three groups). The
  # only behavioural change in step 9 is the `clear_filters` handler being
  # extended to also reset `@cost_filter`. The remaining tests prevent
  # future drift.
  describe "clear_filters and combined filters (slice 6 step 9)" do
    # Combined seeder — ideas with categories + duration + cost, so the
    # 3-way AND can be exercised concretely. Mirrors the priced variant
    # used in step 8 with durations layered on for F13.
    defp insert_idea_full!(title, category_names, duration, cost, %DateTime{} = at) do
      cats = Enum.map(category_names, &CategoriesFixtures.category_by_name!/1)

      idea =
        %Idea{title: title, duration: duration, estimated_cost: cost}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:categories, cats)
        |> Repo.insert!()

      Repo.update!(
        Ecto.Changeset.change(idea, inserted_at: at, updated_at: at),
        force: true
      )
    end

    defp seed_6_lv_ideas_full do
      %{
        sirolo:
          insert_idea_full!(
            "Sirolo",
            ["mare", "viaggio"],
            :weekend,
            200,
            ~U[2026-04-27 10:00:00Z]
          ),
        parigi:
          insert_idea_full!(
            "Parigi",
            ["viaggio"],
            :weekend,
            1000,
            ~U[2026-04-27 10:01:00Z]
          ),
        uffizi:
          insert_idea_full!(
            "Uffizi",
            ["museo", "cultura"],
            :giornata,
            50,
            ~U[2026-04-27 10:02:00Z]
          ),
        stadio:
          insert_idea_full!(
            "Stadio",
            ["sport"],
            :poche_ore,
            100,
            ~U[2026-04-27 10:03:00Z]
          ),
        cinema:
          insert_idea_full!(
            "Cinema",
            ["cinema", "cultura"],
            :mezza_giornata,
            20,
            ~U[2026-04-27 10:04:00Z]
          ),
        bagno:
          insert_idea_full!(
            "Bagno",
            ["mare"],
            nil,
            nil,
            ~U[2026-04-27 10:05:00Z]
          )
      }
    end

    # 1. F16 — clear_filters resets ALL three filter groups (categoria +
    # durata + budget) and the list returns to all 6 ideas. The categoria
    # and durata reset is regression-pinned by slice 5 step 7; the budget
    # reset is the actual GREEN of step 9.
    test "clear_filters resets filter_state, duration_filter AND cost_filter (F16)",
         %{conn: conn} do
      _ = seed_6_lv_ideas_full()
      view = mount_authenticated(conn)
      mare = CategoriesFixtures.category_by_name!("mare")

      view |> cycle_duration(:weekend)
      view |> cycle_filter("mare") |> cycle_filter("mare")
      view |> cycle_budget(100)

      pre = :sys.get_state(view.pid).socket.assigns
      assert pre.filter_state == %{mare.id => :required}
      assert pre.duration_filter == MapSet.new([:weekend])
      assert pre.max_budget_index == 4

      html = render_click(view, "clear_filters")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.filter_state == %{}
      assert assigns.duration_filter == MapSet.new()
      assert assigns.max_budget_index == 0

      for title <- ["Sirolo", "Parigi", "Uffizi", "Stadio", "Cinema", "Bagno"] do
        assert html =~ title, "Expected #{title} after clear_filters"
      end
    end

    # 2. S7 — idempotency: calling clear_filters when ALL three groups are
    # already empty must not crash and must leave each at its empty
    # representation. Extends the slice 5 step 7 idempotency pin to budget.
    test "clear_filters is idempotent when all three groups are already empty (S7)",
         %{conn: conn} do
      _ = seed_6_lv_ideas_full()
      view = mount_authenticated(conn)

      pre = :sys.get_state(view.pid).socket.assigns
      assert pre.filter_state == %{}
      assert pre.duration_filter == MapSet.new()
      assert pre.max_budget_index == 0

      render_click(view, "clear_filters")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.filter_state == %{}
      assert assigns.duration_filter == MapSet.new()
      assert assigns.max_budget_index == 0
      assert Process.alive?(view.pid)
    end

    # 3. F13 — combined 3-way AND across categoria + durata + budget.
    # viaggio:required + weekend + cost <= 500 → Sirolo only.
    #   * Parigi: viaggio + weekend, but cost 1000 > 500 → excluded
    #   * Bagno: NULL duration AND NULL cost → excluded twice over
    #   * Uffizi/Stadio/Cinema: lack viaggio → excluded
    test "viaggio required + weekend + cost <= 500: only Sirolo matches (F13 3-way AND)",
         %{conn: conn} do
      _ = seed_6_lv_ideas_full()
      view = mount_authenticated(conn)

      view |> cycle_filter("viaggio") |> cycle_filter("viaggio")
      view |> cycle_duration(:weekend)
      html = view |> cycle_budget(500) |> render()

      assert html =~ "Sirolo"
      refute html =~ "Parigi"
      refute html =~ "Uffizi"
      refute html =~ "Stadio"
      refute html =~ "Cinema"
      refute html =~ "Bagno"
    end

    # 4. Combined 3-way no-match → empty-filter state (NOT workspace-empty).
    # passeggiata is a category none of the seeded ideas carry; layering
    # duration + budget on top keeps the filtered list empty. The empty-
    # filter copy must appear with its single Mostra tutte affordance.
    test "passeggiata required + weekend + cost=100 → empty-filter state (combined no-match)",
         %{conn: conn} do
      _ = seed_6_lv_ideas_full()
      view = mount_authenticated(conn)

      view |> cycle_filter("passeggiata") |> cycle_filter("passeggiata")
      view |> cycle_duration(:weekend)
      html = view |> cycle_budget(100) |> render()

      assert html =~ "Nessuna idea per i filtri attivi."
      assert html =~ ~s(data-testid="empty-filter-state")
      assert html =~ "Mostra tutte"
      refute html =~ "Nessuna idea ancora. Aggiungine una qui sopra."
    end

    # 5a. F10 extended to 3-way: combined active + non-empty list →
    # exactly ONE Mostra tutte under the filter row, none in the empty
    # branch (the list isn't empty). Pinned in slice 5 step 7 for 2-way;
    # extended here to cover budget as the third group.
    test "combined 3-way active + non-empty list: exactly one Mostra tutte under filter row",
         %{conn: conn} do
      _ = seed_6_lv_ideas_full()
      view = mount_authenticated(conn)

      view |> cycle_filter("viaggio") |> cycle_filter("viaggio")
      view |> cycle_duration(:weekend)
      html = view |> cycle_budget(500) |> render()

      count = Regex.scan(~r/Mostra tutte/, html) |> length()
      assert count == 1
      assert html =~ ~s(id="mostra-tutte")
      refute html =~ ~s(id="mostra-tutte-empty")
    end

    # 5b. Combined 3-way active + empty list → exactly ONE Mostra tutte
    # INSIDE the empty-filter message, none under the filter row.
    test "combined 3-way active + empty list: exactly one Mostra tutte inside empty-filter state",
         %{conn: conn} do
      _ = seed_6_lv_ideas_full()
      view = mount_authenticated(conn)

      view |> cycle_filter("passeggiata") |> cycle_filter("passeggiata")
      view |> cycle_duration(:weekend)
      html = view |> cycle_budget(100) |> render()

      count = Regex.scan(~r/Mostra tutte/, html) |> length()
      assert count == 1
      assert html =~ ~s(id="mostra-tutte-empty")
      refute html =~ ~s(id="mostra-tutte")
    end

    # 6. F19 — budget filter survives form submission. Cycle cost=200 on,
    # open the form, submit a valid idea with cost=100; @cost_filter must
    # remain 200 and the new idea must be both persisted AND visible in
    # the filtered list (cost 100 ≤ 200).
    test "F19: cost_filter survives form submit (regression pin)", %{conn: conn} do
      _ = seed_6_lv_ideas_full()
      view = mount_authenticated(conn)

      view |> cycle_budget(200)
      pre = :sys.get_state(view.pid).socket.assigns
      assert pre.max_budget_index == 5

      view |> open_form()
      render_hook(view, "update_form_budget", %{"value" => "4"})
      html = submit(view, %{title: "BudgetSurvivor"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.max_budget_index == 5
      persisted = Repo.get_by(Idea, title: "BudgetSurvivor")
      assert persisted
      assert persisted.estimated_cost == 100
      assert html =~ "BudgetSurvivor"
    end

    # 7. F20 — new idea outside the active budget filter is hidden. With
    # cost_filter=50 on, submitting an idea with cost=200 persists it but
    # leaves it out of the rendered list (200 > 50).
    test "F20: new idea with cost=200 hidden when cost_filter=50 active (regression pin)",
         %{conn: conn} do
      _ = seed_6_lv_ideas_full()
      view = mount_authenticated(conn)

      view |> cycle_budget(50)

      view |> open_form()
      render_hook(view, "update_form_budget", %{"value" => "5"})
      html = submit(view, %{title: "OltreFiltro"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.max_budget_index == 3
      persisted = Repo.get_by(Idea, title: "OltreFiltro")
      assert persisted
      assert persisted.estimated_cost == 200
      refute html =~ "OltreFiltro"
    end

    # 8. F20 — new NULL-cost idea hidden when cost_filter is on. Mirrors
    # the AA7 / step 8 NULL-exclude invariant for budget specifically:
    # ideas created *while* the filter is active are subject to the same
    # uniform NULL-exclude rule as pre-existing ones.
    test "F20: new NULL-cost idea hidden when cost_filter=50 active (NULL-exclude regression pin)",
         %{conn: conn} do
      _ = seed_6_lv_ideas_full()
      view = mount_authenticated(conn)

      view |> cycle_budget(50)
      total_before = length(Ideajar.Ideas.list_ideas([]))

      view |> open_form()
      # No form-budget chip pressed → @selected_cost stays nil →
      # maybe_inject_budget leaves params untouched → idea persisted with
      # estimated_cost: nil.
      html = submit(view, %{title: "SenzaPrezzo"})

      total_after = length(Ideajar.Ideas.list_ideas([]))
      assert total_after == total_before + 1

      persisted = Repo.get_by(Idea, title: "SenzaPrezzo")
      assert persisted
      assert persisted.estimated_cost == nil

      refute html =~ "SenzaPrezzo"

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.max_budget_index == 3
    end

    # 9. Isolation — clear_filters does NOT touch the form's @selected_cost
    # nor the form chip's aria-pressed state. The form budget belongs to
    # the form sub-block; @cost_filter belongs to the filter row;
    # clear_filters only acts on the latter. Parallel to slice 5 step 8
    # isolation #4.
    test "isolation: clear_filters does not touch form @selected_cost (regression pin)",
         %{conn: conn} do
      _ = seed_6_lv_ideas_full()
      view = mount_authenticated(conn) |> open_form()
      render_hook(view, "update_form_budget", %{"value" => "4"})

      pre = :sys.get_state(view.pid).socket.assigns
      assert pre.form_budget_index == 4

      view |> cycle_budget(200)
      render_click(view, "clear_filters")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.form_budget_index == 4
      assert assigns.max_budget_index == 0
    end

    # 10. Isolation — the filter slider does NOT touch the form's
    # @selected_cost (slice 9 update of the original chip-vs-chip
    # isolation pin: filter is now slider, form is still chip in step 2).
    # The two state slots live side by side and never cross.
    test "isolation: filter slider update_max_budget does not touch form @selected_cost",
         %{conn: conn} do
      _ = seed_6_lv_ideas_full()
      view = mount_authenticated(conn) |> open_form()
      render_hook(view, "update_form_budget", %{"value" => "4"})

      pre = :sys.get_state(view.pid).socket.assigns
      assert pre.form_budget_index == 4

      view |> cycle_budget(200)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.form_budget_index == 4
      assert assigns.max_budget_index == 5
    end

    # 11. Refresh — @cost_filter is process-local state. A fresh mount
    # (simulating a page refresh) starts with the filter cleared, even if
    # a prior LV had it active. Parallel to slice 5 step 8 refresh pin
    # for @duration_filter.
    test "refresh resets @cost_filter to nil (regression pin)", %{conn: conn} do
      _ = seed_6_lv_ideas_full()
      view = mount_authenticated(conn)
      view |> cycle_budget(100)
      pre = :sys.get_state(view.pid).socket.assigns
      assert pre.max_budget_index == 4

      {:ok, fresh_view, _html} =
        live_isolated(conn, Index, session: @authenticated_session)

      assigns = :sys.get_state(fresh_view.pid).socket.assigns
      assert assigns.max_budget_index == 0
      assert assigns.duration_filter == MapSet.new()
      assert assigns.filter_state == %{}
    end

    # 12. Strategic W2 — pin the arity of `filter_active?`. Arity history:
    # slice 4 `/1`, slice 5 `/2`, slice 6 `/3`, slice 7b `/5`, slice 8
    # `/1` socket-based (DD-S8-7). Pinning the current shape and the
    # disappearance of the legacy positional shapes prevents a future
    # regression from re-introducing them.
    test "filter_active?/1 socket-based is exported; legacy /3 + /5 are not" do
      assert function_exported?(IdeajarWeb.IdeaLive.Index, :filter_active?, 1)
      refute function_exported?(IdeajarWeb.IdeaLive.Index, :filter_active?, 3)
      refute function_exported?(IdeajarWeb.IdeaLive.Index, :filter_active?, 5)
    end
  end

  # ── Slice 7a step 4: form Posizione fieldset, text input, LV handlers ──
  #
  # Pure form/LV layer wiring of the location domain (slice 7a step 3 added
  # the schema + cross-field validator). The slice 7a iter2 UX rework
  # replaced the Leaflet map picker with a Google-Maps-style search
  # dropdown — the `📍 Apri mappa` button, the `📍 Coordinate impostate`
  # hint, the `<dialog>` shell, and the `set_location` handler are all
  # gone (see "location search dropdown (slice 7a iter2)" describe).
  #
  # Lifecycle parallel to `reset_categories/1` (slice 3), `reset_duration/1`
  # (slice 5) and `reset_budget/1` (slice 6): a dedicated `reset_location/1`
  # helper fires on mount, toggle_form open, close_form, and save success.
  describe "form location field (slice 7a step 4)" do
    test "mount: @selected_location_name, @selected_lat, @selected_lng are nil",
         %{conn: conn} do
      view = mount_authenticated(conn)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_location_name == nil
      assert assigns.selected_lat == nil
      assert assigns.selected_lng == nil
    end

    test "opening the form renders <legend>Posizione</legend> with NO asterisk + <label>Luogo</label> + text input wired to update_location_name",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render_click(view, "toggle_form")

      [pos_legend] =
        Regex.run(~r{<legend[^>]*>\s*Posizione\s*</legend>}, html) ||
          [nil] |> List.wrap()

      assert pos_legend, "Expected <legend>Posizione</legend> to be rendered"
      refute pos_legend =~ "*"

      assert html =~ ~r{<label[^>]*for="idea-location-name"[^>]*>\s*Luogo\s*</label>}

      [input_tag] =
        Regex.run(~r{<input[^>]*id="idea-location-name"[^>]*>}, html) ||
          [nil] |> List.wrap()

      assert input_tag, "Expected the location-name text input to be rendered"
      assert input_tag =~ ~s(phx-change="update_location_name")
      assert input_tag =~ ~s(placeholder="es. Casa di nonna")
      assert input_tag =~ ~s(maxlength="200")
    end

    test "no location set: 'Rimuovi posizione' button is NOT rendered",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      html = render(view)

      refute html =~ "Rimuovi posizione"
    end

    test "iter2: no '📍 Apri mappa' button rendered (Leaflet picker removed)",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      html = render(view)

      refute html =~ "Apri mappa"
    end

    test "iter2: no '📍 Coordinate impostate' inline hint rendered (replaced by search dropdown)",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      html = render(view)

      refute html =~ "Coordinate impostate"
    end

    test "update_location_name event sets @selected_location_name and leaves lat/lng nil",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form() |> stub_geocoding_empty!()

      render_change(view, "update_location_name", %{"name" => "Casa di nonna"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_location_name == "Casa di nonna"
      assert assigns.selected_lat == nil
      assert assigns.selected_lng == nil
    end

    test "after update_location_name: 'Rimuovi posizione' button is rendered",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form() |> stub_geocoding_empty!()

      html = render_change(view, "update_location_name", %{"name" => "Casa di nonna"})

      assert html =~ "Rimuovi posizione"
    end

    test "remove_location event resets all 3 location assigns and hides the 'Rimuovi posizione' button",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form() |> stub_geocoding_empty!()

      render_change(view, "update_location_name", %{"name" => "Casa di nonna"})

      pre = :sys.get_state(view.pid).socket.assigns
      assert pre.selected_location_name == "Casa di nonna"

      html = render_click(view, "remove_location")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_location_name == nil
      assert assigns.selected_lat == nil
      assert assigns.selected_lng == nil

      refute html =~ "Rimuovi posizione"
    end

    test "save success state (b) name-only persists location_name, lat=nil, lng=nil and resets assigns",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form() |> stub_geocoding_empty!()

      render_change(view, "update_location_name", %{"name" => "Casa di nonna"})

      html = submit(view, %{title: "Picnic"})
      assert html =~ "Idea aggiunta"

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_location_name == nil
      assert assigns.selected_lat == nil
      assert assigns.selected_lng == nil
      assert assigns.form_visible? == false
      assert length(assigns.ideas) == 1

      idea = hd(assigns.ideas)
      assert idea.location_name == "Casa di nonna"
      assert idea.lat == nil
      assert idea.lng == nil
    end

    test "save success state (a) no location input persists location_name, lat, lng all nil",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      submit(view, %{title: "Cinema stasera"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert length(assigns.ideas) == 1

      idea = hd(assigns.ideas)
      assert idea.location_name == nil
      assert idea.lat == nil
      assert idea.lng == nil
    end

    test "close_form resets @selected_location_name, @selected_lat, @selected_lng to nil",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form() |> stub_geocoding_empty!()

      render_change(view, "update_location_name", %{"name" => "Casa di nonna"})

      pre = :sys.get_state(view.pid).socket.assigns
      assert pre.selected_location_name == "Casa di nonna"

      render_click(view, "close_form")

      post = :sys.get_state(view.pid).socket.assigns
      assert post.form_visible? == false
      assert post.selected_location_name == nil
      assert post.selected_lat == nil
      assert post.selected_lng == nil
    end

    test "open_form resets @selected_location_name to nil even after close+reopen with prior input",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form() |> stub_geocoding_empty!()

      render_change(view, "update_location_name", %{"name" => "Casa di nonna"})
      render_click(view, "close_form")
      render_click(view, "toggle_form")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.form_visible? == true
      assert assigns.selected_location_name == nil
      assert assigns.selected_lat == nil
      assert assigns.selected_lng == nil
    end

    # CC22 hostile-uniform list — 5 hostile shapes for `update_location_name`.
    # Missing `"name"` key, non-binary name (integer, list, map, nil) → no-op:
    # @selected_location_name stays at its prior value (nil here) and the LV
    # process remains alive.
    #
    # We use `render_hook/3` (not `render_change/3`) to bypass the form
    # encoder that would coerce `42` → `"42"` and `nil` → `""` before
    # reaching the handler. The handler's catchall must exercise the
    # non-binary clauses on the wire shape itself, not the post-form-cast
    # one.
    for {label, payload} <- [
          {"missing key", %{}},
          {"integer", %{"name" => 42}},
          {"list", %{"name" => []}},
          {"map", %{"name" => %{}}},
          {"nil", %{"name" => nil}}
        ] do
      test "update_location_name with hostile #{label} payload is a no-op",
           %{conn: conn} do
        view = mount_authenticated(conn) |> open_form()

        render_hook(view, "update_location_name", unquote(Macro.escape(payload)))

        assigns = :sys.get_state(view.pid).socket.assigns
        assert assigns.selected_location_name == nil
        assert assigns.selected_lat == nil
        assert assigns.selected_lng == nil
        assert Process.alive?(view.pid)
      end
    end

    # Pin DOM source order: Categorie → Durata → Budget → Posizione → Salva.
    # The save button must remain the last interactive element of the form
    # so screen readers reach all fieldsets first.
    test "form fieldset order: Categorie → Durata → Budget → Posizione → Salva",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      html = render(view)

      categorie_idx = :binary.match(html, "Categorie") |> elem(0)
      durata_idx = :binary.match(html, ">Durata<") |> elem(0)
      budget_idx = :binary.match(html, ">Budget<") |> elem(0)
      posizione_idx = :binary.match(html, ">Posizione<") |> elem(0)
      salva_idx = :binary.match(html, ">\n        Salva\n      <") |> elem(0)

      assert categorie_idx < durata_idx
      assert durata_idx < budget_idx
      assert budget_idx < posizione_idx
      assert posizione_idx < salva_idx
    end
  end

  # ── Slice 7a iter2: search dropdown (replaces map picker) ──
  #
  # The text input drives a debounced (300ms client-side) `phx-change`
  # event into `update_location_name`. When the trimmed query has at
  # least 3 characters the handler calls `Ideajar.Geocoding.search/1`
  # synchronously and assigns `:location_search_results` +
  # `:location_search_state` (`:idle | :searching | :empty | :results`).
  # Clicking a result populates the 3 location assigns; clicking
  # outside fires `dismiss_location_search`. Decision C1: typing
  # after a previous select clears lat/lng so name-only-state-(b)
  # reasserts itself once the typed string diverges from the picked
  # one. The `Geocoding.search/1` HTTP boundary is stubbed via
  # `Req.Test` (see config/test.exs `IdeajarStub`).
  describe "location search dropdown (slice 7a iter2)" do
    defp stub_results!(view, results) do
      Req.Test.stub(IdeajarStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(results))
      end)

      allow_geocoding!(view)
    end

    defp stub_service_unavailable!(view) do
      Req.Test.stub(IdeajarStub, fn conn ->
        Plug.Conn.send_resp(conn, 502, "bad gateway")
      end)

      allow_geocoding!(view)
    end

    test "mount: assigns initial search state (results == [], state == :idle)",
         %{conn: conn} do
      view = mount_authenticated(conn)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.location_search_results == []
      assert assigns.location_search_state == :idle
    end

    test "mount: dropdown not in DOM initially (state idle)", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      html = render(view)

      refute html =~ ~s(role="listbox")
      refute html =~ "Cerco"
      refute html =~ "Nessun risultato"
    end

    # Regression pin (slice 7a iter2 follow-up): the input's `phx-change`
    # is fired by the browser inside the parent `<.form>`, so the params
    # arrive as `%{"idea" => %{"location_name" => "..."}}`, NOT the
    # synthetic `%{"name" => "..."}` shape that the unit-style
    # `render_change/3` calls use. The handler must accept BOTH shapes,
    # otherwise typing in the real browser silently no-ops.
    test "form-shape params (idea.location_name) drive the search the same way",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      stub_results!(view, [
        %{"display_name" => "Sirolo, AN", "lat" => "43.5", "lon" => "13.6"}
      ])

      render_change(view, "update_location_name", %{
        "_target" => ["idea", "location_name"],
        "idea" => %{"location_name" => "sirolo"}
      })

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_location_name == "sirolo"
      assert assigns.location_search_state == :results
      assert length(assigns.location_search_results) == 1
    end

    test "type < 3 chars: silent (state stays :idle, no dropdown rendered)",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form() |> stub_geocoding_empty!()

      html = render_change(view, "update_location_name", %{"name" => "Si"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.location_search_state == :idle
      assert assigns.location_search_results == []
      assert assigns.selected_location_name == "Si"
      refute html =~ ~s(role="listbox")
    end

    test "type >= 3 chars: triggers search, dropdown renders the results",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      stub_results!(view, [
        %{"display_name" => "Sirolo, AN", "lat" => "43.5", "lon" => "13.6"},
        %{"display_name" => "Siracusa, SR", "lat" => "37.0", "lon" => "15.3"}
      ])

      html = render_change(view, "update_location_name", %{"name" => "sir"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.location_search_state == :results
      assert length(assigns.location_search_results) == 2
      assert html =~ ~s(role="listbox")
      assert html =~ "Sirolo, AN"
      assert html =~ "Siracusa, SR"
      assert html =~ ~s(phx-click="select_location")
    end

    test "empty result set: state :empty, dropdown shows 'Nessun risultato'",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      stub_results!(view, [])

      html = render_change(view, "update_location_name", %{"name" => "xyzzy"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.location_search_state == :empty
      assert assigns.location_search_results == []
      assert html =~ "Nessun risultato"
      assert html =~ ~s(role="listbox")
    end

    test "service unavailable: state :idle, no dropdown, flash error 'Ricerca non disponibile, riprova'",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      stub_service_unavailable!(view)

      html = render_change(view, "update_location_name", %{"name" => "sirolo"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.location_search_state == :idle
      assert assigns.location_search_results == []
      refute html =~ ~s(role="listbox")
      assert html =~ "Ricerca non disponibile, riprova"
    end

    test "click result populates the 3 location assigns and closes the dropdown",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      stub_results!(view, [
        %{"display_name" => "Sirolo, AN", "lat" => "43.5", "lon" => "13.6"}
      ])

      render_change(view, "update_location_name", %{"name" => "sir"})

      html =
        render_click(view, "select_location", %{
          "name" => "Sirolo, AN",
          "lat" => "43.5",
          "lng" => "13.6"
        })

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_location_name == "Sirolo, AN"
      assert assigns.selected_lat == 43.5
      assert assigns.selected_lng == 13.6
      assert assigns.location_search_state == :idle
      assert assigns.location_search_results == []
      refute html =~ ~s(role="listbox")
      assert html =~ ~s(value="Sirolo, AN")
    end

    # C1 — typing after a successful select must clear lat/lng so the form
    # cannot be submitted as state (c) name+coords with a stale name. The
    # location name is replaced with the new query.
    test "C1: typing after a select clears lat/lng and re-runs the search",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      stub_results!(view, [
        %{"display_name" => "Sirolo, AN", "lat" => "43.5", "lon" => "13.6"}
      ])

      render_change(view, "update_location_name", %{"name" => "sir"})

      render_click(view, "select_location", %{
        "name" => "Sirolo, AN",
        "lat" => "43.5",
        "lng" => "13.6"
      })

      pre = :sys.get_state(view.pid).socket.assigns
      assert pre.selected_lat == 43.5
      assert pre.selected_lng == 13.6

      stub_results!(view, [
        %{"display_name" => "Roma, RM", "lat" => "41.9", "lon" => "12.5"}
      ])

      render_change(view, "update_location_name", %{"name" => "roma"})

      post = :sys.get_state(view.pid).socket.assigns
      assert post.selected_location_name == "roma"
      assert post.selected_lat == nil
      assert post.selected_lng == nil
      assert post.location_search_state == :results
      assert length(post.location_search_results) == 1
    end

    test "phx-click-away dismiss_location_search closes the dropdown without touching the 3 assigns",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      stub_results!(view, [
        %{"display_name" => "Sirolo, AN", "lat" => "43.5", "lon" => "13.6"}
      ])

      render_change(view, "update_location_name", %{"name" => "sir"})

      pre = :sys.get_state(view.pid).socket.assigns
      assert pre.location_search_state == :results
      assert pre.selected_location_name == "sir"

      html = render_click(view, "dismiss_location_search")

      post = :sys.get_state(view.pid).socket.assigns
      assert post.location_search_state == :idle
      assert post.location_search_results == []
      # 3 location assigns survive dismissal
      assert post.selected_location_name == "sir"
      assert post.selected_lat == nil
      assert post.selected_lng == nil
      refute html =~ ~s(role="listbox")
    end

    test "phx-click-away wired on the search input wrapper",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      html = render(view)

      assert html =~ ~s(phx-click-away="dismiss_location_search")
    end

    test "submit without selecting from the dropdown (state b): name persists, lat/lng nil",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      stub_results!(view, [])

      render_change(view, "update_location_name", %{"name" => "Casa di nonna"})

      html = submit(view, %{title: "Picnic"})
      assert html =~ "Idea aggiunta"

      assigns = :sys.get_state(view.pid).socket.assigns
      assert length(assigns.ideas) == 1
      idea = hd(assigns.ideas)
      assert idea.location_name == "Casa di nonna"
      assert idea.lat == nil
      assert idea.lng == nil
    end

    test "submit after selecting from the dropdown (state c): all 3 fields persist",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      stub_results!(view, [
        %{"display_name" => "Sirolo, AN", "lat" => "43.5", "lon" => "13.6"}
      ])

      render_change(view, "update_location_name", %{"name" => "sir"})

      render_click(view, "select_location", %{
        "name" => "Sirolo, AN",
        "lat" => "43.5",
        "lng" => "13.6"
      })

      submit(view, %{title: "Gita"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert length(assigns.ideas) == 1
      idea = hd(assigns.ideas)
      assert idea.location_name == "Sirolo, AN"
      assert idea.lat == 43.5
      assert idea.lng == 13.6
    end

    # Hostile select_location payloads: missing keys, non-binary lat/lng,
    # non-numeric strings, out-of-range floats. Handler must no-op so the
    # 3 location assigns and search state stay unchanged and the LV
    # process stays alive.
    for {label, payload} <- [
          {"non-numeric lat", %{"name" => "X", "lat" => "abc", "lng" => "13.6"}},
          {"non-numeric lng", %{"name" => "X", "lat" => "43.5", "lng" => "xyz"}},
          {"out-of-range lat (>90)", %{"name" => "X", "lat" => "120.0", "lng" => "13.6"}},
          {"out-of-range lat (<-90)", %{"name" => "X", "lat" => "-91.0", "lng" => "13.6"}},
          {"out-of-range lng (>180)", %{"name" => "X", "lat" => "43.5", "lng" => "200.0"}},
          {"out-of-range lng (<-180)", %{"name" => "X", "lat" => "43.5", "lng" => "-181.0"}},
          {"missing name", %{"lat" => "43.5", "lng" => "13.6"}},
          {"missing lat", %{"name" => "X", "lng" => "13.6"}},
          {"missing lng", %{"name" => "X", "lat" => "43.5"}},
          {"non-binary name", %{"name" => 42, "lat" => "43.5", "lng" => "13.6"}}
        ] do
      test "select_location with hostile #{label} payload is a no-op",
           %{conn: conn} do
        view = mount_authenticated(conn) |> open_form()

        render_hook(view, "select_location", unquote(Macro.escape(payload)))

        assigns = :sys.get_state(view.pid).socket.assigns
        assert assigns.selected_location_name == nil
        assert assigns.selected_lat == nil
        assert assigns.selected_lng == nil
        assert Process.alive?(view.pid)
      end
    end

    test "remove_location resets the search results + state too",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      stub_results!(view, [
        %{"display_name" => "Sirolo, AN", "lat" => "43.5", "lon" => "13.6"}
      ])

      render_change(view, "update_location_name", %{"name" => "sir"})

      pre = :sys.get_state(view.pid).socket.assigns
      assert pre.location_search_state == :results
      assert length(pre.location_search_results) == 1

      render_click(view, "remove_location")

      post = :sys.get_state(view.pid).socket.assigns
      assert post.selected_location_name == nil
      assert post.selected_lat == nil
      assert post.selected_lng == nil
      assert post.location_search_state == :idle
      assert post.location_search_results == []
    end

    test "DOM source order regression: Categorie → Durata → Budget → Posizione → Salva",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      html = render(view)

      categorie_idx = :binary.match(html, "Categorie") |> elem(0)
      durata_idx = :binary.match(html, ">Durata<") |> elem(0)
      budget_idx = :binary.match(html, ">Budget<") |> elem(0)
      posizione_idx = :binary.match(html, ">Posizione<") |> elem(0)
      salva_idx = :binary.match(html, ">\n        Salva\n      <") |> elem(0)

      assert categorie_idx < durata_idx
      assert durata_idx < budget_idx
      assert budget_idx < posizione_idx
      assert posizione_idx < salva_idx
    end

    test "no Leaflet/dialog DOM survives the rework",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      html = render(view)

      refute html =~ "location-map-dialog"
      refute html =~ "form-map-picker"
      refute html =~ "LeafletMap"
      refute html =~ "Apri mappa"
    end
  end

  # Slice 7a step 8 — pure regression pin block. After the iter2 rework
  # the form, the `select_location` handler (replacing `set_location`),
  # the extended `update_location_name` handler (search + C1 clear), the
  # `dismiss_location_search` handler, the `remove_location` handler,
  # the `maybe_inject_*` save-time injectors, the cross-field
  # `validate_location_consistency/1` validator, and the idea card
  # location badge are all in place. This describe pins the invariants
  # that emerge from their composition.
  #
  # Spec mapping: F5, F15, F17, S2, CC11.
  describe "form/badge integration + edit-text-after-pin invariants (slice 7a step 8)" do
    # F16 state (b) — name without coords renders the badge with just
    # the name. Pure regression pin against the slice 7a step 5 contract.
    test "card badge state (b): persisted idea with location_name only renders '📍 <name>'",
         %{conn: conn} do
      mare = CategoriesFixtures.category_by_name!("mare")

      assert {:ok, _idea} =
               Ideajar.Ideas.create_idea(%{
                 title: "Picnic",
                 category_ids: [mare.id],
                 location_name: "Casa di nonna"
               })

      {:ok, _view, html} =
        live_isolated(conn, Index, session: @authenticated_session)

      [_full, inner] =
        Regex.run(
          ~r{<span[^>]*data-testid="idea-location-badge"[^>]*>(.*?)</span>}s,
          html
        )

      assert String.trim(inner) == "📍 Casa di nonna"
    end

    # F16 state (c) — name + coords renders the badge with just the name.
    # Coords are NOT exposed in the badge (slice 7b will use them for the
    # distance filter, not for badge text).
    test "card badge state (c): persisted idea with name + coords renders only '📍 <name>' (no coords)",
         %{conn: conn} do
      mare = CategoriesFixtures.category_by_name!("mare")

      assert {:ok, _idea} =
               Ideajar.Ideas.create_idea(%{
                 title: "Sirolo",
                 category_ids: [mare.id],
                 location_name: "Sirolo, AN",
                 lat: 43.5,
                 lng: 13.6
               })

      {:ok, _view, html} =
        live_isolated(conn, Index, session: @authenticated_session)

      [_full, inner] =
        Regex.run(
          ~r{<span[^>]*data-testid="idea-location-badge"[^>]*>(.*?)</span>}s,
          html
        )

      assert String.trim(inner) == "📍 Sirolo, AN"
      refute inner =~ "43.5"
      refute inner =~ "13.6"
    end

    # S2 — XSS regression on the badge. A persisted location_name carrying
    # a `<script>` payload must surface escaped through HEEx auto-escape.
    # Duplicates the step 5 S2 pin in the integration block so a future
    # refactor that strips this regression from step 5 still trips here.
    test "S2: persisted idea with hostile location_name <script> renders escaped on the card badge",
         %{conn: conn} do
      mare = CategoriesFixtures.category_by_name!("mare")

      assert {:ok, _idea} =
               Ideajar.Ideas.create_idea(%{
                 title: "Hostile",
                 category_ids: [mare.id],
                 location_name: "<script>alert(1)</script>"
               })

      {:ok, _view, html} =
        live_isolated(conn, Index, session: @authenticated_session)

      [_full, inner] =
        Regex.run(
          ~r{<span[^>]*data-testid="idea-location-badge"[^>]*>(.*?)</span>}s,
          html
        )

      assert inner =~ "&lt;script&gt;"
      assert inner =~ "&lt;/script&gt;"
      refute inner =~ "<script>"
      refute inner =~ "</script>"
    end

    # F17 / CC11 — On a vanilla save success (no location involved) the
    # 3 location assigns are still nil afterwards. Parallel to the
    # explicit reset-on-save-success pins for duration (slice 5) and
    # budget (slice 6). The integration here is "save success path
    # touches reset_location/1".
    test "F17: save success resets the 3 location assigns to nil",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      submit(view, %{title: "Cinema stasera"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.form_visible? == false
      assert assigns.selected_location_name == nil
      assert assigns.selected_lat == nil
      assert assigns.selected_lng == nil
    end
  end

  # ── Slice 7a Step 9: Hostile inputs uniform list + cross-field
  # validation regression pin. Step 4 already covers `update_location_name`
  # hostile inputs (5 cases); the iter2 dropdown describe covers
  # `select_location` hostile inputs (out-of-range + non-numeric +
  # missing-key + non-binary, replacing the old `set_location` matrix);
  # step 3 covers cross-field validation at the changeset level. This
  # describe block adds:
  #   * cross-field validation pinned at the submit/LV level (state D
  #     combinations all surface "Posizione incompleta" on `:location_name`);
  #   * `remove_location` idempotency (multiple consecutive invocations
  #     leave state nil + no crash).
  describe "hostile inputs and cross-field validation regression (slice 7a step 9)" do
    # Cross-field validation regression — all 4 state-D combinations
    # surface the canonical "Posizione incompleta" error on
    # `:location_name`. Submit-level pins parallel to step 3's
    # changeset-level pins.

    test "submit with lat without lng surfaces 'Posizione incompleta' on :location_name",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      # Coords without complete pair: simulate by placing values directly
      # into the LV assigns via render_hook (same pattern step 7 uses).
      :sys.replace_state(view.pid, fn state ->
        socket = state.socket
        new_assigns = Map.merge(socket.assigns, %{selected_lat: 43.5})
        %{state | socket: %{socket | assigns: new_assigns}}
      end)

      submit(view, %{title: "Picnic"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.ideas == []

      assert {"Posizione incompleta", _opts} =
               Keyword.get(assigns.form.source.errors, :location_name)
    end

    test "submit with lng without lat surfaces 'Posizione incompleta'",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      :sys.replace_state(view.pid, fn state ->
        socket = state.socket
        new_assigns = Map.merge(socket.assigns, %{selected_lng: 13.6})
        %{state | socket: %{socket | assigns: new_assigns}}
      end)

      submit(view, %{title: "Picnic"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.ideas == []

      assert {"Posizione incompleta", _opts} =
               Keyword.get(assigns.form.source.errors, :location_name)
    end

    test "submit with coords without location_name surfaces 'Posizione incompleta'",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      :sys.replace_state(view.pid, fn state ->
        socket = state.socket
        new_assigns = Map.merge(socket.assigns, %{selected_lat: 43.5, selected_lng: 13.6})
        %{state | socket: %{socket | assigns: new_assigns}}
      end)

      submit(view, %{title: "Picnic"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.ideas == []

      assert {"Posizione incompleta", _opts} =
               Keyword.get(assigns.form.source.errors, :location_name)
    end

    test "submit with empty-string name (post-trim) + coords is rejected",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      # Post-trim "" → nil → state D. Step 8 already pins the in-band
      # update_location_name path; this is the regression pin via direct
      # assigns mutation.
      :sys.replace_state(view.pid, fn state ->
        socket = state.socket

        new_assigns =
          Map.merge(socket.assigns, %{
            selected_location_name: "",
            selected_lat: 43.5,
            selected_lng: 13.6
          })

        %{state | socket: %{socket | assigns: new_assigns}}
      end)

      submit(view, %{title: "Picnic"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.ideas == []

      assert {"Posizione incompleta", _opts} =
               Keyword.get(assigns.form.source.errors, :location_name)
    end

    # remove_location idempotency: calling twice with no location set
    # yields no error and the assigns remain nil.

    test "remove_location is idempotent on already-empty location state",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      # Initial state: all 3 nil.
      assigns_before = :sys.get_state(view.pid).socket.assigns
      assert assigns_before.selected_location_name == nil
      assert assigns_before.selected_lat == nil
      assert assigns_before.selected_lng == nil

      render_click(view, "remove_location")
      render_click(view, "remove_location")
      render_click(view, "remove_location")

      assigns_after = :sys.get_state(view.pid).socket.assigns
      assert assigns_after.selected_location_name == nil
      assert assigns_after.selected_lat == nil
      assert assigns_after.selected_lng == nil
      assert Process.alive?(view.pid)
    end
  end

  describe "Geolocation JS hook (slice 7b step 5)" do
    # Static-source pins for the JS hook. Slice 7b step 6 and step 8
    # exercise the server side of the geolocation flow (handlers
    # `set_user_location`/`user_location_denied`); these tests pin only
    # the JS half — that the hook file exists with the expected click
    # handler shape and that app.js registers it on the LiveSocket so
    # the LiveView's `phx-hook="Geolocation"` button actually wires up
    # at boot time.

    test "hook source defines mounted() and a click handler invoking navigator.geolocation" do
      hook_js = File.read!(Path.join(File.cwd!(), "assets/js/hooks/geolocation.js"))

      assert hook_js =~ "export const Geolocation"
      assert hook_js =~ "mounted()"
      assert hook_js =~ "addEventListener"
      assert hook_js =~ "navigator.geolocation"
      assert hook_js =~ "getCurrentPosition"
      assert hook_js =~ "set_user_location"
      assert hook_js =~ "user_location_denied"
    end

    test "hook does NOT register click in updated() (no double-bind on LV patch)" do
      # Phoenix LV calls the update callback on every diff; if
      # `addEventListener` were registered there, every render would
      # stack another listener producing N pushEvents per click. The
      # hook must rely on the one-time `mounted()` bind only.
      #
      # The regex anchors on a line-start method definition (`^\s*updated\s*\(`)
      # so the design-notes comment that explains the rationale below
      # does NOT trip the assertion.
      hook_js = File.read!(Path.join(File.cwd!(), "assets/js/hooks/geolocation.js"))

      refute hook_js =~ ~r/^\s*updated\s*\(/m
    end

    test "hook maps W3C PositionError codes to the four documented reason strings" do
      # W3C: 1=PERMISSION_DENIED, 2=POSITION_UNAVAILABLE, 3=TIMEOUT.
      # Hook fallback for missing API → "unsupported".
      hook_js = File.read!(Path.join(File.cwd!(), "assets/js/hooks/geolocation.js"))

      assert hook_js =~ "permission_denied"
      assert hook_js =~ "unavailable"
      assert hook_js =~ "timeout"
      assert hook_js =~ "unsupported"
    end

    test "app.js registers the Geolocation hook on the LiveSocket" do
      app_js = File.read!(Path.join(File.cwd!(), "assets/js/app.js"))
      assert app_js =~ "Geolocation"
    end
  end

  describe "user location handlers (slice 7b step 6)" do
    test "mount initialises user_lat / user_lng / user_location_name to nil",
         %{conn: conn} do
      view = mount_authenticated(conn)
      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.user_lat == nil
      assert assigns.user_lng == nil
      assert assigns.user_location_name == nil
    end

    test "set_user_location with valid coords sets lat/lng + falls back to 'La mia posizione' when reverse-geocode is unavailable",
         %{conn: conn} do
      view = mount_authenticated(conn)

      # No Req.Test stub installed → Geocoding.reverse/2 returns
      # {:error, :service_unavailable} (defensive rescue path), the
      # handler falls back silently to the generic IT label.
      render_hook(view, "set_user_location", %{"lat" => 43.6, "lng" => 13.5})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_lat == 43.6
      assert assigns.user_lng == 13.5
      assert assigns.user_location_name == "La mia posizione"
    end

    test "set_user_location uses Nominatim reverse-geocode display_name when available",
         %{conn: conn} do
      view = mount_authenticated(conn)

      Req.Test.stub(IdeajarStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "display_name" => "Sirolo, Provincia di Ancona, Marche, Italia",
            "lat" => "43.6",
            "lon" => "13.5"
          })
        )
      end)

      Req.Test.allow(IdeajarStub, self(), view.pid)
      render_hook(view, "set_user_location", %{"lat" => 43.6, "lng" => 13.5})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_lat == 43.6
      assert assigns.user_lng == 13.5
      assert assigns.user_location_name == "Sirolo, Provincia di Ancona, Marche, Italia"
    end

    test "user_location_denied with reason permission_denied flashes the canonical IT message",
         %{conn: conn} do
      view = mount_authenticated(conn)

      render_hook(view, "user_location_denied", %{"reason" => "permission_denied"})

      assert render(view) =~ "Permesso di geolocalizzazione negato"
    end

    test "user_location_denied with reason timeout flashes the generic IT message",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "user_location_denied", %{"reason" => "timeout"})

      assert render(view) =~ "Posizione non disponibile, riprova"
    end

    test "user_location_denied with reason unavailable flashes the generic IT message",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "user_location_denied", %{"reason" => "unavailable"})

      assert render(view) =~ "Posizione non disponibile, riprova"
    end

    test "user_location_denied with reason unsupported flashes the generic IT message",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "user_location_denied", %{"reason" => "unsupported"})

      assert render(view) =~ "Posizione non disponibile, riprova"
    end

    # Hostile uniform list S1 — eight malformed payloads. Each must
    # leave the LV process alive AND the three user_* assigns at nil.
    test "set_user_location is a no-op for non-numeric, out-of-range, missing, and non-binary payloads",
         %{conn: conn} do
      view = mount_authenticated(conn)

      hostile = [
        %{"lat" => "abc", "lng" => 13.6},
        %{"lat" => 91.0, "lng" => 13.6},
        %{"lat" => -91.0, "lng" => 13.6},
        %{"lat" => 43.5, "lng" => 181.0},
        %{"lat" => 43.5, "lng" => -181.0},
        %{},
        %{"lat" => [], "lng" => 13.6},
        %{"lat" => 43.5}
      ]

      Enum.each(hostile, fn params ->
        render_hook(view, "set_user_location", params)
      end)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_lat == nil
      assert assigns.user_lng == nil
      assert assigns.user_location_name == nil
      assert Process.alive?(view.pid)
    end
  end

  describe "user location filter search (slice 7b step 7)" do
    defp user_search_stub_results!(view, results) do
      Req.Test.stub(IdeajarStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(results))
      end)

      Req.Test.allow(IdeajarStub, self(), view.pid)
      view
    end

    defp user_search_stub_unavailable!(view) do
      Req.Test.stub(IdeajarStub, fn conn ->
        Plug.Conn.send_resp(conn, 502, "bad gateway")
      end)

      Req.Test.allow(IdeajarStub, self(), view.pid)
      view
    end

    test "mount: user_location_search_results == [] and state == :idle",
         %{conn: conn} do
      view = mount_authenticated(conn)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_location_search_results == []
      assert assigns.user_location_search_state == :idle
    end

    test "update_user_location_name with < 3 chars stays idle, no dropdown",
         %{conn: conn} do
      view = mount_authenticated(conn)

      render_hook(view, "update_user_location_name", %{"name" => "ro"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_location_search_state == :idle
    end

    test "update_user_location_name ≥ 3 chars + 2 results → state :results, dropdown rendered",
         %{conn: conn} do
      view = mount_authenticated(conn)

      user_search_stub_results!(view, [
        %{"display_name" => "Roma, RM", "lat" => "41.9", "lon" => "12.5"},
        %{"display_name" => "Roma Termini", "lat" => "41.901", "lon" => "12.501"}
      ])

      render_hook(view, "update_user_location_name", %{"name" => "roma"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_location_search_state == :results
      assert length(assigns.user_location_search_results) == 2
    end

    test "update_user_location_name with empty results → state :empty",
         %{conn: conn} do
      view = mount_authenticated(conn)
      user_search_stub_results!(view, [])

      render_hook(view, "update_user_location_name", %{"name" => "qqxz"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_location_search_state == :empty
    end

    test "update_user_location_name with service unavailable → flash + state :idle",
         %{conn: conn} do
      view = mount_authenticated(conn)
      user_search_stub_unavailable!(view)

      render_hook(view, "update_user_location_name", %{"name" => "roma"})

      assert render(view) =~ "Ricerca non disponibile, riprova"
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_location_search_state == :idle
    end

    test "select_user_location with valid result sets 3 user_* assigns + state :idle",
         %{conn: conn} do
      view = mount_authenticated(conn)

      render_hook(view, "select_user_location", %{
        "name" => "Roma, RM",
        "lat" => "41.9",
        "lng" => "12.5"
      })

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_lat == 41.9
      assert assigns.user_lng == 12.5
      assert assigns.user_location_name == "Roma, RM"
      assert assigns.user_location_search_state == :idle
    end

    test "select_user_location swap preserves @max_distance_index (DD19 swap clause)",
         %{conn: conn} do
      view = mount_authenticated(conn)

      # Pre-state: user has set a reference + slider at index 3.
      render_hook(view, "set_user_location", %{"lat" => 43.5, "lng" => 13.6})

      :sys.replace_state(view.pid, fn state ->
        new_assigns = Map.put(state.socket.assigns, :max_distance_index, 3)
        %{state | socket: %{state.socket | assigns: new_assigns}}
      end)

      # Swap to a new search result.
      render_hook(view, "select_user_location", %{
        "name" => "Roma, RM",
        "lat" => "41.9",
        "lng" => "12.5"
      })

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_location_name == "Roma, RM"
      assert assigns.max_distance_index == 3
    end

    test "dismiss_user_location_search resets search state but leaves user_* assigns",
         %{conn: conn} do
      view = mount_authenticated(conn)

      user_search_stub_results!(view, [
        %{"display_name" => "Roma", "lat" => "41.9", "lon" => "12.5"}
      ])

      render_hook(view, "update_user_location_name", %{"name" => "roma"})

      render_hook(view, "dismiss_user_location_search", %{})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_location_search_state == :idle
      # User had not selected a result; user_* still nil.
      assert assigns.user_lat == nil
      assert assigns.user_lng == nil
      assert assigns.user_location_name == nil
    end

    test "select_user_location with hostile payloads is a no-op (S3 uniform list)",
         %{conn: conn} do
      view = mount_authenticated(conn)

      hostile = [
        %{},
        %{"name" => "X"},
        %{"name" => "X", "lat" => "abc", "lng" => "13.6"},
        %{"name" => "X", "lat" => "91", "lng" => "13.6"},
        %{"name" => "X", "lat" => "43.5", "lng" => "181"},
        %{"name" => :atom, "lat" => "43.5", "lng" => "13.6"}
      ]

      Enum.each(hostile, fn params ->
        render_hook(view, "select_user_location", params)
      end)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_lat == nil
      assert assigns.user_lng == nil
      assert assigns.user_location_name == nil
      assert Process.alive?(view.pid)
    end

    test "update_user_location_name with non-binary payload is a no-op (S4)",
         %{conn: conn} do
      view = mount_authenticated(conn)

      render_hook(view, "update_user_location_name", %{"name" => 123})
      render_hook(view, "update_user_location_name", %{"name" => :atom})
      render_hook(view, "update_user_location_name", %{})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_location_search_state == :idle
      assert Process.alive?(view.pid)
    end

    # Real-browser regression pin (parallel slice 7a iter2 commit 868f3fc):
    # `phx-change` on the filter input fires with the form-bracketed
    # name attribute as the params shape, NOT the synthetic `%{"name" => …}`
    # shape that `render_hook/3` uses. The handler must accept both, or
    # typing in the actual browser silently no-ops while the unit tests
    # stay green.
    test "form-shape params (filter.user_location_name) drive the search the same way",
         %{conn: conn} do
      view = mount_authenticated(conn)

      user_search_stub_results!(view, [
        %{"display_name" => "Roma, RM", "lat" => "41.9", "lon" => "12.5"}
      ])

      render_hook(view, "update_user_location_name", %{
        "filter" => %{"user_location_name" => "roma"}
      })

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_location_search_state == :results
      assert length(assigns.user_location_search_results) == 1
    end

    # Browser-context regression pin: `view |> form(selector, ...)` only
    # resolves when the input is inside a `<form>` element with that id.
    # `render_hook/3` bypasses the browser's form-context requirement,
    # so the unit tests above stayed green even when the filter inputs
    # were bare (and `phx-change` therefore never fired in real browsers).
    # This pin guards both the form wrapper AND the form-shape param flow.
    test "filter search form wraps the input so phx-change fires in real browsers",
         %{conn: conn} do
      view = mount_authenticated(conn)

      user_search_stub_results!(view, [
        %{"display_name" => "Roma, RM", "lat" => "41.9", "lon" => "12.5"}
      ])

      view
      |> form("#filter-distance-search-form", filter: %{user_location_name: "roma"})
      |> render_change()

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_location_search_state == :results
    end

    test "@user_location_search_query tracks the typed text so re-renders don't reset the input",
         %{conn: conn} do
      view = mount_authenticated(conn)

      user_search_stub_results!(view, [
        %{"display_name" => "Roma, RM", "lat" => "41.9", "lon" => "12.5"}
      ])

      render_hook(view, "update_user_location_name", %{"name" => "roma"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_location_search_query == "roma"

      html = render(view)
      assert html =~ ~s(value="roma")
    end

    test "select_user_location clears @user_location_search_query so the input empties",
         %{conn: conn} do
      view = mount_authenticated(conn)

      user_search_stub_results!(view, [
        %{"display_name" => "Roma, RM", "lat" => "41.9", "lon" => "12.5"}
      ])

      render_hook(view, "update_user_location_name", %{"name" => "roma"})

      render_hook(view, "select_user_location", %{
        "name" => "Roma, RM",
        "lat" => "41.9",
        "lng" => "12.5"
      })

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_location_search_query == ""
    end
  end

  describe "distance filter sub-block (slice 7b step 8)" do
    test "renders the role=group sub-block with aria-label after Budget",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

      assert html =~ ~s(role="group" aria-label="Filtra per distanza")

      [_, after_budget] = String.split(html, ~s(aria-label="Filtra per budget"), parts: 2)
      assert after_budget =~ ~s(aria-label="Filtra per distanza")
    end

    test "mount: @max_distance_index defaults to 0", %{conn: conn} do
      view = mount_authenticated(conn)
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.max_distance_index == 0
    end

    test "renders the slider with the full ARIA contract on mount (A1)",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

      assert html =~ ~s(type="range")
      assert html =~ ~s(min="0")
      assert html =~ ~s(max="6")
      assert html =~ ~s(aria-valuemin="0")
      assert html =~ ~s(aria-valuemax="6")
      assert html =~ ~s(aria-valuenow="0")
      assert html =~ ~s(aria-valuetext="Disattivo")
    end

    test "slider is disabled and aria-disabled when no reference point is set",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

      [slider_html] = Regex.run(~r/<input[^>]*id="filter-distance-slider"[^>]*>/, html)

      assert slider_html =~ "disabled"
      assert slider_html =~ ~s(aria-disabled="true")
    end

    test "renders the helper text instructing to set a reference point when @user_lat is nil",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

      assert html =~ "Imposta un punto di riferimento per usare il filtro distanza"
    end

    # DD13 combined-state pin — the disabled slider AND the helper text
    # must coexist in the same render call. Two separate tests assert
    # them individually, but the contract is "both together when no
    # reference point is set".
    test "DD13 combined-state: when @user_lat is nil, slider has disabled AND helper text is rendered",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

      [slider_html] = Regex.run(~r/<input[^>]*id="filter-distance-slider"[^>]*>/, html)
      assert slider_html =~ "disabled"
      assert slider_html =~ ~s(aria-disabled="true")
      assert html =~ "Imposta un punto di riferimento per usare il filtro distanza"
    end

    test "always renders the NULL-exclude helper text in the sub-block (DD14)",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

      assert html =~ "Le idee senza posizione sono nascoste quando un filtro è attivo."
    end

    test "renders the geolocation button with phx-hook=Geolocation",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

      assert html =~ ~s(phx-hook="Geolocation")
      assert html =~ "Usa la mia posizione"
    end

    test "renders the LocationSearchInput with the filter event names + IT placeholder",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

      assert html =~ ~s(phx-change="update_user_location_name")
      assert html =~ ~s(phx-click-away="dismiss_user_location_search")
      assert html =~ ~s(placeholder="Cerca punto di partenza")
    end

    test "after set_user_location, slider becomes enabled and aria-disabled=false",
         %{conn: conn} do
      view = mount_authenticated(conn)

      render_hook(view, "set_user_location", %{"lat" => 43.5, "lng" => 13.6})

      html = render(view)
      [slider_html] = Regex.run(~r/<input[^>]*id="filter-distance-slider"[^>]*>/, html)

      refute slider_html =~ ~r/\sdisabled[\s>]/
      assert slider_html =~ ~s(aria-disabled="false")
    end

    test "after set_user_location, the 'Punto di riferimento: La mia posizione' label appears",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "set_user_location", %{"lat" => 43.5, "lng" => 13.6})

      html = render(view)
      assert html =~ "Punto di riferimento: La mia posizione"
    end

    test "update_max_distance with value '3' assigns @max_distance_index 3 + aria-valuetext = 'fino a 50 km'",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "set_user_location", %{"lat" => 43.5, "lng" => 13.6})

      render_hook(view, "update_max_distance", %{"value" => "3"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.max_distance_index == 3

      html = render(view)
      assert html =~ ~s(aria-valuenow="3")
      assert html =~ ~s(aria-valuetext="fino a 50 km")
    end

    test "update_max_distance index 6 → aria-valuetext = 'oltre 1000 km'",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "set_user_location", %{"lat" => 43.5, "lng" => 13.6})
      render_hook(view, "update_max_distance", %{"value" => "6"})

      html = render(view)
      assert html =~ ~s(aria-valuetext="oltre 1000 km")
    end

    test "slider form wraps the range input so phx-change fires in real browsers",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "set_user_location", %{"lat" => 43.5, "lng" => 13.6})

      view
      |> form("#filter-distance-slider-form", value: "3")
      |> render_change()

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.max_distance_index == 3
    end

    test "update_max_distance hostile uniform list → no-op (DD9)",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "set_user_location", %{"lat" => 43.5, "lng" => 13.6})

      hostile = [
        %{"value" => "abc"},
        %{"value" => "-1"},
        %{"value" => "7"},
        %{"value" => "3.5"},
        %{}
      ]

      Enum.each(hostile, fn p ->
        render_hook(view, "update_max_distance", p)
      end)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.max_distance_index == 0
      assert Process.alive?(view.pid)
    end

    test "renders the touch-target CSS rule for the slider thumb (A8)" do
      app_css = File.read!(Path.join(File.cwd!(), "assets/css/app.css"))

      assert app_css =~ "::-webkit-slider-thumb"
      assert app_css =~ "::-moz-range-thumb"
    end

    test "filter row sub-block source order: Categorie → Durata → Budget → Distanza (F19)",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

      cat_pos = :binary.match(html, "Filtra per categoria") |> elem(0)
      dur_pos = :binary.match(html, "Filtra per durata") |> elem(0)
      bud_pos = :binary.match(html, "Filtra per budget") |> elem(0)
      dist_pos = :binary.match(html, "Filtra per distanza") |> elem(0)

      assert cat_pos < dur_pos
      assert dur_pos < bud_pos
      assert bud_pos < dist_pos
    end
  end

  describe "distance filter integration with list_ideas (slice 7b step 8 GREEN)" do
    defp seed_idea_with_coords!(title, lat, lng) do
      mare = Ideajar.Repo.get_by!(Ideajar.Categories.Category, name: "mare")

      %Ideajar.Ideas.Idea{
        title: title,
        lat: lat,
        lng: lng,
        location_name: title,
        duration: :weekend,
        estimated_cost: 100
      }
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:categories, [mare])
      |> Ideajar.Repo.insert!()
    end

    test "F11: slider index 0 + ref point + mix coords/NULL ideas → render shows all (NULL passes)",
         %{conn: conn} do
      seed_idea_with_coords!("Sirolo", 43.5, 13.6)
      seed_idea_with_coords!("Senza coords", nil, nil)

      view = mount_authenticated(conn)
      render_hook(view, "set_user_location", %{"lat" => 43.5, "lng" => 13.6})

      html = render(view)
      assert html =~ "Sirolo"
      assert html =~ "Senza coords"
    end

    test "F12: slider index 1 (5km) + ref Sirolo → only ideas within 5 km, NULL excluded",
         %{conn: conn} do
      seed_idea_with_coords!("Sirolo", 43.5, 13.6)
      seed_idea_with_coords!("Roma", 41.9, 12.5)
      seed_idea_with_coords!("Senza coords", nil, nil)

      view = mount_authenticated(conn)
      render_hook(view, "set_user_location", %{"lat" => 43.5, "lng" => 13.6})
      render_hook(view, "update_max_distance", %{"value" => "1"})

      html = render(view)
      assert html =~ "Sirolo"
      refute html =~ "Roma"
      refute html =~ "Senza coords"
    end

    test "F13: slider index 6 + ref Sirolo → all ideas with coords, NULL excluded",
         %{conn: conn} do
      seed_idea_with_coords!("Sirolo", 43.5, 13.6)
      seed_idea_with_coords!("Roma", 41.9, 12.5)
      seed_idea_with_coords!("Senza coords", nil, nil)

      view = mount_authenticated(conn)
      render_hook(view, "set_user_location", %{"lat" => 43.5, "lng" => 13.6})
      render_hook(view, "update_max_distance", %{"value" => "6"})

      html = render(view)
      assert html =~ "Sirolo"
      assert html =~ "Roma"
      refute html =~ "Senza coords"
    end
  end

  describe "distance filter reset handlers (slice 7b step 9)" do
    test "F14 remove_user_location: resets 3 user_* + slider 0 + slider disabled",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "set_user_location", %{"lat" => 43.5, "lng" => 13.6})
      render_hook(view, "update_max_distance", %{"value" => "3"})

      render_click(view, "remove_user_location")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_lat == nil
      assert assigns.user_lng == nil
      assert assigns.user_location_name == nil
      assert assigns.max_distance_index == 0

      html = render(view)
      [slider_html] = Regex.run(~r/<input[^>]*id="filter-distance-slider"[^>]*>/, html)
      assert slider_html =~ "disabled"
    end

    test "F15 remove_distance_filter: resets only slider, leaves user_* intact",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "set_user_location", %{"lat" => 43.5, "lng" => 13.6})
      render_hook(view, "update_max_distance", %{"value" => "3"})

      render_click(view, "remove_distance_filter")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.max_distance_index == 0
      assert assigns.user_lat == 43.5
      assert assigns.user_lng == 13.6
      assert assigns.user_location_name == "La mia posizione"
    end

    test "F17 refresh resets @user_* + slider (LV remount)", %{conn: conn} do
      # First mount: set state, then re-mount (simulating refresh) and
      # confirm everything is back to defaults.
      view1 = mount_authenticated(conn)
      render_hook(view1, "set_user_location", %{"lat" => 43.5, "lng" => 13.6})
      render_hook(view1, "update_max_distance", %{"value" => "3"})

      view2 = mount_authenticated(conn)
      assigns = :sys.get_state(view2.pid).socket.assigns
      assert assigns.user_lat == nil
      assert assigns.user_lng == nil
      assert assigns.user_location_name == nil
      assert assigns.max_distance_index == 0
    end

    test "F18 save success does NOT reset @user_* nor slider (filter survives submit)",
         %{conn: conn} do
      mare = Ideajar.Repo.get_by!(Ideajar.Categories.Category, name: "mare")

      view = mount_authenticated(conn)
      render_hook(view, "set_user_location", %{"lat" => 43.5, "lng" => 13.6})
      render_hook(view, "update_max_distance", %{"value" => "3"})

      open_form(view)
      render_click(view, "toggle_category", %{"id" => Integer.to_string(mare.id)})

      render_change(view, "save", %{
        "idea" => %{
          "title" => "Picnic improvviso",
          "duration" => "weekend"
        }
      })

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_lat == 43.5
      assert assigns.user_lng == 13.6
      assert assigns.user_location_name == "La mia posizione"
      assert assigns.max_distance_index == 3
    end

    test "Rimuovi punto di riferimento button is rendered when reference is set",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "set_user_location", %{"lat" => 43.5, "lng" => 13.6})

      html = render(view)
      assert html =~ "Rimuovi punto di riferimento"
      assert html =~ ~s(phx-click="remove_user_location")
    end

    test "Rimuovi punto di riferimento button NOT rendered when nil reference",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)
      refute html =~ "Rimuovi punto di riferimento"
    end

    test "Rimuovi filtro distanza button is rendered when slider > 0",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "set_user_location", %{"lat" => 43.5, "lng" => 13.6})
      render_hook(view, "update_max_distance", %{"value" => "3"})

      html = render(view)
      assert html =~ "Rimuovi filtro distanza"
      assert html =~ ~s(phx-click="remove_distance_filter")
    end

    test "Rimuovi filtro distanza button NOT rendered when slider at 0",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "set_user_location", %{"lat" => 43.5, "lng" => 13.6})

      html = render(view)
      refute html =~ "Rimuovi filtro distanza"
    end

    test "remove_user_location is idempotent on already-empty state",
         %{conn: conn} do
      view = mount_authenticated(conn)

      render_click(view, "remove_user_location")
      render_click(view, "remove_user_location")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.user_lat == nil
      assert assigns.max_distance_index == 0
      assert Process.alive?(view.pid)
    end
  end

  describe "text search filter handlers (slice 8 step 3)" do
    test "mount: @text_search_query defaults to empty string", %{conn: conn} do
      view = mount_authenticated(conn)
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.text_search_query == ""
    end

    test "update_text_search with bare {q: 'mar'} assigns the typed text + reloads",
         %{conn: conn} do
      view = mount_authenticated(conn)

      render_hook(view, "update_text_search", %{"q" => "mar"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.text_search_query == "mar"
    end

    test "update_text_search with form-shape {filter: {text_search: 'mar'}} same behavior (DD-S8-6)",
         %{conn: conn} do
      view = mount_authenticated(conn)

      render_hook(view, "update_text_search", %{"filter" => %{"text_search" => "mar"}})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.text_search_query == "mar"
    end

    test "update_text_search with empty string clears the assign", %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "update_text_search", %{"q" => "mar"})

      render_hook(view, "update_text_search", %{"q" => ""})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.text_search_query == ""
    end

    test "update_text_search with < 3 chars still assigns the typed text (server filter inactive)",
         %{conn: conn} do
      view = mount_authenticated(conn)

      render_hook(view, "update_text_search", %{"q" => "ma"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.text_search_query == "ma"
    end

    test "remove_text_search resets @text_search_query", %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "update_text_search", %{"q" => "mar"})

      render_click(view, "remove_text_search")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.text_search_query == ""
    end

    test "S1/S2/S3 hostile uniform list → no-op for update_text_search",
         %{conn: conn} do
      view = mount_authenticated(conn)

      hostile = [
        %{"q" => 123},
        %{"q" => :atom},
        %{"q" => String.duplicate("a", 201)},
        %{},
        %{"filter" => %{}}
      ]

      Enum.each(hostile, fn p ->
        render_hook(view, "update_text_search", p)
      end)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.text_search_query == ""
      assert Process.alive?(view.pid)
    end

    test "F13 save success does NOT reset @text_search_query", %{conn: conn} do
      mare = Ideajar.Repo.get_by!(Ideajar.Categories.Category, name: "mare")

      view = mount_authenticated(conn)
      render_hook(view, "update_text_search", %{"q" => "mar"})

      open_form(view)
      render_click(view, "toggle_category", %{"id" => Integer.to_string(mare.id)})

      render_change(view, "save", %{
        "idea" => %{
          "title" => "Picnic improvviso",
          "duration" => "weekend"
        }
      })

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.text_search_query == "mar"
    end

    test "F11 clear_filters extension cascades @text_search_query to ''",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "update_text_search", %{"q" => "mar"})

      render_click(view, "clear_filters")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.text_search_query == ""
    end
  end

  describe "filter_active? refactor /5 → /1 (slice 8 step 4 — DD-S8-7)" do
    # Slice 7b extended filter_active?/3 → /5 (adding max_distance_index
    # + user_lat). Slice 8 collapses /5 → /1 socket-based BEFORE adding
    # the 6th text-search axis. This step is a behavior-preserving
    # refactor: tests pin the new arity, the disappearance of /5, and
    # invariance of the boolean output across all 5 existing axes.

    test "filter_active?/1 is exported and /5 is not (arity regression pin)" do
      assert function_exported?(IdeajarWeb.IdeaLive.Index, :filter_active?, 1)
      refute function_exported?(IdeajarWeb.IdeaLive.Index, :filter_active?, 5)
    end

    test "behavior-preservation: all-inactive assigns → false", %{conn: conn} do
      view = mount_authenticated(conn)
      assigns = :sys.get_state(view.pid).socket.assigns

      refute IdeajarWeb.IdeaLive.Index.filter_active?(assigns)
    end

    test "behavior-preservation: any single axis active → true", %{conn: conn} do
      view = mount_authenticated(conn)
      base = :sys.get_state(view.pid).socket.assigns

      # category active
      assert IdeajarWeb.IdeaLive.Index.filter_active?(%{base | filter_state: %{1 => :required}})
      # duration active
      assert IdeajarWeb.IdeaLive.Index.filter_active?(%{
               base
               | duration_filter: MapSet.new([:weekend])
             })

      # budget active (slice 9: index > 0)
      assert IdeajarWeb.IdeaLive.Index.filter_active?(%{base | max_budget_index: 4})
      # distance index > 0
      assert IdeajarWeb.IdeaLive.Index.filter_active?(%{base | max_distance_index: 3})
      # reference point set
      assert IdeajarWeb.IdeaLive.Index.filter_active?(%{base | user_lat: 43.5})
    end

    test "step 4 invariant (historical): /5 was a refactor target before step 5 added the text axis",
         %{conn: conn} do
      # Slice 8 step 4 was a pure refactor (filter_active?/5 → /1
      # socket-based). Step 5 then extended the BODY to include the
      # text-search axis. This test pins the post-step-5 contract:
      # text_search_query alone should activate the filter, in
      # parallel with the other 5 axes.
      view = mount_authenticated(conn)
      base = :sys.get_state(view.pid).socket.assigns

      assert IdeajarWeb.IdeaLive.Index.filter_active?(%{base | text_search_query: "mar"})
      refute IdeajarWeb.IdeaLive.Index.filter_active?(%{base | text_search_query: ""})
    end
  end

  describe "text search sub-block + integration (slice 8 step 5)" do
    test "renders the role=group sub-block with aria-label after Distanza",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

      assert html =~ ~s(role="group" aria-label="Filtra per testo")

      [_, after_distance] = String.split(html, ~s(aria-label="Filtra per distanza"), parts: 2)
      assert after_distance =~ ~s(aria-label="Filtra per testo")
    end

    test "renders the form wrapper + text input with the canonical attrs",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

      assert html =~ ~s(id="filter-text-search-form")
      assert html =~ ~s(phx-change="update_text_search")
      assert html =~ ~s(id="filter-text-search-input")
      assert html =~ ~s(name="filter[text_search]")
      assert html =~ ~s(placeholder="Cerca idee")
      assert html =~ ~s(autocomplete="off")
      assert html =~ ~s(maxlength="200")
      assert html =~ ~s(phx-debounce="300")
    end

    test "renders the visible 'Testo' sub-label and the NULL-exception helper text",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

      assert html =~ ~r{<p[^>]*class="[^"]*text-xs[^"]*"[^>]*>\s*Testo\s*</p>}
      assert html =~ "La ricerca trova le idee con la parola in titolo o descrizione."
    end

    test "F19 source order: Categorie → Durata → Budget → Distanza → Testo",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

      cat_pos = :binary.match(html, "Filtra per categoria") |> elem(0)
      dur_pos = :binary.match(html, "Filtra per durata") |> elem(0)
      bud_pos = :binary.match(html, "Filtra per budget") |> elem(0)
      dist_pos = :binary.match(html, "Filtra per distanza") |> elem(0)
      txt_pos = :binary.match(html, "Filtra per testo") |> elem(0)

      assert cat_pos < dur_pos
      assert dur_pos < bud_pos
      assert bud_pos < dist_pos
      assert dist_pos < txt_pos
    end

    test "Rimuovi filtro testo button hidden when query empty, visible when non-empty",
         %{conn: conn} do
      view = mount_authenticated(conn)
      refute render(view) =~ "Rimuovi filtro testo"

      render_hook(view, "update_text_search", %{"q" => "mar"})
      html = render(view)
      assert html =~ "Rimuovi filtro testo"
      assert html =~ ~s(phx-click="remove_text_search")
    end

    test "Rimuovi filtro testo button has hit area ≥ 44×44",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "update_text_search", %{"q" => "mar"})
      html = render(view)

      [button] = Regex.run(~r/<button[^>]*phx-click="remove_text_search"[^>]*>/, html)
      assert button =~ "min-h-11"
      assert button =~ "min-w-11"
    end

    test "filter_active? body extension: text_search_query non-empty alone → true",
         %{conn: conn} do
      view = mount_authenticated(conn)
      base = :sys.get_state(view.pid).socket.assigns

      assert IdeajarWeb.IdeaLive.Index.filter_active?(%{base | text_search_query: "mar"})
    end

    test "DD-S8-13 empty state: workspace non-empty + text query no-match → empty-filter state",
         %{conn: conn} do
      mare = Ideajar.Repo.get_by!(Ideajar.Categories.Category, name: "mare")

      %Ideajar.Ideas.Idea{title: "Sirolo"}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:categories, [mare])
      |> Ideajar.Repo.insert!()

      view = mount_authenticated(conn)
      render_hook(view, "update_text_search", %{"q" => "qqxz"})
      html = render(view)

      assert html =~ "Nessuna idea per i filtri attivi"
      assert html =~ "Mostra tutte"
    end

    test "F4 integration: render filters by typed text query (3+ chars)",
         %{conn: conn} do
      mare = Ideajar.Repo.get_by!(Ideajar.Categories.Category, name: "mare")

      [
        %Ideajar.Ideas.Idea{title: "Sirolo", description: "Mare bellissimo"},
        %Ideajar.Ideas.Idea{title: "Uffizi", description: "Galleria di Firenze"}
      ]
      |> Enum.each(fn idea ->
        idea
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:categories, [mare])
        |> Ideajar.Repo.insert!()
      end)

      view = mount_authenticated(conn)
      render_hook(view, "update_text_search", %{"q" => "Firenze"})
      html = render(view)

      assert html =~ "Uffizi"
      refute html =~ "Sirolo"
    end

    test "F5 form-shape (real-browser regression pin via form selector)",
         %{conn: conn} do
      view = mount_authenticated(conn)

      view
      |> form("#filter-text-search-form", filter: %{text_search: "mar"})
      |> render_change()

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.text_search_query == "mar"
    end

    test "F6 case-insensitive integration: query 'mare' matches 'MARE in tempesta'",
         %{conn: conn} do
      mare = Ideajar.Repo.get_by!(Ideajar.Categories.Category, name: "mare")

      %Ideajar.Ideas.Idea{title: "MARE in tempesta", description: nil}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:categories, [mare])
      |> Ideajar.Repo.insert!()

      view = mount_authenticated(conn)
      render_hook(view, "update_text_search", %{"q" => "mare"})

      assert render(view) =~ "MARE in tempesta"
    end

    test "F8 NULL-description integration: title match + description nil",
         %{conn: conn} do
      mare = Ideajar.Repo.get_by!(Ideajar.Categories.Category, name: "mare")

      %Ideajar.Ideas.Idea{title: "Picnic improvviso", description: nil}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:categories, [mare])
      |> Ideajar.Repo.insert!()

      view = mount_authenticated(conn)
      render_hook(view, "update_text_search", %{"q" => "picnic"})

      assert render(view) =~ "Picnic improvviso"
    end

    test "F14 combined AND at LV layer: text + category filter active together",
         %{conn: conn} do
      mare = Ideajar.Repo.get_by!(Ideajar.Categories.Category, name: "mare")
      cultura = Ideajar.Repo.get_by!(Ideajar.Categories.Category, name: "cultura")

      # mare + matching text → should remain visible.
      %Ideajar.Ideas.Idea{title: "Mare a Sirolo", description: "Spiaggia bianca"}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:categories, [mare])
      |> Ideajar.Repo.insert!()

      # cultura + matching text → filtered out by category.
      %Ideajar.Ideas.Idea{title: "Mare di libri", description: "Spiaggia letteraria"}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:categories, [cultura])
      |> Ideajar.Repo.insert!()

      # mare but no text match → filtered out by text.
      %Ideajar.Ideas.Idea{title: "Pizza in terrazza", description: "Cena estiva"}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:categories, [mare])
      |> Ideajar.Repo.insert!()

      view = mount_authenticated(conn)

      # Activate category filter (mare required) + text search (spiaggia).
      render_click(view, "cycle_filter", %{"id" => Integer.to_string(mare.id)})
      render_click(view, "cycle_filter", %{"id" => Integer.to_string(mare.id)})
      render_hook(view, "update_text_search", %{"q" => "spiaggia"})

      html = render(view)
      assert html =~ "Mare a Sirolo"
      refute html =~ "Mare di libri"
      refute html =~ "Pizza in terrazza"
    end

    test "S5 XSS regression: malicious query is HTML-escaped on the input value",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "update_text_search", %{"q" => "<script>alert(1)</script>"})

      html = render(view)
      refute html =~ "<script>alert(1)</script>"
      assert html =~ "&lt;script&gt;"
    end
  end

  describe "filter budget slider (slice 9 step 2)" do
    defp seed_idea_with_cost!(title, cost) do
      mare = Ideajar.Repo.get_by!(Ideajar.Categories.Category, name: "mare")

      %Ideajar.Ideas.Idea{title: title, estimated_cost: cost}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:categories, [mare])
      |> Ideajar.Repo.insert!()
    end

    test "F1/F3 mount: slider HTML5 + full ARIA, @max_budget_index default 0",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.max_budget_index == 0

      assert html =~ ~s(type="range")
      assert html =~ ~s(id="filter-budget-slider")
      assert html =~ ~s(min="0")
      assert html =~ ~s(max="7")
      assert html =~ ~s(aria-valuemin="0")
      assert html =~ ~s(aria-valuemax="7")
      assert html =~ ~s(aria-valuenow="0")
      assert html =~ ~s(aria-valuetext="Disattivo")
    end

    test "F2/A3 sub-block ha role=group aria-label='Filtra per budget'",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)
      assert html =~ ~s(role="group" aria-label="Filtra per budget")
    end

    test "F8/F4 update_max_budget index 0 → tutte le idee (NULL-cost passa)",
         %{conn: conn} do
      seed_idea_with_cost!("Caffè", 0)
      seed_idea_with_cost!("Sirolo", 200)
      seed_idea_with_cost!("Bagno", nil)

      view = mount_authenticated(conn)
      render_hook(view, "update_max_budget", %{"value" => "0"})
      html = render(view)

      assert html =~ "Caffè"
      assert html =~ "Sirolo"
      assert html =~ "Bagno"
    end

    test "F5 slider index 1 (gratis) → solo cost == 0, NULL escluse",
         %{conn: conn} do
      seed_idea_with_cost!("Caffè", 0)
      seed_idea_with_cost!("Sirolo", 200)
      seed_idea_with_cost!("Bagno", nil)

      view = mount_authenticated(conn)
      render_hook(view, "update_max_budget", %{"value" => "1"})
      html = render(view)

      assert html =~ "Caffè"
      refute html =~ "Sirolo"
      refute html =~ "Bagno"
    end

    test "F6 slider index 4 (100€) → cost ≤ 100, NULL escluse", %{conn: conn} do
      seed_idea_with_cost!("Caffè", 0)
      seed_idea_with_cost!("Uffizi", 50)
      seed_idea_with_cost!("Stadio", 100)
      seed_idea_with_cost!("Sirolo", 200)
      seed_idea_with_cost!("Bagno", nil)

      view = mount_authenticated(conn)
      render_hook(view, "update_max_budget", %{"value" => "4"})
      html = render(view)

      assert html =~ "Caffè"
      assert html =~ "Uffizi"
      assert html =~ "Stadio"
      refute html =~ "Sirolo"
      refute html =~ "Bagno"
    end

    test "F9 form-shape %{filter: %{budget: '3'}} → identico a bare-shape",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "update_max_budget", %{"filter" => %{"budget" => "3"}})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.max_budget_index == 3
    end

    test "F10/S1/S2/S3 hostile uniform list → no-op", %{conn: conn} do
      view = mount_authenticated(conn)

      hostile = [
        %{"value" => "-1"},
        %{"value" => "8"},
        %{"value" => "abc"},
        %{"value" => "3.5"},
        %{}
      ]

      Enum.each(hostile, fn p ->
        render_hook(view, "update_max_budget", p)
      end)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.max_budget_index == 0
      assert Process.alive?(view.pid)
    end

    test "F12 'Rimuovi filtro budget' button hidden when index 0, visible when > 0",
         %{conn: conn} do
      view = mount_authenticated(conn)
      refute render(view) =~ "Rimuovi filtro budget"

      render_hook(view, "update_max_budget", %{"value" => "3"})
      html = render(view)
      assert html =~ "Rimuovi filtro budget"
      assert html =~ ~s(phx-click="remove_budget_filter")
    end

    test "F11 click 'Rimuovi filtro budget' → @max_budget_index = 0",
         %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "update_max_budget", %{"value" => "3"})

      render_click(view, "remove_budget_filter")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.max_budget_index == 0
    end

    test "F13 clear_filters cascade reset @max_budget_index = 0", %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "update_max_budget", %{"value" => "3"})

      render_click(view, "clear_filters")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.max_budget_index == 0
    end

    test "F14 refresh resets @max_budget_index (LV remount)", %{conn: conn} do
      view1 = mount_authenticated(conn)
      render_hook(view1, "update_max_budget", %{"value" => "4"})

      view2 = mount_authenticated(conn)
      assigns = :sys.get_state(view2.pid).socket.assigns
      assert assigns.max_budget_index == 0
    end

    test "F16 phx-debounce='200' pinned in slider attributes", %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)
      assert html =~ ~s(phx-debounce="200")
    end

    test "F17 filter-budget-slider-form wraps the input (real-browser pin)",
         %{conn: conn} do
      view = mount_authenticated(conn)

      view
      |> form("#filter-budget-slider-form", filter: %{budget: "3"})
      |> render_change()

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.max_budget_index == 3
    end

    test "A6 'Rimuovi filtro budget' hit area ≥ 44×44", %{conn: conn} do
      view = mount_authenticated(conn)
      render_hook(view, "update_max_budget", %{"value" => "3"})
      html = render(view)

      [button] = Regex.run(~r/<button[^>]*phx-click="remove_budget_filter"[^>]*>/, html)
      assert button =~ "min-h-11"
      assert button =~ "min-w-11"
    end

    test "A8 sub-block source order Categorie → Durata → Budget → Distanza → Testo invariato",
         %{conn: conn} do
      view = mount_authenticated(conn)
      html = render(view)

      cat = :binary.match(html, "Filtra per categoria") |> elem(0)
      dur = :binary.match(html, "Filtra per durata") |> elem(0)
      bud = :binary.match(html, "Filtra per budget") |> elem(0)
      dist = :binary.match(html, "Filtra per distanza") |> elem(0)
      txt = :binary.match(html, "Filtra per testo") |> elem(0)

      assert cat < dur
      assert dur < bud
      assert bud < dist
      assert dist < txt
    end

    test "@cost_filter assign no longer exists post-rename (DD-S9-5)", %{conn: conn} do
      view = mount_authenticated(conn)
      assigns = :sys.get_state(view.pid).socket.assigns
      refute Map.has_key?(assigns, :cost_filter)
      assert Map.has_key?(assigns, :max_budget_index)
    end
  end

  describe "form budget slider (slice 9 step 3)" do
    test "FF1/FF2 mount form: HTML5 slider 0..7, default value 0, NO chip group",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      html = render(view)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.form_budget_index == 0

      assert html =~ ~s(id="form-budget-slider")
      assert html =~ ~s(type="range")
      assert html =~ ~s(name="idea[budget]")

      [slider] = Regex.run(~r/<input[^>]*id="form-budget-slider"[^>]*>/, html)
      assert slider =~ ~s(min="0")
      assert slider =~ ~s(max="7")
      assert slider =~ ~s(value="0")

      refute html =~ "form-budget-chip-"
    end

    test "FF8/A2 form aria-valuetext usa BudgetLabels.form (NOT 'fino a')",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      html = render(view)

      [slider] = Regex.run(~r/<input[^>]*id="form-budget-slider"[^>]*>/, html)
      assert slider =~ ~s(aria-valuetext="Non specificato")

      render_hook(view, "update_form_budget", %{"value" => "4"})
      html = render(view)
      [slider] = Regex.run(~r/<input[^>]*id="form-budget-slider"[^>]*>/, html)
      assert slider =~ ~s(aria-valuetext="100€")
      refute slider =~ "fino a"
    end

    test "FF5 update_form_budget con index 0..7 → assign", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      render_hook(view, "update_form_budget", %{"value" => "3"})
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.form_budget_index == 3
    end

    test "form-shape extractor: %{idea: %{budget: '3'}} → assign", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      render_hook(view, "update_form_budget", %{"idea" => %{"budget" => "3"}})
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.form_budget_index == 3
    end

    test "FF6/S4 hostile uniform list → no-op", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()

      hostile = [
        %{"value" => "-1"},
        %{"value" => "8"},
        %{"value" => "abc"},
        %{"value" => "3.5"},
        %{}
      ]

      Enum.each(hostile, fn p ->
        render_hook(view, "update_form_budget", p)
      end)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.form_budget_index == 0
      assert Process.alive?(view.pid)
    end

    test "FF3 slider index 0 + valid submit → idea con estimated_cost = nil",
         %{conn: conn} do
      mare = Ideajar.Repo.get_by!(Ideajar.Categories.Category, name: "mare")

      view = mount_authenticated(conn) |> open_form()
      render_click(view, "toggle_category", %{"id" => Integer.to_string(mare.id)})
      # form_budget_index resta 0

      render_change(view, "save", %{
        "idea" => %{"title" => "Senza prezzo", "duration" => "weekend"}
      })

      idea = Ideajar.Repo.get_by!(Ideajar.Ideas.Idea, title: "Senza prezzo")
      assert idea.estimated_cost == nil
    end

    test "FF4 slider index 4 + valid submit → idea con estimated_cost = 100",
         %{conn: conn} do
      mare = Ideajar.Repo.get_by!(Ideajar.Categories.Category, name: "mare")

      view = mount_authenticated(conn) |> open_form()
      render_click(view, "toggle_category", %{"id" => Integer.to_string(mare.id)})
      render_hook(view, "update_form_budget", %{"value" => "4"})

      render_change(view, "save", %{
        "idea" => %{"title" => "Da 100€", "duration" => "weekend"}
      })

      idea = Ideajar.Repo.get_by!(Ideajar.Ideas.Idea, title: "Da 100€")
      assert idea.estimated_cost == 100
    end

    test "FF7 save success cascade reset @form_budget_index = 0",
         %{conn: conn} do
      mare = Ideajar.Repo.get_by!(Ideajar.Categories.Category, name: "mare")

      view = mount_authenticated(conn) |> open_form()
      render_click(view, "toggle_category", %{"id" => Integer.to_string(mare.id)})
      render_hook(view, "update_form_budget", %{"value" => "4"})

      render_change(view, "save", %{
        "idea" => %{"title" => "Salvata", "duration" => "weekend"}
      })

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.form_budget_index == 0
    end

    test "FF10 'Rimuovi prezzo' button hidden when index 0, visible when > 0",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      refute render(view) =~ "Rimuovi prezzo"

      render_hook(view, "update_form_budget", %{"value" => "3"})
      html = render(view)
      assert html =~ "Rimuovi prezzo"
      assert html =~ ~s(phx-click="remove_form_budget")
    end

    test "FF10 click 'Rimuovi prezzo' → @form_budget_index = 0",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      render_hook(view, "update_form_budget", %{"value" => "5"})

      render_click(view, "remove_form_budget")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.form_budget_index == 0
    end

    test "FF10 'Rimuovi prezzo' button hit area ≥ 44×44", %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      render_hook(view, "update_form_budget", %{"value" => "3"})
      html = render(view)

      [button] = Regex.run(~r/<button[^>]*phx-click="remove_form_budget"[^>]*>/, html)
      assert button =~ "min-h-11"
      assert button =~ "min-w-11"
    end

    test "S6 hostile form param idea[budget]=999 → estimated_cost = nil",
         %{conn: conn} do
      mare = Ideajar.Repo.get_by!(Ideajar.Categories.Category, name: "mare")

      view = mount_authenticated(conn) |> open_form()
      render_click(view, "toggle_category", %{"id" => Integer.to_string(mare.id)})

      # Hostile update → no-op (assign rimane 0). DM3a clamp garantisce
      # no Integer.to_string(:error) crash.
      render_hook(view, "update_form_budget", %{"idea" => %{"budget" => "999"}})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.form_budget_index == 0
      assert Process.alive?(view.pid)

      render_change(view, "save", %{
        "idea" => %{"title" => "Hostile", "duration" => "weekend"}
      })

      idea = Ideajar.Repo.get_by!(Ideajar.Ideas.Idea, title: "Hostile")
      assert idea.estimated_cost == nil
    end

    test "@selected_cost assign no longer exists post-rename (DD-S9-5)",
         %{conn: conn} do
      view = mount_authenticated(conn) |> open_form()
      assigns = :sys.get_state(view.pid).socket.assigns
      refute Map.has_key?(assigns, :selected_cost)
      assert Map.has_key?(assigns, :form_budget_index)
    end
  end

  describe "BudgetChip lifecycle (slice 9 step 4)" do
    test "C1: lib/ideajar_web/components/budget_chip.ex does NOT exist" do
      refute File.exists?(Path.join(File.cwd!(), "lib/ideajar_web/components/budget_chip.ex"))
    end

    test "C2: test/ideajar_web/components/budget_chip_test.exs does NOT exist" do
      refute File.exists?(
               Path.join(File.cwd!(), "test/ideajar_web/components/budget_chip_test.exs")
             )
    end

    test "C3: no production source under lib/ contains executable BudgetChip references" do
      sources = Path.wildcard("lib/**/*.{ex,heex}")

      callsites =
        Enum.flat_map(sources, fn path ->
          src = File.read!(path)

          if src =~ ~r/(import|alias)\s+IdeajarWeb\.Components\.BudgetChip/ or
               src =~ ~r/<\s*BudgetChip\./ or
               src =~ ~r/\bBudgetChip\.(form_chip|filter_chip|budget_badge)\(/ do
            [path]
          else
            []
          end
        end)

      assert callsites == [],
             "BudgetChip executable references found in: #{inspect(callsites)}"
    end

    test "C4: BudgetBadge module exists post-extraction (rendering invariato)" do
      assert File.exists?(Path.join(File.cwd!(), "lib/ideajar_web/components/budget_badge.ex"))

      assert function_exported?(IdeajarWeb.Components.BudgetBadge, :badge, 1)
    end

    test "C5: BudgetLabels module exists with filter/1 + form/1" do
      assert function_exported?(IdeajarWeb.Components.BudgetLabels, :filter, 1)
      assert function_exported?(IdeajarWeb.Components.BudgetLabels, :form, 1)
    end

    test "A7: CSS thumb touch target rules for the 2 budget sliders" do
      app_css = File.read!(Path.join(File.cwd!(), "assets/css/app.css"))

      assert app_css =~ "#filter-budget-slider::-webkit-slider-thumb"
      assert app_css =~ "#filter-budget-slider::-moz-range-thumb"
      assert app_css =~ "#form-budget-slider::-webkit-slider-thumb"
      assert app_css =~ "#form-budget-slider::-moz-range-thumb"
    end
  end

  describe "filter row collapse (slice 9 follow-up)" do
    test "mount: filter row is collapsed by default", %{conn: conn} do
      view = mount_authenticated_collapsed(conn)
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.filters_expanded? == false

      html = render(view)
      # Toggle button is always visible
      assert html =~ "Filtri"
      assert html =~ ~s(phx-click="toggle_filters")
      # Sub-blocks are NOT rendered when collapsed
      refute html =~ ~s(aria-label="Filtra per categoria")
      refute html =~ ~s(aria-label="Filtra per durata")
      refute html =~ ~s(aria-label="Filtra per budget")
      refute html =~ ~s(aria-label="Filtra per distanza")
      refute html =~ ~s(aria-label="Filtra per testo")
    end

    test "click 'Filtri' button expands the row and renders all sub-blocks",
         %{conn: conn} do
      view = mount_authenticated_collapsed(conn)
      render_click(view, "toggle_filters")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.filters_expanded? == true

      html = render(view)
      assert html =~ ~s(aria-label="Filtra per categoria")
      assert html =~ ~s(aria-label="Filtra per durata")
      assert html =~ ~s(aria-label="Filtra per budget")
      assert html =~ ~s(aria-label="Filtra per distanza")
      assert html =~ ~s(aria-label="Filtra per testo")
    end

    test "toggle_filters is idempotent — collapsed → expanded → collapsed",
         %{conn: conn} do
      view = mount_authenticated_collapsed(conn)
      render_click(view, "toggle_filters")
      assert :sys.get_state(view.pid).socket.assigns.filters_expanded? == true

      render_click(view, "toggle_filters")
      assert :sys.get_state(view.pid).socket.assigns.filters_expanded? == false
    end

    test "aria-expanded mirrors the @filters_expanded? assign", %{conn: conn} do
      view = mount_authenticated_collapsed(conn)

      [button] =
        Regex.run(~r/<button[^>]*phx-click="toggle_filters"[^>]*>/, render(view))

      assert button =~ ~s(aria-expanded="false")

      render_click(view, "toggle_filters")

      [button] =
        Regex.run(~r/<button[^>]*phx-click="toggle_filters"[^>]*>/, render(view))

      assert button =~ ~s(aria-expanded="true")
    end

    test "active filter counter: 0 active → label 'Filtri' (no parens)",
         %{conn: conn} do
      view = mount_authenticated_collapsed(conn)
      html = render(view)
      assert html =~ "Filtri"
      refute html =~ ~r/Filtri\s*\(\d+\)/
    end

    test "active filter counter: 1 active → label 'Filtri (1)'", %{conn: conn} do
      view = mount_authenticated_collapsed(conn)
      render_click(view, "toggle_filters")
      render_hook(view, "update_text_search", %{"q" => "mar"})
      render_click(view, "toggle_filters")

      html = render(view)
      assert html =~ ~r/Filtri\s*\(1\)/
    end

    test "active filter counter: counts the 5 axes (categoria, durata, budget, distanza, testo)",
         %{conn: conn} do
      view = mount_authenticated_collapsed(conn)
      mare = Ideajar.Repo.get_by!(Ideajar.Categories.Category, name: "mare")

      render_click(view, "toggle_filters")
      render_click(view, "cycle_filter", %{"id" => Integer.to_string(mare.id)})
      render_click(view, "toggle_duration_filter", %{"duration" => "weekend"})
      render_hook(view, "update_max_budget", %{"value" => "4"})
      render_hook(view, "set_user_location", %{"lat" => 43.5, "lng" => 13.6})
      render_hook(view, "update_max_distance", %{"value" => "3"})
      render_hook(view, "update_text_search", %{"q" => "mar"})
      render_click(view, "toggle_filters")

      html = render(view)
      # 5 logical axes: distanza counts once even with both ref + slider set.
      assert html =~ ~r/Filtri\s*\(5\)/
    end

    test "F refresh: filter expansion state resets on remount (LV-session only)",
         %{conn: conn} do
      view1 = mount_authenticated_collapsed(conn)
      render_click(view1, "toggle_filters")
      assert :sys.get_state(view1.pid).socket.assigns.filters_expanded? == true

      view2 = mount_authenticated_collapsed(conn)
      assert :sys.get_state(view2.pid).socket.assigns.filters_expanded? == false
    end
  end

  describe "delete trash button on idea cards (slice 12 step 2)" do
    test "each rendered card carries a delete button with required attributes",
         %{conn: conn} do
      insert_idea_with_categories!("Sirolo", ["mare"], ~U[2026-04-27 10:00:00Z])
      insert_idea_with_categories!("Uffizi", ["museo"], ~U[2026-04-27 10:01:00Z])
      insert_idea_with_categories!("Stadio", ["sport"], ~U[2026-04-27 10:02:00Z])

      view = mount_authenticated(conn)
      html = render(view)

      [%{id: id1}, %{id: id2}, %{id: id3}] =
        Idea
        |> Repo.all()
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

      # Each card must expose its own delete button keyed by id.
      for id <- [id1, id2, id3] do
        assert html =~ ~s|id="delete-btn-#{id}"|
        assert html =~ ~s|phx-value-id="#{id}"|
      end

      # Attribute set required by the spec/plan: aria-label, type=button,
      # phx-click=request_delete, sr-only fallback span.
      delete_buttons = Regex.scan(~r{<button[^>]*id="delete-btn-\d+"[^>]*>.*?</button>}s, html)
      assert length(delete_buttons) == 3

      Enum.each(delete_buttons, fn [btn] ->
        assert btn =~ ~s|aria-label="Elimina idea"|
        assert btn =~ ~s|type="button"|
        assert btn =~ ~s|phx-click="request_delete"|
        assert btn =~ ~s|<span class="sr-only">Elimina</span>|
      end)
    end
  end

  describe "delete confirmation modal opens on trash click (slice 12 step 3)" do
    test "no modal renders before any trash click", %{conn: conn} do
      insert_idea_with_categories!("Sirolo", ["mare"], ~U[2026-04-27 10:00:00Z])
      view = mount_authenticated(conn)
      html = render(view)

      refute html =~ ~s|role="dialog"|
      refute html =~ "Eliminare questa idea?"
    end

    test "request_delete opens a dialog with the idea title and required ARIA wiring",
         %{conn: conn} do
      idea =
        insert_idea_with_categories!(
          "Mare a Sirolo",
          ["mare"],
          ~U[2026-04-27 10:00:00Z]
        )

      view = mount_authenticated(conn)
      html = render_click(view, "request_delete", %{"id" => "#{idea.id}"})

      # Dialog wiring (role + ARIA labelling + describing).
      assert html =~ ~s|role="dialog"|
      assert html =~ ~s|aria-modal="true"|
      assert html =~ ~s|aria-labelledby="delete-modal-title"|
      assert html =~ ~s|aria-describedby="delete-modal-body"|
      assert html =~ ~s|id="delete-modal"|

      # Title and body content (with idea title interpolated).
      assert html =~ ~r{<h2 id="delete-modal-title"[^>]*>Eliminare questa idea\?</h2>}
      assert html =~ ~s|id="delete-modal-body"|
      assert html =~ ~s|Elimina l&#39;idea &quot;Mare a Sirolo&quot;|
      assert html =~ "L&#39;idea sarà rimossa definitivamente."

      # Buttons present with the required attributes.
      assert html =~ ~s|id="delete-cancel-btn"|
      assert html =~ ~r/<button[^>]*id="delete-cancel-btn"[^>]*type="button"[^>]*phx-click="cancel_delete"[^>]*>Annulla<\/button>/

      # F13: confirm button carries phx-disable-with attribute.
      assert html =~
               ~r/<button[^>]*type="button"[^>]*phx-click="confirm_delete"[^>]*phx-disable-with="Eliminazione…"[^>]*>Elimina<\/button>/
    end

    test "F10: opening the modal pushes focus to the cancel button", %{conn: conn} do
      idea = insert_idea_with_categories!("Sirolo", ["mare"], ~U[2026-04-27 10:00:00Z])

      view = mount_authenticated(conn)
      render_click(view, "request_delete", %{"id" => "#{idea.id}"})

      assert_push_event(view, "ideajar:focus", %{to: "#delete-cancel-btn"})
    end

    test "F5 XSS: the idea title is HTML-escaped in the modal body", %{conn: conn} do
      idea =
        insert_idea_with_categories!(
          "<script>alert(1)</script>",
          ["mare"],
          ~U[2026-04-27 10:00:00Z]
        )

      view = mount_authenticated(conn)
      html = render_click(view, "request_delete", %{"id" => "#{idea.id}"})

      assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
      refute html =~ "<script>alert(1)</script>"
    end

    test "F11: request_delete with an id not in @ideas is a silent no-op", %{conn: conn} do
      insert_idea_with_categories!("Sirolo", ["mare"], ~U[2026-04-27 10:00:00Z])

      view = mount_authenticated(conn)
      html = render_click(view, "request_delete", %{"id" => "99999999"})

      refute html =~ ~s|role="dialog"|
      assert Process.alive?(view.pid)
    end

    defp open_delete_modal(view, idea_id) do
      render_click(view, "request_delete", %{"id" => "#{idea_id}"})
      view
    end

    test "click on Annulla closes the modal and pushes focus back to the trash button",
         %{conn: conn} do
      idea = insert_idea_with_categories!("Sirolo", ["mare"], ~U[2026-04-27 10:00:00Z])
      target = "#delete-btn-#{idea.id}"

      view = mount_authenticated(conn) |> open_delete_modal(idea.id)
      html = render_click(view, "cancel_delete")

      refute html =~ ~s|role="dialog"|
      assert Repo.aggregate(Idea, :count) == 1
      assert_push_event(view, "ideajar:focus", %{to: ^target})
    end

    test "Escape key closes the modal and pushes focus back to the trash button",
         %{conn: conn} do
      idea = insert_idea_with_categories!("Sirolo", ["mare"], ~U[2026-04-27 10:00:00Z])
      target = "#delete-btn-#{idea.id}"

      view = mount_authenticated(conn) |> open_delete_modal(idea.id)

      html =
        view
        |> element("#delete-modal")
        |> render_keydown(%{"key" => "Escape"})

      refute html =~ ~s|role="dialog"|
      assert Repo.aggregate(Idea, :count) == 1
      assert_push_event(view, "ideajar:focus", %{to: ^target})
    end

    test "click on the backdrop closes the modal and pushes focus back to the trash button",
         %{conn: conn} do
      idea = insert_idea_with_categories!("Sirolo", ["mare"], ~U[2026-04-27 10:00:00Z])
      target = "#delete-btn-#{idea.id}"

      view = mount_authenticated(conn) |> open_delete_modal(idea.id)

      html =
        view
        |> element("#delete-modal .backdrop")
        |> render_click()

      refute html =~ ~s|role="dialog"|
      assert Repo.aggregate(Idea, :count) == 1
      assert_push_event(view, "ideajar:focus", %{to: ^target})
    end

    test "cancel_delete with no open modal is a silent no-op", %{conn: conn} do
      view = mount_authenticated(conn)
      html = render_click(view, "cancel_delete")

      refute html =~ ~s|role="dialog"|
      assert Process.alive?(view.pid)
    end

    test "R2: backdrop fires cancel_delete and the dialog content does not",
         %{conn: conn} do
      idea = insert_idea_with_categories!("Sirolo", ["mare"], ~U[2026-04-27 10:00:00Z])

      view = mount_authenticated(conn)
      html = render_click(view, "request_delete", %{"id" => "#{idea.id}"})

      # The backdrop is a sibling of the dialog content (not its parent),
      # so an internal click can't bubble-cancel.
      assert html =~ ~r{<div class="backdrop" phx-click="cancel_delete">\s*</div>}

      # Inside the modal markup we expect exactly two `phx-click="cancel_delete"`
      # occurrences: one on the backdrop, one on the Annulla button. If a third
      # appears it has likely been added to the dialog content div, which would
      # let an internal click bubble-cancel.
      modal_chunk =
        case Regex.run(
               ~r{<div[^>]*id="delete-modal"[^>]*>(.*?)</div></div>}s,
               html
             ) do
          [_, inner] -> inner
          _ -> flunk("delete-modal wrapper not found in rendered HTML")
        end

      cancel_clicks =
        Regex.scan(~r{phx-click="cancel_delete"}, modal_chunk)
        |> length()

      assert cancel_clicks == 2,
             "expected exactly 2 phx-click=cancel_delete in modal (backdrop + Annulla), got #{cancel_clicks}"
    end
  end

  describe "confirm_delete happy path with focus successor (slice 12 step 5)" do
    defp open_and_confirm_delete(view, idea_id) do
      render_click(view, "request_delete", %{"id" => "#{idea_id}"})
      render_click(view, "confirm_delete")
    end

    test "deleting a middle card removes the idea, flashes success, focuses the next card",
         %{conn: conn} do
      # Render order is inserted_at DESC, so the rendered list is:
      # [recente, middle, vecchia]. Deleting "recente" (top) leaves
      # [middle, vecchia] and the focus successor is the next card,
      # which in render order is "middle".
      _vecchia =
        insert_idea_with_categories!("Vecchia", ["mare"], ~U[2026-04-26 10:00:00Z])

      middle =
        insert_idea_with_categories!("Middle", ["mare"], ~U[2026-04-27 10:00:00Z])

      recente =
        insert_idea_with_categories!("Recente", ["mare"], ~U[2026-04-28 10:00:00Z])

      target = "#delete-btn-#{middle.id}"

      view = mount_authenticated(conn)
      html = open_and_confirm_delete(view, recente.id)

      refute html =~ ~s|role="dialog"|
      refute html =~ "Recente"
      assert html =~ "Middle"
      assert html =~ "Vecchia"
      assert html =~ "Idea eliminata"
      # Phoenix flash uses role="status" for info-level messages; assert
      # both are present without pinning their exact DOM proximity.
      assert html =~ ~s|role="status"|

      assert Repo.get(Idea, recente.id) == nil
      assert Repo.aggregate(Idea, :count) == 2
      assert_push_event(view, "ideajar:focus", %{to: ^target})
    end

    test "deleting the last card in render order focuses the previous card",
         %{conn: conn} do
      # Deleting "Vecchia" (last in render order) leaves [Recente, Middle]
      # and the focus successor falls back to the previous card "Middle".
      vecchia =
        insert_idea_with_categories!("Vecchia", ["mare"], ~U[2026-04-26 10:00:00Z])

      middle =
        insert_idea_with_categories!("Middle", ["mare"], ~U[2026-04-27 10:00:00Z])

      _recente =
        insert_idea_with_categories!("Recente", ["mare"], ~U[2026-04-28 10:00:00Z])

      target = "#delete-btn-#{middle.id}"

      view = mount_authenticated(conn)
      html = open_and_confirm_delete(view, vecchia.id)

      refute html =~ "Vecchia"
      assert Repo.aggregate(Idea, :count) == 2
      assert_push_event(view, "ideajar:focus", %{to: ^target})
    end

    test "deleting the only card focuses the add-idea button and shows the empty state",
         %{conn: conn} do
      idea = insert_idea_with_categories!("Solo", ["mare"], ~U[2026-04-27 10:00:00Z])

      view = mount_authenticated(conn)
      html = open_and_confirm_delete(view, idea.id)

      refute html =~ ~s|role="dialog"|
      assert Repo.aggregate(Idea, :count) == 0
      assert html =~ "Nessuna idea ancora. Aggiungine una qui sopra."
      assert_push_event(view, "ideajar:focus", %{to: "#add-idea-button"})
    end
  end

  describe "confirm_delete error branches (slice 12 step 6)" do
    defp inject_delete_fun!(view, fun) do
      :sys.replace_state(view.pid, fn state ->
        socket = Phoenix.Component.assign(state.socket, :delete_idea_fun, fun)
        %{state | socket: socket}
      end)

      view
    end

    test "F8 race: confirming a deletion already done elsewhere flashes 'Idea già eliminata' and refreshes",
         %{conn: conn} do
      _vecchia =
        insert_idea_with_categories!("Vecchia", ["mare"], ~U[2026-04-26 10:00:00Z])

      target =
        insert_idea_with_categories!("Bersaglio", ["mare"], ~U[2026-04-27 10:00:00Z])

      _recente =
        insert_idea_with_categories!("Recente", ["mare"], ~U[2026-04-28 10:00:00Z])

      view = mount_authenticated(conn)
      render_click(view, "request_delete", %{"id" => "#{target.id}"})

      # Out-of-band: another device removes the same idea before we
      # confirm. The LiveView still holds the stale modal state.
      Repo.delete!(target)

      html = render_click(view, "confirm_delete")

      refute html =~ ~s|role="dialog"|
      assert html =~ "Idea già eliminata"
      assert html =~ ~s|role="status"|
      refute html =~ "Bersaglio"
      assert Repo.aggregate(Idea, :count) == 2
      assert_push_event(view, "ideajar:focus", %{to: "#add-idea-button"})
      assert Process.alive?(view.pid)
    end

    test "F9 DB error: an unexpected Repo failure flashes a retry hint and keeps the modal open",
         %{conn: conn} do
      idea = insert_idea_with_categories!("Sirolo", ["mare"], ~U[2026-04-27 10:00:00Z])

      view = mount_authenticated(conn)
      render_click(view, "request_delete", %{"id" => "#{idea.id}"})

      inject_delete_fun!(view, fn _id ->
        {:error,
         %Ecto.Changeset{
           data: %Idea{},
           valid?: false,
           errors: [base: {"db down", []}]
         }}
      end)

      html = render_click(view, "confirm_delete")

      assert html =~ "Eliminazione non riuscita, riprova"
      assert html =~ ~s|role="alert"|
      # Modal must remain visible so the user can retry or cancel.
      assert html =~ ~s|role="dialog"|
      assert html =~ "Eliminare questa idea?"
      assert Repo.aggregate(Idea, :count) == 1
      assert Process.alive?(view.pid)
    end

    test "F9 DB error: confirming again from the still-open modal still hits the stub once more",
         %{conn: conn} do
      # Anti-regression: the modal stays open exactly so the user can
      # retry — make sure the second confirm goes through the same code
      # path (no silent no-op).
      idea = insert_idea_with_categories!("Sirolo", ["mare"], ~U[2026-04-27 10:00:00Z])

      view = mount_authenticated(conn)
      render_click(view, "request_delete", %{"id" => "#{idea.id}"})

      counter = :counters.new(1, [])

      inject_delete_fun!(view, fn _id ->
        :counters.add(counter, 1, 1)
        {:error, %Ecto.Changeset{data: %Idea{}, valid?: false, errors: []}}
      end)

      render_click(view, "confirm_delete")
      render_click(view, "confirm_delete")

      assert :counters.get(counter, 1) == 2
      assert Repo.aggregate(Idea, :count) == 1
    end
  end

  describe "active filters survive a delete (slice 12 step 7)" do
    test "deleting a card while a category filter is required keeps the other filtered card and the filter state",
         %{conn: conn} do
      # Pin: confirm_delete must rebuild the list via reload_ideas/1
      # (which reads filter_state from assigns), not via Ideas.list_ideas/0.
      mare = CategoriesFixtures.category_by_name!("mare")

      to_delete =
        insert_idea_with_categories!("Mare-uno", ["mare"], ~U[2026-04-27 10:00:00Z])

      _other_with_mare =
        insert_idea_with_categories!("Mare-due", ["mare"], ~U[2026-04-26 10:00:00Z])

      _museo_only =
        insert_idea_with_categories!("Museo", ["museo"], ~U[2026-04-25 10:00:00Z])

      view = mount_authenticated(conn)

      # Two clicks → :required state on "mare" → only the two
      # mare-tagged ideas remain visible.
      render_click(view, "cycle_filter", %{"id" => "#{mare.id}"})
      render_click(view, "cycle_filter", %{"id" => "#{mare.id}"})

      pre = render(view)
      assert pre =~ "Mare-uno"
      assert pre =~ "Mare-due"
      refute pre =~ "Museo"

      # Confirm delete on "Mare-uno". The filter must survive.
      render_click(view, "request_delete", %{"id" => "#{to_delete.id}"})
      html = render_click(view, "confirm_delete")

      refute html =~ "Mare-uno"
      assert html =~ "Mare-due"
      refute html =~ "Museo"

      # Filter state assign is unchanged.
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.filter_state[mare.id] == :required
    end
  end
end
