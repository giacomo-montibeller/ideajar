# Spec: Add a base idea (title + description + link)

> Slice 2 of the ideajar project (see `CONTEXT.md` and `plans/slice-1-device-password-auth.md` for the slice list). Foundation feature: lets the couple add ideas and see them in a list, with no filters or categorization yet.

## Intent Description

La rotta `/` (oggi placeholder "Workspace privato") diventa una **LiveView** con la lista delle idee della coppia. In alto c'è un bottone **`+ Aggiungi idea`**: al click si espande sotto un form con tre campi (titolo, descrizione, link), inizialmente collassato. Submit corretto → idea persistita su SQLite, form svuotato e ricollassato, focus sul bottone "Aggiungi". Click su "✕" → form collassa senza salvare. Lista ordinata per `inserted_at` decrescente.

Form: **titolo** obbligatorio (1–200 char, trimmato), **descrizione** facoltativa (≤5000 char, free-text con `white-space: pre-wrap` per preservare a-capo), **link** facoltativo (≤2000 char; se popolato deve avere schema `http://` o `https://` ed essere parsabile come URI con host valido). Validazione **on-submit** via Ecto changeset; errori in cima al form. Description e link visualizzati per intero, link sempre con `target="_blank" rel="noopener noreferrer"`.

Spazio condiviso: nessuna `created_by`, nessuna privacy per idea. Modifica e cancellazione fuori scope; filtri/categorie fuori scope (slice 3-8). Nessun real-time push tra device: l'utente B vede l'idea di A solo al refresh.

LiveView `mount/3` verifica `session["authenticated"] == true` defense-in-depth e redirect a `/login?return_to=%2F` altrimenti — chiude il warning R3 di slice 1.

## User-Facing Behavior

```gherkin
Feature: Add a base idea (title + description + link) and see it in the list

  Background:
    Given my browser holds a valid signed session cookie marking this device as authenticated
    And the workspace currently has no ideas

  # ── Empty state ─────────────────────────────────────────────────────
  Scenario: Empty state shows the helpful prompt
    When I visit "/"
    Then I see a button labelled "+ Aggiungi idea"
    And no ideas list is visible
    And I see the empty-state message "Nessuna idea ancora. Aggiungine una qui sopra."

  # ── Form expansion / collapse ───────────────────────────────────────
  Scenario: Add-idea form is collapsed by default
    When I visit "/"
    Then the add-idea form is not visible in the rendered DOM
    And the "+ Aggiungi idea" button is enabled

  Scenario: Clicking the add button expands the form
    Given I am on "/"
    When I click "+ Aggiungi idea"
    Then the add-idea form becomes visible
    And the title input has autofocus
    And I see a "Salva" button and a "✕" close icon

  Scenario: Clicking the close icon collapses the form without saving
    Given the add-idea form is expanded
    And I have typed "Mare a Sirolo" into the title field
    When I click the "✕" close icon
    Then the form is no longer visible
    And the workspace still has no ideas

  # ── Successful creation ─────────────────────────────────────────────
  Scenario: Submitting valid input creates the idea, collapses the form, and shows it in the list
    Given the add-idea form is expanded
    When I fill in "Mare a Sirolo" as the title
    And I fill in "Spiaggia delle due Sorelle, partenza presto" as the description
    And I fill in "https://www.parcodelconero.com/sirolo/" as the link
    And I submit the form
    Then the idea "Mare a Sirolo" appears at the top of the list
    And I see its description "Spiaggia delle due Sorelle, partenza presto"
    And I see its link rendered as <a href="https://www.parcodelconero.com/sirolo/" target="_blank" rel="noopener noreferrer">
    And the form is no longer visible
    And the form fields, when re-opened, are empty
    And the focus has returned to the "+ Aggiungi idea" button

  Scenario: Submitting with only the title creates a minimal idea
    Given the add-idea form is expanded
    When I fill in "Cinema stasera" as the title
    And I leave description and link empty
    And I submit the form
    Then the idea "Cinema stasera" appears in the list
    And the rendered idea has no description block
    And the rendered idea has no link block

  Scenario: Title with surrounding whitespace is trimmed before validation
    Given the add-idea form is expanded
    When I fill in "   " as the title and submit
    Then I see a validation error "Il titolo è obbligatorio"
    And no idea is created

  # ── Validation errors ───────────────────────────────────────────────
  Scenario: Submitting an empty title shows the validation error
    Given the add-idea form is expanded
    When I submit the form with an empty title
    Then I see a validation error "Il titolo è obbligatorio"
    And the form remains expanded
    And no idea is created

  Scenario: Submitting a title longer than 200 characters shows the validation error
    Given the add-idea form is expanded
    When I submit the form with a title of 201 characters
    Then I see a validation error mentioning the 200-character limit
    And no idea is created

  Scenario Outline: Submitting an invalid link shows the validation error
    Given the add-idea form is expanded
    When I submit the form with title "Test" and link "<value>"
    Then I see a validation error "Il link deve iniziare con http:// o https://"
    And no idea is created

    Examples:
      | value                |
      | not-a-url            |
      | ftp://example.com    |
      | javascript:alert(1)  |
      | mailto:foo@bar.com   |
      | http:/missing-slash  |

  Scenario Outline: Valid links are accepted
    Given the add-idea form is expanded
    When I submit the form with title "Test" and link "<value>"
    Then the idea is created
    And its rendered link href equals "<value>"

    Examples:
      | value                                   |
      | http://example.com                      |
      | https://example.com                     |
      | https://www.parcodelconero.com/sirolo/  |

  # ── List ordering and rendering ─────────────────────────────────────
  Scenario: Ideas are rendered newest-first
    Given the workspace already has the idea "Vecchia" inserted 2 hours ago
    When I add a new idea "Recente"
    Then "Recente" appears above "Vecchia" in the list

  Scenario: Description newlines are preserved in rendering
    Given the workspace already has an idea with description "riga 1\nriga 2"
    When I visit "/"
    Then "riga 1" and "riga 2" are rendered on separate visual lines

  Scenario: User input in description is HTML-escaped
    Given the workspace already has an idea with description "<script>alert(1)</script>"
    When I visit "/"
    Then the rendered HTML contains "&lt;script&gt;alert(1)&lt;/script&gt;"
    And the rendered HTML does not contain the literal "<script>alert(1)</script>"

  # ── Persistence (validated manually as part of V1, not in the automated suite) ──
  Scenario: Ideas survive an app restart
    Given I have created the idea "Mare a Sirolo"
    When the application is restarted
    And I revisit "/"
    Then "Mare a Sirolo" is still in the list

  # ── LiveView mount auth (defense-in-depth, closes R3 of slice 1) ────
  Scenario: LiveView mount with no session redirects to /login
    Given my browser has no session cookie for this app
    When the LiveView at "/" is mounted
    Then the mount returns a redirect to "/login?return_to=%2F"
    And no LiveView state is initialised

  Scenario: LiveView mount with tampered session is treated as no session
    Given my browser presents a session cookie that does not validate
    When the LiveView at "/" is mounted
    Then the mount returns a redirect to "/login?return_to=%2F"
```

## Architecture Specification

### Components

| Componente | Tipo | Responsabilità |
|---|---|---|
| `Ideajar.Ideas` | Context module (`lib/ideajar/ideas.ex`) | API pubblica del dominio Ideas: `list_ideas/0`, `create_idea/1`, `change_idea/2`. Wrappa `Ideajar.Repo`. Pure domain — non importa nulla da `IdeajarWeb.*`. |
| `Ideajar.Ideas.Idea` | Ecto schema (`lib/ideajar/ideas/idea.ex`) | Schema della tabella `ideas`: `title`, `description`, `url`, `inserted_at`, `updated_at`. Changeset con `validate_required([:title])`, `validate_length(:title, min: 1, max: 200)`, `validate_length(:description, max: 5000)`, `validate_length(:url, max: 2000)`, `validate_url(:url)` (helper privato che usa `URI.parse/1` + check scheme http/https + host non vuoto). Trim su `title` e `url` prima delle validazioni. |
| Migration | `priv/repo/migrations/<timestamp>_create_ideas.exs` | `CREATE TABLE ideas (id INTEGER PK, title TEXT NOT NULL, description TEXT, url TEXT, inserted_at, updated_at)` + index su `inserted_at DESC` per la list ordering. |
| `IdeajarWeb.IdeaLive.Index` | LiveView (`lib/ideajar_web/live/idea_live/index.ex` + `index.html.heex`) | Mount: check `session["authenticated"]`, carica `Ideas.list_ideas/0`, init form non visibile. Eventi: `"toggle_form"`, `"close_form"`, `"save"`. Rerender ottimistico dopo `create_idea`. |
| `IdeajarWeb.Router` | Routing | Sostituire `get "/", PageController, :home` con `live "/", IdeaLive.Index` sotto `pipe_through [:browser, :require_auth]`. Rimuovere `PageController`, `PageHTML`, `page_html/`, e relativo test (sostituiti dal LiveView). |

### Interfaces

- **Domain API** — `Ideajar.Ideas`:
  ```elixir
  @spec list_ideas() :: [Idea.t()]              # ordered by inserted_at DESC
  @spec create_idea(map()) :: {:ok, Idea.t()} | {:error, Ecto.Changeset.t()}
  @spec change_idea(Idea.t() | nil, map()) :: Ecto.Changeset.t()
  ```

- **Routes**:
  - `live "/", IdeaLive.Index` (under `:require_auth`)
  - Login routes invariate
  - `PageController.home`, `PageHTML`, e il suo template **rimossi** (il LiveView è la nuova home)

- **DB schema** (slice 2):
  ```sql
  CREATE TABLE ideas (
    id           INTEGER PRIMARY KEY,
    title        TEXT NOT NULL,
    description  TEXT,
    url          TEXT,
    inserted_at  TEXT_DATETIME NOT NULL,
    updated_at   TEXT_DATETIME NOT NULL
  );
  CREATE INDEX ideas_inserted_at_desc_idx ON ideas (inserted_at DESC);
  ```

- **LiveView assigns**:
  - `@ideas :: [Idea.t()]`
  - `@form :: Phoenix.HTML.Form.t()`
  - `@form_visible? :: boolean()`

- **LiveView events**:
  - `"toggle_form"` → `assign(socket, form_visible?: true)` + reset form
  - `"close_form"` → `assign(socket, form_visible?: false)` + reset form
  - `"save"` con params `%{"idea" => attrs}` → `Ideas.create_idea(attrs)`; on `:ok` rerender list + collapse form + `JS.focus("#add-idea-button")`; on `:error` rerender form con `@form` aggiornato

- **Mount auth**:
  ```elixir
  def mount(_params, %{"authenticated" => true}, socket), do: {:ok, base_assigns(socket)}
  def mount(_params, _session, socket), do: {:ok, redirect(socket, to: "/login?return_to=%2F")}
  ```

### Constraints

- **Validazione lato Ecto** = single source of truth; il LiveView non duplica regole.
- **Trim** su `title` e `url` prima della validazione (changeset helper).
- **HEEx auto-escape** per description e title rendering — niente `raw/1`.
- **`rel="noopener noreferrer"`** su tutti i link esterni renderizzati.
- **Nessun PubSub real-time** tra device in slice 2.
- **Nessuna paginazione** (YAGNI).
- **Domain pure** — `Ideajar.Ideas` non importa nulla da `IdeajarWeb.*`.
- **Focus management** post-submit via `Phoenix.LiveView.JS.focus/1` nativo (nessun JS hook custom).
- **No `mix phx.gen.live`** — scrittura manuale del LiveView (più snella, niente FormComponent separato per slice 2).

### Dependencies

Nessuna nuova dipendenza Hex. `Ecto.SQLite3` già configurato in slice 1.

### Out of scope

- Edit/delete idea (slice futura se servirà)
- Categorie (slice 3)
- Filtri (slice 4-7), ricerca (slice 8)
- Real-time push / Phoenix.PubSub tra device
- Paginazione, infinite scroll
- Soft-delete, audit trail, "created_by"

## Acceptance Criteria

### Functional / behavioral

- [ ] **F1** — Tutti gli scenari Gherkin **automatabili** passano come test ExUnit (`Phoenix.LiveViewTest` per il LiveView, `DataCase` per il context). Lo scenario "Ideas survive an app restart" è **manuale** in V1 (Ecto persistence è semantica garantita dal driver, non un'invariante di slice).
- [ ] **F2** — `Ideas.list_ideas/0` ritorna le idee ordinate per `inserted_at` decrescente. Verificato con due fixture a timestamp diversi.
- [ ] **F3** — `Ideas.create_idea/1` con titolo trimmato vuoto → `{:error, changeset}` con `errors[:title]` contenente "Il titolo è obbligatorio".
- [ ] **F4** — `Ideas.create_idea/1` con `url: "ftp://x"` → `{:error, changeset}` con `errors[:url]` contenente "deve iniziare con http:// o https://".
- [ ] **F5** — Form sempre collassato all'arrivo su `/`; visibile solo dopo `phx-click="toggle_form"`.
- [ ] **F6** — Trim del titolo prima della validazione: input `"   "` viene trattato come empty e produce errore `Il titolo è obbligatorio`.

### Security

- [ ] **S1** — XSS: idea con `title: "<script>"` o `description: "<img onerror>"` viene escapata in render (HEEx default). Test esplicito su una di queste.
- [ ] **S2** — `rel="noopener noreferrer"` su ogni `<a href={url} target="_blank">` renderizzato.
- [ ] **S3** — LiveView mount senza session valida → redirect a `/login?return_to=%2F`. Test esplicito.
- [ ] **S4** — URL validation rifiuta `javascript:`, `mailto:`, `data:`, `ftp:` e schemi vuoti.

### Operational / data

- [ ] **O1** — Migration `create_ideas` runnable forward e backward (`mix ecto.rollback`).
- [ ] **O2** — Index `ideas_inserted_at_desc_idx` esiste post-migration (verificato leggendo schema SQLite).

### Performance / UX

- [ ] **P1** — `Ideas.list_ideas/0` con 1000 idee fixture rende in <50ms (single SELECT con index su DESC).
- [ ] **P2** — Render LiveView iniziale per workspace con 0 idee in <100ms.
- [ ] **P3** — Submit valido → form collapse + new idea visible: render LiveView round-trip <100ms (single Ecto insert).

### Validation venue

- [ ] **V1** — Tutti gli scenari BDD validati in DevTools mobile viewport (iPhone 13 + Pixel 7); 4 screenshot: empty state, form aperto, form con errore, lista con 3 idee.
- [ ] **V1a** — Lighthouse a11y ≥95 sulla home con form aperto + 3 idee.
- [ ] **V1b** — Keyboard-only: Tab → "+ Aggiungi" → Enter → Tab attraverso titolo, descrizione, link, Salva → Enter. Funziona end-to-end.
- [ ] **V1c** — "Ideas survive an app restart" validato manualmente: creare un'idea in dev, `Ctrl+C` su `mix phx.server`, riavviare, verificare che l'idea è ancora in lista.

### Documentation / handoff

- [ ] **D1** — `docs/conventions.md` "UI copy" table aggiornata con le stringhe canoniche di slice 2 (vedi tabella sotto).
- [ ] **D2** — README.md menziona `mix ecto.migrate` nel quick start.

### UI copy aggiunta (canonical, da appendere a `docs/conventions.md`)

| Elemento | Testo IT |
|---|---|
| Bottone aggiungi idea | `+ Aggiungi idea` |
| Bottone submit form | `Salva` |
| Tooltip/aria close | `Chiudi` |
| Label campo titolo | `Titolo` |
| Label campo descrizione | `Descrizione` |
| Label campo link | `Link` |
| Errore titolo vuoto | `Il titolo è obbligatorio` |
| Errore titolo lungo | `Il titolo non può superare i 200 caratteri` |
| Errore link invalido | `Il link deve iniziare con http:// o https://` |
| Empty state | `Nessuna idea ancora. Aggiungine una qui sopra.` |

## Consistency Gate

- [x] Intent is unambiguous
- [x] Every behavior has a corresponding BDD scenario
- [x] Architecture constrains without over-engineering
- [x] Terminology consistent across artifacts
- [x] No contradictions between artifacts

**Verdict: PASS** — ready for `/plan`.
