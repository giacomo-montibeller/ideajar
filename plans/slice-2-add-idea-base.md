# Plan: Slice 2 — Add a base idea (title + description + link)

**Created**: 2026-04-27
**Branch**: main (trunk-based)
**Status**: approved
**Spec**: `docs/specs/add-idea-base.md`

## Build conventions (carried from slice 1)

- **Strict TDD** — RED → GREEN → REFACTOR per step.
- **Every commit** through the `commit-message` skill.
- Pre-step gate locale: `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo`, `mix deps.audit`, `mix test`. Same gates run in CI on every push.
- Domain in `Ideajar.*`, delivery in `IdeajarWeb.*`.
- UI copy in italiano; nuove stringhe vanno appese alla tabella canonica in `docs/conventions.md` nel commit che le introduce.

## Goal

Sostituire la home placeholder di slice 1 con una **LiveView** che mostra la lista idee della coppia, con un bottone `+ Aggiungi idea` che espande un form (titolo, descrizione, link) per la creazione. Form collassato di default, validazione on-submit via Ecto changeset, idee persistite su SQLite ordinate per `inserted_at` decrescente. Fuori scope: filtri, categorie, modifica/cancellazione, real-time. Chiude inoltre il warning R3 di slice 1 (LiveView mount auth defense-in-depth).

## Decisioni architetturali pre-build (chiuse iter 2)

Queste decisioni sono fissate qui e Step 4-7 le applicano meccanicamente. Il piano non lascia "or equivalent" su scelte strutturali.

- **A1 — Schema vs migration types**: migration usa `add :description, :text` e `add :url, :text` (SQLite TEXT senza cap DB-side); schema dichiara `field :description, :string` e `field :url, :string` con commento esplicito sul mapping; cap di lunghezza solo a livello changeset.
- **A2 — Description length cap**: **rimosso**. Threat model = 2 utenti fidati; cap 5000 era defensive-coding inertia. `description` resta opzionale, free-text, senza vincoli di lunghezza nell'app. Test e UI copy aggiornati di conseguenza.
- **A3 — `change_idea/2` nel context**: **non esposto**. La LiveView chiama `Ideajar.Ideas.Idea.changeset(%Idea{}, %{})` direttamente (la LV è dentro `IdeajarWeb.*` ma può conoscere lo schema; il context espone solo le operazioni che fanno I/O o aggregano regole di business).
- **A4 — `phx-change` sul form**: **non usato**. LiveView preserva il valore degli input non legati a un handler server; l'on-submit è l'unica validazione runtime. Niente handler `validate` no-op.
- **A5 — Focus management post-submit**: **`push_event("ideajar:focus", %{to: "..."})` dal server + listener in `assets/js/app.js`** — pattern testabile (assert su push_event nel reducer) e disaccoppiato dal DOM. Niente `phx-mounted` su elementi conditionally-rendered.
- **A6 — Focus management su autofocus title quando form si apre**: idem A5 — push_event al `toggle_form` handler. La proprietà HTML `autofocus` è inadeguata per LV re-render (UX blocker iter 1).
- **A7 — Error rendering**: **CoreComponents `<.input field={@form[:title]} label="Titolo" />`** che il scaffold Phoenix 1.8 fornisce. Errore reso inline accanto all'input via `<.error>` interno con `aria-invalid`/`aria-describedby` automatici. Niente `<ul>` flat di errori. Per l'accumulo (multi-error submit), CoreComponents gestisce nativamente.
- **A8 — Submit button**: `phx-disable-with="Salvataggio…"` non opzionale (UX blocker iter 1: doppi-tap su mobile creano duplicati).
- **A9 — Close button**: `<button type="button" aria-label="Chiudi" phx-click="close_form">✕</button>` — `type="button"` esplicito (UX blocker iter 1: dentro un form il default è `type="submit"`).
- **A10 — Success confirmation**: `put_flash(:info, "Idea aggiunta")` (Phoenix scaffold ha già `flash_group` in layout root). Screen reader friendly via `aria-live` del flash component.
- **A11 — Link rendering**: `<a href={url} target="_blank" rel="noopener noreferrer" aria-label="Apri link in una nuova scheda" class="break-all">{display_text}</a>`. `class="break-all"` previene overflow su mobile per URL lunghi. `aria-label` annuncia il cambio di context (WCAG 3.2.5).
- **A12 — Close button hit area + flash live-region**: il `✕` button ha minimo `44×44 CSS px` di hit area (WCAG 2.5.5) e classi visive che lo distinguono dal `Salva` (es. `text-base-content/60` vs primario per Salva). Phoenix scaffold flash component ha `role="alert"` per errori e `aria-live="polite"` per info — asserito esplicitamente nei test di Step 6 (success flash) e Step 9 (error flash) per evitare regressioni silenti su future modifiche del template.

## Acceptance Criteria

> Mappatura uno-a-uno con `docs/specs/add-idea-base.md`. Le AC P2/P3 originali sono **rimosse** (design budget non binary-verifiable per acceptance acceptance review iter 1); P1 è **rimossa** (YAGNI per 2-user app per strategic review iter 1). Aggiunte F7, S5, S6, S7.

### Functional / behavioral
- [ ] **F1** — Tutti gli scenari Gherkin **automatabili** passano come test ExUnit (LV via `Phoenix.LiveViewTest`, domain via `DataCase`). Lo scenario "Ideas survive an app restart" è manuale in V1c. Lo scenario "focus has returned to '+ Aggiungi idea'" è automatabile come "il server emette `push_event` con target corretto"; il fatto che il browser focusi è in V1b manuale.
- [ ] **F2** — `Ideas.list_ideas/0` ritorna idee ordinate per `inserted_at` decrescente, con tie-break su `id` decrescente.
- [ ] **F3** — `Ideas.create_idea/1` con titolo trimmato vuoto → `{:error, changeset}` con `errors[:title]` esattamente `Il titolo è obbligatorio` (stringa canonica).
- [ ] **F4** — `Ideas.create_idea/1` con `url: "ftp://x"` → `{:error, changeset}` con `errors[:url]` esattamente `Il link deve iniziare con http:// o https://`.
- [ ] **F5** — Form sempre collassato all'arrivo su `/`; visibile solo dopo `phx-click="toggle_form"`.
- [ ] **F6** — Trim del titolo prima della validazione: `"   "` → vuoto → errore `Il titolo è obbligatorio`.
- [ ] **F7** — Click su `✕` durante data entry: form collassa, riaperture mostra campi vuoti (no draft persistence in slice 2; trade-off accettato).

### Security
- [ ] **S1** — XSS: `title` e `description` sempre escapate in render. Test esplicito su `<script>alert(1)</script>` in description.
- [ ] **S2** — `rel="noopener noreferrer"` + `target="_blank"` + `aria-label="Apri link in una nuova scheda"` su ogni `<a>` di idea.
- [ ] **S3** — LiveView mount senza session valida → redirect a `/login?return_to=%2F`. Test esplicito.
- [ ] **S4** — URL validation rifiuta esplicitamente: `not-a-url`, `ftp://example.com`, `javascript:alert(1)`, `mailto:foo@bar.com`, `http:/missing-slash`, `data:text/html,<script>alert(1)</script>`, `://example.com`, `https://` (host vuoto), `   ` (whitespace only — trim → empty → valid because optional).
- [ ] **S5** — URL scheme è case-insensitive in fase di **validazione** (`HTTPS://example.com`, `Http://example.com` accettati). Il valore è persistito e renderizzato **verbatim**: nessuna normalizzazione lower-case. Il check usa `String.downcase(scheme) in ["http", "https"]` solo per la decisione di accept/reject.
- [ ] **S6** — DB write failure (es. `Repo.insert/1` ritorna `{:error, %Ecto.Changeset{}}` con cause non-validation, oppure raise): la LV non crasha; mostra flash di errore generico "Salvataggio non riuscito, riprova" e mantiene il form aperto con il contenuto. Test via stub.
- [ ] **S7** — Il bottone Salva ha attr `phx-disable-with="Salvataggio…"` per prevenire double-click client-side. **Server-side idempotency è esplicitamente fuori scope** (vedi R8): un attaccante via curl può POST due volte. Per slice 2 (2-user app fidata) il client-side guard è sufficiente.

### Operational / data
- [ ] **O1** — Migration `create_ideas` runnable forward e backward. **Test automatizzato**: `mix ecto.migrate` → schema attesa; `mix ecto.rollback --step 1` → tabella `ideas` non esiste; nuovo `mix ecto.migrate` → re-creata.
- [ ] **O2** — Index `ideas_inserted_at_desc_idx` esiste post-migration (verificato leggendo schema SQLite via `Ecto.Adapters.SQL.query!`).

### Validation venue
- [ ] **V1** — 4 screenshot mobile-viewport (iPhone 13 + Pixel 7): empty state, form aperto, form con errore, lista con 3 idee. Allegati come file in `docs/screenshots/slice-2/`.
- [ ] **V1a** — Lighthouse a11y ≥95 sulla home con form aperto + 3 idee, profilo Mobile (default DevTools, simulated 4G), categoria accessibility, single run dopo hard reload. Output JSON allegato.
- [ ] **V1b** — Keyboard-only walkthrough esplicito (verifica tutti e 3 i target di `push_event("ideajar:focus")`):
  1. Tab sulla pagina → focus su `+ Aggiungi idea`
  2. Enter → form si apre; **verifica focus su `#idea-title`** (target 1: toggle_form)
  3. Tab → `Descrizione` → Tab → `Link` → Tab → `Salva`
  4. Submit con title vuoto (es. immediatamente Enter dopo aver eliminato testo) → form resta aperto; **verifica focus jump su `#idea-title`** (target 2: focus_first_invalid)
  5. Fix title valido, Enter su `Salva` → form collassa, idea visibile, flash "Idea aggiunta"; **verifica focus su `#add-idea-button`** (target 3: post-save)
  6. Tab dopo save success → focus si muove deterministicamente al successivo elemento focusabile della pagina (link nella prima idea card se presente, altrimenti elemento successivo nel tab order); **verificare assenza di focus trap**
- [ ] **V1c** — Persistence survival: `mix phx.server` → crea idea via UI → `Ctrl+C` → riavvia → idea ancora in lista.

### Documentation
- [ ] **D1** — `docs/conventions.md` "UI copy" table aggiornata con stringhe canoniche di slice 2 (vedi tabella sotto).
- [ ] **D2** — README.md menziona `mix ecto.migrate` nel quick start.

### UI copy aggiunta (canonical)

| Elemento | Testo IT |
|---|---|
| Bottone aggiungi idea | `+ Aggiungi idea` |
| Bottone submit form | `Salva` |
| Submit pending (phx-disable-with) | `Salvataggio…` |
| Aria close icon | `Chiudi` |
| Label campo titolo | `Titolo` |
| Label campo descrizione | `Descrizione` |
| Label campo link | `Link` |
| Errore titolo vuoto | `Il titolo è obbligatorio` |
| Errore titolo lungo | `Il titolo non può superare i 200 caratteri` |
| Errore link invalido | `Il link deve iniziare con http:// o https://` |
| Errore link lungo | `Il link non può superare i 2000 caratteri` |
| Aria link external | `Apri link in una nuova scheda` |
| Empty state | `Nessuna idea ancora. Aggiungine una qui sopra.` |
| Flash success | `Idea aggiunta` |
| Flash DB error | `Salvataggio non riuscito, riprova` |

## User-Facing Behavior

> Verbatim da `docs/specs/add-idea-base.md` con le seguenti **revisioni iter 2**:
> - "the add-idea form is not visible in the rendered DOM" → "the add-idea form is **not present in the rendered HTML**" (eliminata ambiguità DOM-vs-CSS-hidden; il form è rendered conditionally in HEEx, quindi assente del tutto)
> - "the title input has autofocus" → "the title input receives focus when the form opens" (autofocus HTML attr non funziona in LV re-render; verifica via push_event server-side + V1b manual)
> - "no LiveView state is initialised" rimosso (implementation leak)
> - Aggiunti scenari boundary (title 200, url 2000), tie-break, double-click, DB-failure, mixed-case scheme

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
    Then the add-idea form is not present in the rendered HTML
    And the "+ Aggiungi idea" button is enabled

  Scenario: Clicking the add button expands the form and focuses the title input
    Given I am on "/"
    When I click "+ Aggiungi idea"
    Then the add-idea form becomes visible
    And the server emits a "ideajar:focus" event targeting "#idea-title"
    And I see a "Salva" button with phx-disable-with "Salvataggio…"
    And I see a "✕" close button with type="button" and aria-label "Chiudi"

  Scenario: Clicking the close icon collapses the form without saving
    Given the add-idea form is expanded
    And I have typed "Mare a Sirolo" into the title field
    When I click the "✕" close icon
    Then the form is no longer visible
    And the workspace still has no ideas

  Scenario: Reopening the form after close shows empty fields (F7)
    Given the add-idea form is expanded
    And I have typed "Mare a Sirolo" into the title field
    When I click the "✕" close icon
    And I click "+ Aggiungi idea"
    Then the title field is empty
    And the description field is empty
    And the link field is empty

  # ── Successful creation ─────────────────────────────────────────────
  Scenario: Submitting valid input creates the idea, collapses the form, returns focus, and shows a success flash
    Given the add-idea form is expanded
    When I fill in "Mare a Sirolo" as the title
    And I fill in "Spiaggia delle due Sorelle, partenza presto" as the description
    And I fill in "https://www.parcodelconero.com/sirolo/" as the link
    And I submit the form
    Then the idea "Mare a Sirolo" appears at the top of the list
    And I see its description "Spiaggia delle due Sorelle, partenza presto"
    And I see its link rendered as <a href="https://www.parcodelconero.com/sirolo/" target="_blank" rel="noopener noreferrer" aria-label="Apri link in una nuova scheda">
    And the form is no longer visible
    And the server emits a "ideajar:focus" event targeting "#add-idea-button"
    And a flash "Idea aggiunta" is shown

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
    Then I see a validation error "Il titolo è obbligatorio" associated with the title input via aria-describedby
    And the title input has aria-invalid="true"
    And no idea is created

  Scenario: Title at exactly 200 characters is accepted (boundary)
    Given the add-idea form is expanded
    When I submit the form with a title of exactly 200 characters
    Then the idea is created

  Scenario: URL at exactly 2000 characters with valid scheme is accepted (boundary)
    Given the add-idea form is expanded
    When I submit the form with a 2000-character https URL
    Then the idea is created

  # ── Validation errors ───────────────────────────────────────────────
  Scenario: Submitting an empty title shows the validation error inline
    Given the add-idea form is expanded
    When I submit the form with an empty title
    Then I see "Il titolo è obbligatorio" as an error associated with the title input
    And the title input has aria-invalid="true"
    And the form remains expanded
    And the server emits a "ideajar:focus" event targeting "#idea-title"
    And no idea is created

  Scenario: Submitting a title longer than 200 characters shows the validation error
    Given the add-idea form is expanded
    When I submit the form with a title of 201 characters
    Then I see "Il titolo non può superare i 200 caratteri" associated with the title input
    And no idea is created

  Scenario Outline: Submitting an invalid link shows the validation error
    Given the add-idea form is expanded
    When I submit the form with title "Test" and link "<value>"
    Then I see "Il link deve iniziare con http:// o https://" associated with the link input
    And no idea is created

    Examples:
      | value                                       |
      | not-a-url                                   |
      | ftp://example.com                           |
      | javascript:alert(1)                         |
      | mailto:foo@bar.com                          |
      | http:/missing-slash                         |
      | data:text/html,<script>alert(1)</script>    |
      | https://                                    |
      | ://example.com                              |

  Scenario Outline: Valid links are accepted and case-insensitive in scheme (S5)
    Given the add-idea form is expanded
    When I submit the form with title "Test" and link "<value>"
    Then the idea is created
    And its rendered link href equals "<href>"

    Examples:
      | value                  | href                   |
      | http://example.com     | http://example.com     |
      | https://example.com    | https://example.com    |
      | HTTPS://example.com    | HTTPS://example.com    |
      | Http://Example.com     | Http://Example.com     |

  Scenario: Submitting with both invalid title and invalid url shows both errors
    Given the add-idea form is expanded
    When I submit the form with empty title and link "ftp://x"
    Then I see "Il titolo è obbligatorio" near the title input
    And I see "Il link deve iniziare con http:// o https://" near the link input
    And no idea is created

  Scenario: A whitespace-only URL (after trim, empty) is accepted because url is optional
    Given the add-idea form is expanded
    When I submit the form with title "Test" and link "   "
    Then the idea is created
    And the rendered idea has no link block

  # ── Concurrency / double-click protection ───────────────────────────
  Scenario: The Salva button is disabled during submission (phx-disable-with)
    Given the add-idea form is expanded with valid input
    When the form is being submitted
    Then the Salva button has the phx-disable-with attribute equal to "Salvataggio…"
    And tapping it again before the response would be ignored client-side

  # ── List ordering and rendering ─────────────────────────────────────
  Scenario: Ideas are rendered newest-first
    Given the workspace already has the idea "Vecchia" with inserted_at 2 hours before "Recente"
    When I add a new idea "Recente"
    Then "Recente" appears above "Vecchia" in the rendered HTML

  Scenario: Tie-break — equal inserted_at, higher id first
    Given two ideas with `inserted_at = 2026-04-27T10:00:00Z`, ids 1 ("First") and 2 ("Second")
    When I visit "/"
    Then "Second" appears above "First" in the rendered HTML

  Scenario: Description newlines are preserved via CSS
    Given the workspace already has an idea whose description is the two lines `riga 1` and `riga 2` joined by a single LF (
)
    When I visit "/"
    Then the description element has CSS class "whitespace-pre-wrap"
    And the rendered HTML contains both "riga 1" and "riga 2" separated by the same LF character

  Scenario: User input in description is HTML-escaped
    Given the workspace already has an idea with description "<script>alert(1)</script>"
    When I visit "/"
    Then the rendered HTML contains "&lt;script&gt;alert(1)&lt;/script&gt;"
    And the rendered HTML does not contain the literal "<script>alert(1)</script>"

  # ── DB error handling (S6) ──────────────────────────────────────────
  Scenario: Repo write failure surfaces a generic flash without crashing
    Given the add-idea form is expanded with valid input
    And the persistence layer will fail with an unexpected error
    When I submit the form
    Then I see a flash "Salvataggio non riuscito, riprova" with role="alert"
    And the form remains expanded with my input preserved
    And the LiveView process did not crash

  # ── Persistence (manual, V1c) ───────────────────────────────────────
  Scenario: Ideas survive an app restart
    Given I have created the idea "Mare a Sirolo"
    When the application is restarted
    And I revisit "/"
    Then "Mare a Sirolo" is still in the list

  # ── LiveView mount auth (defense-in-depth) ──────────────────────────
  Scenario: LiveView mount with no session redirects to /login
    Given my browser has no session cookie for this app
    When I visit "/"
    Then I am redirected to "/login?return_to=%2F"

  Scenario: LiveView mount with tampered session is treated as no session
    Given my browser presents a session cookie that does not validate
    When I visit "/"
    Then I am redirected to "/login?return_to=%2F"
```

## Steps

### Step 1: Migration + Idea schema (skeleton, with rollback test)

**Complexity**: standard
**RED**:
1. `test/ideajar/ideas/idea_test.exs`: insert `%Idea{title: "Mare", description: "x", url: "https://example.com"}` via `Repo.insert/1` ritorna `{:ok, %Idea{id: id}}` con id non-nil + timestamps utc.
2. `assert_raise Ecto.ConstraintError, ~r/NOT NULL/, fn -> Repo.insert(%Idea{title: nil}) end`.
3. Schema verifica: `Idea.__schema__(:fields)` contiene `[:id, :title, :description, :url, :inserted_at, :updated_at]`.
4. **Migration round-trip test** in `test/ideajar/ideas/migration_test.exs` (`async: false`, tagged `:migration`): query SQLite per nome tabella prima del migrate (assente) → `Ecto.Migrator.up/4` con la specifica migration → query (presente) → `Ecto.Migrator.down/4` → query (assente) → re-up (presente). Verifica inoltre presenza dell'index `ideas_inserted_at_desc_idx` post-up.
**GREEN**:
- `mix ecto.gen.migration create_ideas` → modificare migration con `create table(:ideas) do add :title, :string, null: false; add :description, :text; add :url, :text; timestamps(type: :utc_datetime) end` + `create index(:ideas, [:inserted_at], name: :ideas_inserted_at_desc_idx)`. (A1: migration usa `:text`, schema usa `:string`).
- `lib/ideajar/ideas/idea.ex`: `schema "ideas" do field :title, :string; field :description, :string; field :url, :string; timestamps(type: :utc_datetime) end`. Commento su A1 (mapping `:string` Ecto → `TEXT` SQLite).
- Niente changeset/validazioni in questo step.
**REFACTOR**: nessuno significativo.
**Files**: `priv/repo/migrations/<ts>_create_ideas.exs`, `lib/ideajar/ideas/idea.ex`, `test/ideajar/ideas/idea_test.exs`, `test/ideajar/ideas/migration_test.exs`.
**Spec mapping**: O1, O2.

### Step 2: Idea changeset with validations (full security boundary)

**Complexity**: complex (security boundary, single source of truth per validation)
**RED** (`test/ideajar/ideas/idea_test.exs` estensione, tutti i test usano stringhe **canoniche** dalla UI copy table):
1. `Idea.changeset(%Idea{}, %{title: "Mare"})` → valid.
2. `changeset(%{title: ""})` → invalid, `errors[:title]` esattamente `{"Il titolo è obbligatorio", _}`.
3. `changeset(%{title: "   "})` → invalid (trim), stesso errore.
4. `changeset(%{title: String.duplicate("a", 201)})` → invalid, errore esattamente `Il titolo non può superare i 200 caratteri`.
5. `changeset(%{title: String.duplicate("a", 200)})` → valid (boundary).
6. `changeset(%{title: "x", description: String.duplicate("d", 100_000)})` → valid (A2: nessun cap su description).
7. `changeset(%{title: "x", url: ""})` → valid.
8. `changeset(%{title: "x", url: "   "})` → valid (trim → empty → optional).
9. `changeset(%{title: "x", url: "  https://example.com  "})` → valid, `get_change/2` sull'url ritorna `"https://example.com"` (trimmed).
10. `changeset(%{title: "x", url: String.duplicate("h", 2001)})` → invalid, errore esattamente `Il link non può superare i 2000 caratteri`.
11. `changeset(%{title: "x", url: "https://" <> String.duplicate("a", 1992)})` → valid (boundary 2000).
12. **Scenario Outline invalid links**: per ogni valore in `["not-a-url", "ftp://example.com", "javascript:alert(1)", "mailto:foo@bar.com", "http:/missing-slash", "data:text/html,<script>alert(1)</script>", "https://", "://example.com"]` → invalid con errore esatto `Il link deve iniziare con http:// o https://`.
13. **Scenario Outline valid links case-insensitive**: per ogni valore in `["http://example.com", "https://example.com", "HTTPS://example.com", "Http://Example.com"]` → valid.
14. `changeset(%{title: "", url: "ftp://x"})` → invalid con errori su **entrambi** `:title` e `:url` (no short-circuit).
**GREEN**:
- `Idea.changeset/2`: `cast([:title, :description, :url])` + private `trim_text/2` su `:title` e `:url` + `validate_required([:title], message: "Il titolo è obbligatorio")` + `validate_length(:title, max: 200, message: "Il titolo non può superare i 200 caratteri")` + `validate_length(:url, max: 2000, message: "Il link non può superare i 2000 caratteri")` + `validate_url/1` helper.
- `validate_url/1`: per nil/empty → ok; altrimenti `URI.parse/1` + `String.downcase(scheme)` accettato in `["http", "https"]` + `host` non in `[nil, ""]`. Errore esatto `Il link deve iniziare con http:// o https://`.
**REFACTOR**: estrarre `trim_text/2` come helper privato in modulo; commenti di intent.
**Files**: `lib/ideajar/ideas/idea.ex` (estensione), `test/ideajar/ideas/idea_test.exs` (estensione).
**Spec mapping**: F3, F4, F6, S4, S5; tutti gli scenari validation + boundary + mixed-error.

### Step 3: Ideajar.Ideas context (list + create only)

**Complexity**: standard
**RED** (`test/ideajar/ideas_test.exs`):
1. `Ideas.list_ideas/0` su DB vuoto → `[]`.
2. Inserisci 2 idee con timestamps diversi → `list_ideas/0` ritorna in ordine `inserted_at DESC`.
3. **Tie-break**: inserisci 2 idee con stesso `inserted_at` (force via `Repo.insert/1` con :utc_datetime esplicito identico) → `list_ideas/0` ritorna prima quella con `id` maggiore.
4. `Ideas.create_idea(%{title: "Mare"})` → `{:ok, %Idea{}}` e l'idea è in `list_ideas/0`.
5. `Ideas.create_idea(%{title: ""})` → `{:error, %Ecto.Changeset{}}` con errore esatto `Il titolo è obbligatorio`.
**GREEN**:
- `lib/ideajar/ideas.ex`: `list_ideas/0` con `from i in Idea, order_by: [desc: i.inserted_at, desc: i.id]`; `create_idea/1` chiama `Idea.changeset/2` + `Repo.insert/1`. **Niente `change_idea/2`** (A3).
**REFACTOR**: docstring + `@spec`.
**Files**: `lib/ideajar/ideas.ex`, `test/ideajar/ideas_test.exs`.
**Spec mapping**: F2, F3, F4, scenari ordering + tie-break.

### Step 4: IdeaLive.Index — empty state + mount auth (live_isolated, no route yet)

**Complexity**: complex (security boundary defense-in-depth)
**RED** (`test/ideajar_web/live/idea_live/index_test.exs` usando `Phoenix.LiveViewTest.live_isolated/3` — niente route ancora):
1. `live_isolated(conn, IdeajarWeb.IdeaLive.Index, session: %{"authenticated" => true})` → `{:ok, view, html}` con html contenente "+ Aggiungi idea", `id="add-idea-button"`, empty state "Nessuna idea ancora. Aggiungine una qui sopra.", e nessun `<form>`.
2. `live_isolated(conn, IdeajarWeb.IdeaLive.Index, session: %{})` → `{:error, {:redirect, %{to: "/login?return_to=%2F"}}}`.
3. `live_isolated(conn, IdeajarWeb.IdeaLive.Index, session: %{"authenticated" => false})` → idem redirect.
4. `live_isolated(...)` con sessione valida ma DB vuoto → `view.assigns.ideas == []` e `view.assigns.form_visible? == false`.
**GREEN**:
- `lib/ideajar_web/live/idea_live/index.ex`: `mount(_, %{"authenticated" => true}, socket)` → `assign(socket, ideas: Ideas.list_ideas(), form_visible?: false, form: empty_form())`; `mount(_, _, socket)` → `{:ok, redirect(socket, to: "/login?return_to=%2F")}`. `empty_form/0` chiama `Idea.changeset(%Idea{}, %{}) |> to_form()` (A3 — direttamente nel LV).
- `lib/ideajar_web/live/idea_live/index.html.heex`: `<button id="add-idea-button" phx-click="toggle_form">+ Aggiungi idea</button>` + `<%= if Enum.empty?(@ideas) do %>...empty state...<% end %>`.
- **Niente route changes in questo step**: il LiveView esiste come modulo ma `/` continua a servire `PageController.home`. La route swap è Step 8.
**REFACTOR**: estrarre helper `redirect_to_login/1` privato.
**Files**: `lib/ideajar_web/live/idea_live/index.ex`, `lib/ideajar_web/live/idea_live/index.html.heex`, `test/ideajar_web/live/idea_live/index_test.exs`.
**Spec mapping**: empty state, mount auth (no session, tampered) — S3, F5.

### Step 5: Form expand / collapse + focus management (push_event + JS hook)

**Complexity**: complex (cross-layer: server push_event + JS listener + UX a11y)
**RED** (estensione `idea_live/index_test.exs`, sempre `live_isolated`):
1. `view |> render_click("toggle_form")` → form visibile, contiene `<input id="idea-title" name="idea[title]" required>`, `<input name="idea[description]">`, `<input name="idea[url]">`, label per ognuno (CoreComponents `<.input label="Titolo">`), `<button type="submit" phx-disable-with="Salvataggio…">Salva</button>`, `<button type="button" aria-label="Chiudi" phx-click="close_form">✕</button>`.
2. Dopo `toggle_form` → `assert_push_event(view, "ideajar:focus", %{to: "#idea-title"})` (A6).
3. `render_click("close_form")` → form non visibile, `view.assigns.form_visible? == false`, `view.assigns.ideas` invariato.
4. F7 — open form, scrivi "Mare" via `render_change` → close → re-open → `view |> form("#idea-form") |> render() |> Floki.find("input[name='idea[title]']") |> Floki.attribute("value")` ritorna `[]` (vuoto, non `["Mare"]`).
5. `render_click("toggle_form")` due volte di seguito senza close → secondo click è no-op (idempotent: form_visible? resta true, form non resettato).
**GREEN**:
- `handle_event("toggle_form", _, %{assigns: %{form_visible?: false}} = socket)` → `assign(socket, form_visible?: true) |> reset_form() |> push_event("ideajar:focus", %{to: "#idea-title"})`.
- `handle_event("toggle_form", _, %{assigns: %{form_visible?: true}} = socket)` → no-op (idempotent).
- `handle_event("close_form", _, socket)` → `assign(socket, form_visible?: false) |> reset_form()`.
- `reset_form/1` privato: `assign(socket, form: empty_form())`.
- `assets/js/app.js`: aggiungere `window.addEventListener("phx:ideajar:focus", e => document.querySelector(e.detail.to)?.focus())` (A5).
- Template usa CoreComponents `<.input field={@form[:title]} label="Titolo" id="idea-title" required>` etc. (A7).
**REFACTOR**: nessuno significativo.
**Files**: `lib/ideajar_web/live/idea_live/index.ex`, `lib/ideajar_web/live/idea_live/index.html.heex`, `assets/js/app.js`, test.
**Spec mapping**: form expansion/collapse scenarios, F5, F7, A6, A7, A8, A9.

### Step 6: Successful submit (full happy path including rendering edges)

**Complexity**: complex (security boundary su URL render + flash + push_event focus + double-click guard)
**RED** (estensione `idea_live/index_test.exs`):
1. Open form, fill title=Mare, description="r1\nr2", url="https://example.com/sirolo", submit → idea in lista al primo posto, html rendered contiene `<a href="https://example.com/sirolo" target="_blank" rel="noopener noreferrer" aria-label="Apri link in una nuova scheda">`. Description element ha `class="whitespace-pre-wrap"` e contiene "r1\nr2".
2. Form non più visibile, `view.assigns.form_visible? == false`.
3. `assert_push_event(view, "ideajar:focus", %{to: "#add-idea-button"})` (A5).
4. Flash component contiene "Idea aggiunta" (A10).
5. Re-open form → campi vuoti.
6. Submit con solo title → idea in lista, no `<a>`, no description block.
7. Per ogni URL valido in `["http://example.com", "https://example.com", "HTTPS://example.com", "Http://Example.com"]` (S5) → idea creata con href esattamente uguale all'input.
8. **Boundary**: title 200 char esatti → idea creata; url 2000 char esatti (con prefisso https://) → idea creata.
9. **XSS**: idea con description `"<script>alert(1)</script>"` → render contiene `&lt;script&gt;alert(1)&lt;/script&gt;`, **non** contiene la stringa literal.
10. **Ordering**: insert "Vecchia" con inserted_at 2h fa, poi "Recente" con now → "Recente" appare prima di "Vecchia" nel DOM (verifica con Floki).
11. **Tie-break**: 2 idee stesso inserted_at, id 1 e 2 → id=2 prima nel DOM.
12. **S7** — Salva button ha attr `phx-disable-with="Salvataggio…"`.
13. **S2/A11** — link rendered contiene tutte le 4 attribute (target, rel, aria-label, class break-all).
**GREEN**:
- `handle_event("save", %{"idea" => attrs}, socket)`:
  - `case Ideas.create_idea(attrs)`:
    - `{:ok, _}` → `socket |> assign(ideas: Ideas.list_ideas(), form_visible?: false) |> reset_form() |> put_flash(:info, "Idea aggiunta") |> push_event("ideajar:focus", %{to: "#add-idea-button"})`.
    - `{:error, changeset}` → `assign(socket, form: to_form(changeset, action: :insert)) |> push_event("ideajar:focus", %{to: focus_first_invalid(changeset)})`. (Step 7 chiude la parte error rendering.)
- Template lista: function component `<.idea_card idea={idea} />` in modulo `IdeajarWeb.Components.IdeaCard` o inline. Contiene title, description (con `class="whitespace-pre-wrap"`, conditional su nil/empty), link (conditional su nil/empty, con tutti gli attr di A11).
- `focus_first_invalid/1` ritorna `"#idea-title"` se title ha errore, sennò `"#idea-url"`, sennò `"#idea-description"`.
**REFACTOR**: estrarre `<.idea_card>` come function component se utile per leggibilità del template.
**Files**: `lib/ideajar_web/live/idea_live/index.ex`, `lib/ideajar_web/live/idea_live/index.html.heex`, eventualmente `lib/ideajar_web/components/idea_card.ex`, test.
**Spec mapping**: successful creation scenarios, ordering, tie-break, XSS, newlines preserved, S1, S2, S5, S7, A5, A10, A11.

### Step 7: Validation errors with CoreComponents inline rendering

**Complexity**: standard
**RED** (estensione `idea_live/index_test.exs`):
1. Open form, submit con title vuoto → render contiene errore "Il titolo è obbligatorio" associato all'input title. Verifica:
   - `<input id="idea-title">` ha attr `aria-invalid="true"`
   - `<input>` ha attr `aria-describedby="idea-title-error"` (o equivalente del CoreComponents)
   - elemento con id `idea-title-error` (o equivalente) contiene il testo errore
   - form ancora visibile
   - `assert_push_event(view, "ideajar:focus", %{to: "#idea-title"})` (focus on first invalid).
2. Submit con title `"   "` → stesso errore, F6.
3. Submit con title 201 char → errore "Il titolo non può superare i 200 caratteri" su input title.
4. Submit con title vuoto + url ftp → entrambi gli errori associati ai rispettivi input; focus su `#idea-title` (primo invalid in ordine).
5. Submit con title valido + url ftp → errore "Il link deve iniziare con http:// o https://" associato a input url; focus su `#idea-url`.
6. Submit con title valido + url 2001 char → errore "Il link non può superare i 2000 caratteri".
7. Submit con whitespace-only url + title valido → idea creata (url trim → empty → optional → valid).
**GREEN**:
- Template: usare `<.input field={@form[:title]} label="Titolo" id="idea-title" required>`, `<.input field={@form[:description]} label="Descrizione" id="idea-description" type="textarea">`, `<.input field={@form[:url]} label="Link" id="idea-url" type="url">`. CoreComponents render automaticamente `<.error>` con aria attributes (A7).
- Niente flat error list. Niente `<ul role="alert">`.
- `focus_first_invalid/1` già implementata in Step 6.
**REFACTOR**: nessuno (CoreComponents fornisce la struttura).
**Files**: `lib/ideajar_web/live/idea_live/index.html.heex`, test.
**Spec mapping**: validation errors scenarios + boundary, F3, F4, F6, S4, A7.

### Step 8: Wire route + remove PageController + migrate slice-1 cross-cutting tests

**Complexity**: complex (routing change + file deletion + test migration)
**RED**:
1. **Test ConnCase di routing** (`test/ideajar_web/router_test.exs`): GET `/` per route info ritorna LiveView `IdeajarWeb.IdeaLive.Index`, non `PageController`.
2. **Migrate slice-1 tests** — i 4 test attualmente in `test/ideajar_web/controllers/page_controller_test.exs` da preservare come slice-1 invariant regression:
   - `"redirects to /login with return_to=/"` (no session) — sposta in `test/ideajar_web/live/idea_live/index_test.exs` come `live(conn, "/")` test.
   - `"renders the workspace home"` (authenticated) — sposta nel LV test, asserisce render contiene "+ Aggiungi idea" (è la nuova home placeholder-equivalent).
   - `"a second device is a separate authentication"` — generalizza in `test/ideajar_web/auth_boundary_test.exs` come test sul plug `:require_auth` slegato dalla home specifica (test che 2 conn distinti con stato sessione diverso → comportamento diverso).
   - `"after successful login the cookie carries authentication"` — idem, test slegato dalla home; resta in `auth_boundary_test.exs`.
3. ConnCase test che POST a `/` senza session → 403 dal plug `:require_auth` (already covered, regressione).
**GREEN**:
- Router: rimuovere `get "/", PageController, :home`, aggiungere `live "/", IdeajarWeb.IdeaLive.Index` sotto `pipe_through [:browser, :require_auth]`.
- Eliminare `lib/ideajar_web/controllers/page_controller.ex`, `lib/ideajar_web/controllers/page_html.ex`, `lib/ideajar_web/controllers/page_html/home.html.heex`.
- Eliminare `test/ideajar_web/controllers/page_controller_test.exs` dopo aver migrato i 4 test.
- Creare `test/ideajar_web/auth_boundary_test.exs` con i 2 test plug-level estratti.
**REFACTOR**: nessuno (è uno step di routing + cleanup).
**Files**: `lib/ideajar_web/router.ex`, eliminati 3 file PageController-related, `test/ideajar_web/live/idea_live/index_test.exs` (estensione), nuovo `test/ideajar_web/auth_boundary_test.exs`, eliminato `test/ideajar_web/controllers/page_controller_test.exs`.
**Spec mapping**: integration end-to-end della LV su `/`. Conferma scenari "First visit shows the helpful prompt" e "LiveView mount with no/tampered session" come test routed.

### Step 9: Repo failure resilience + Documentation + spec sync

**Complexity**: standard (catch-all error handling è un piccolo refactor + 1 test; docs sync è meccanico)

**Mocking technique decision**: per testare il catch-all senza introdurre Mox, **estraggo la chiamata `Ideas.create_idea/1` dietro una funzione iniettabile via socket assigns**: `socket.assigns[:create_idea_fun] || (&Ideajar.Ideas.create_idea/1)`. In test, `assign(socket, :create_idea_fun, fn _ -> {:error, :db_unavailable} end)` sostituisce il default. Pattern già documentato come "test seam via assigns" — meno ingombrante di Mox per un singolo punto di iniezione.

**RED**:
1. `test/ideajar_web/live/idea_live/index_test.exs` (estensione): aprire LV con `live_isolated` e iniettare `:create_idea_fun` via socket assigns dopo mount; submit form con valid input → render contiene flash con `role="alert"` e testo "Salvataggio non riuscito, riprova", form ancora visibile con valori popolati (`@form` non resettato), LV process non crashato.
2. Asserire che il flash success di Step 6 ha `aria-live="polite"` (o `role="status"` se Phoenix scaffold usa quello) — pin del live-region per A12.
3. `test/ideajar/docs_test.exs` (estensione): README.md contiene `mix ecto.migrate`. `docs/conventions.md` contiene tutte le 15 nuove stringhe della UI copy table (incluso `Salvataggio…`, `Idea aggiunta`, `Salvataggio non riuscito, riprova`, `Apri link in una nuova scheda`, `Il link non può superare i 2000 caratteri`).
4. **Spec sync test**: il file `docs/specs/add-idea-base.md` contiene la versione iter-2 dei Gherkin scenarios + Architecture (no `change_idea/2`). Test minimo: `File.read!(...) =~ "data:text/html"` (un token unico aggiunto in iter 2) e **non** contiene `change_idea/2`.

**GREEN**:
- Iniettabilità: `lib/ideajar_web/live/idea_live/index.ex` aggiunge `defp create_idea_fun(socket), do: socket.assigns[:create_idea_fun] || (&Ideajar.Ideas.create_idea/1)`. `handle_event("save", ...)` chiama `create_idea_fun(socket).(attrs)`.
- Catch-all branch:
  ```
  case create_idea_fun(socket).(attrs) do
    {:ok, _} -> ...success (Step 6)...
    {:error, %Ecto.Changeset{} = cs} -> ...changeset error (Step 7)...
    {:error, _other} -> socket |> put_flash(:error, "Salvataggio non riuscito, riprova") |> assign(form: to_form(Ideajar.Ideas.Idea.changeset(%Idea{}, attrs), action: :insert))
  end
  ```
- Aggiornare README.md "Quick start" con `mix ecto.migrate` post `mix setup`.
- Estendere `docs/conventions.md` "UI copy" table con le 15 nuove stringhe.
- **Sync `docs/specs/add-idea-base.md`** con la versione iter-2 del Gherkin block + Architecture (rimuovere `change_idea/2` dall'Interface section). Spec è il single source of truth per i futuri lettori.

**REFACTOR**: nessuno.
**Files**: `lib/ideajar_web/live/idea_live/index.ex`, `README.md`, `docs/conventions.md`, `docs/specs/add-idea-base.md`, `test/ideajar_web/live/idea_live/index_test.exs`, `test/ideajar/docs_test.exs`.
**Spec mapping**: S6, D1, D2, A12.

## Complexity Classification

| Step | Complessità | Motivazione |
|------|-------------|-------------|
| 1 | standard | Schema + migration con rollback test automatizzato |
| 2 | **complex** | URL validation è security-relevant; canonical strings; boundary + multi-error |
| 3 | standard | Thin context wrapper |
| 4 | **complex** | LiveView entry + mount auth defense-in-depth |
| 5 | **complex** | push_event + JS hook + CoreComponents inputs + a11y |
| 6 | **complex** | Submit + persistence + secure link rendering + flash + focus + double-click guard |
| 7 | standard | Error rendering via CoreComponents (eredita la struttura) |
| 8 | **complex** | Routing change + file deletion + test migration cross-cutting |
| 9 | standard | Catch-all + docs sync |

## Pre-PR Quality Gate

- [ ] `mix test` passa (incluso `:migration` tagged test in test/ideajar/ideas/migration_test.exs).
- [ ] `mix format --check-formatted` passa.
- [ ] `mix credo` passa.
- [ ] `mix deps.audit` passa.
- [ ] `mix compile --warnings-as-errors` passa.
- [ ] `/code-review` su file toccati passa.
- [ ] **F1 traceability**: ogni `Scenario:` Gherkin (escluso `:manual` "Ideas survive an app restart") ha almeno un test ExUnit/LiveViewTest che lo cita per nome (`# Scenario: …` sopra il `test`). Verifica via grep nella PR description.
- [ ] **V1**: 4 screenshot in `docs/screenshots/slice-2/`.
- [ ] **V1a**: Lighthouse a11y mobile ≥95 — output JSON allegato.
- [ ] **V1b**: walkthrough keyboard-only verificato secondo i 7 step elencati.
- [ ] **V1c**: persistence survival manualmente verificata.
- [ ] CI verde sul push.

## Risks & Open Questions

- **R1 — Session keys come stringhe nel mount.** Pattern `%{"authenticated" => true}` esplicito. Helper `IdeajarWeb.ConnCase.authenticated_session/0` per i test.
- **R2 — `live_isolated/3` per testare LV senza route (Step 4).** Phoenix.LiveViewTest supporta nativamente. Permette di testare il LV come unit prima di wirearlo a `/`.
- **R3 — `push_event` + JS listener è testabile.** `assert_push_event/3` di `Phoenix.LiveViewTest` verifica che il server abbia emesso l'evento. Il fatto che il browser focusi è V1b manuale. Questo chiude il gap automation di iter 1.
- **R4 — Migration timestamp uniqueness.** Single-developer trunk-based, no collision attesa.
- **R5 — Test concurrency con Ecto sandbox.** Il `migration_test.exs` è `async: false` perché manipola lo schema; gli altri usano sandbox per-test (ConnCase default).
- **R6 — Step 4 senza route swap.** Per uno step il LiveView esiste come modulo "orfano" (non raggiungibile via HTTP); CI passa perché nessun test lo collega a `/`. La route swap è in Step 8. Trunk-based: ogni step rimane committable e CI verde.
- **R7 — A2 (no description cap) implica DB potenzialmente grande.** SQLite TEXT è unbounded; in pratica le coppie scrivono note brevi. Se mai diventasse un problema, slice future re-introdurranno il cap con behavioral driver.
- **R8 — `phx-disable-with` blocca solo client-side.** Un attaccante via curl può POST due volte. Per slice 2 (2-user app, no concurrency reale) è acceptable. Slice future con scrittura più frequente potrebbero aggiungere idempotency-key server-side.
- **R9 — `focus_first_invalid/1` su edit case.** Iter 2 prevede solo create. Quando arriverà edit, riusare l'helper su `focus_first_invalid(changeset, prefix)` parametrizzato.
- **R10 — Step 6 e Step 7 condividono `focus_first_invalid/1`.** Step 6 lo introduce (per la branch error nel save handler); Step 7 lo riusa nei test. Decisione: implementare in Step 6 con TDD su error path almeno scheletrico, poi Step 7 espande la copertura.
- **Q1 — Trunk-based screenshots.** V1 screenshot in `docs/screenshots/slice-2/` committati con Step 9 oppure separato? Decisione: committarli con il PR-equivalent commit (l'ultimo della slice). Se dimenticati, V1 non è chiuso.

## Plan Review Summary (iter 1)

> Reviewer iter 1: acceptance, design, UX = needs-revision; strategic = approve.
> Iter 2 incorpora i blocker e i warning ad alto leverage. Da rilanciare solo i 3 reviewer che hanno richiesto revision.

### Modifiche di iter 2 rispetto a iter 1

**Acceptance fixes:**
- P1, P2, P3 rimosse (P1: YAGNI 2-user; P2/P3: design budget non binary-verifiable).
- `data:`, `https://`, `://example.com` aggiunti a S4.
- F1 split: focus-return è automatabile come "server emette push_event con target X" (V1b chiude il loop browser-side).
- F7 aggiunto (close discards, reopening empty).
- S5 aggiunto (case-insensitive scheme).
- S6 aggiunto (DB write failure resilience).
- S7 aggiunto (phx-disable-with anti-double-click).
- Boundary scenarios espliciti (title 200, url 2000).
- Tie-break scenario esplicito.
- Mixed-error scenario esplicito.
- DB-failure scenario esplicito.
- Migration rollback automatizzato (Step 1 RED #4).
- Implementation leak rimosso ("no LiveView state initialised", "DOM" → "rendered HTML").

**Design fixes:**
- Step 4 splittato: solo LV creation (no routing). Step 8 dedicato a routing + cleanup + test migration con nomi espliciti.
- Step 6 focus mechanism committato: `push_event` server-side + JS listener (A5).
- Step 7 error rendering via CoreComponents `<.input>` (A7), niente flat list.
- `phx-change` rimosso (A4).
- Schema/migration types committati (A1).
- `change_idea/2` rimosso dal context (A3).
- 4 test migrati con nomi espliciti in Step 8.

**UX fixes:**
- Close button `type="button"` esplicito (A9).
- Autofocus title via push_event (A6) anziché HTML autofocus.
- `phx-disable-with` non opzionale (A8).
- Errors associati ai field via CoreComponents (aria-describedby/aria-invalid) — A7.
- Focus jump al primo invalid post-submit error (Step 7).
- Success flash "Idea aggiunta" (A10).
- DB failure resilience (S6, Step 9).
- Link mobile-friendly: aria-label + class break-all (A11).
- Copy drift: tutti gli error string canonici, asserzione esatta nei test.

**Strategic fixes:**
- Description 5000-char cap rimosso (A2).
- P1 1000-idea fixture rimosso.
- Distribuzione doc updates: stringhe nuove vanno in `docs/conventions.md` nel commit dell'introduzione, ma Step 9 fa il sync finale + automated docs_test.

### Warning iter 1 ancora aperti (tracciati per `/build`)

- **Acceptance B1 (Step 1 NOT NULL constraint via `Ecto.ConstraintError`)**: documentato come comportamento atteso; Step 1 RED #2 usa `assert_raise`.
- **Acceptance B5 (Step 5 idempotent toggle_form)**: chiarito come "secondo click no-op" (Step 5 RED #5).
- **Strategic 100-ideas list scenario**: skipped — YAGNI per 2-user.
- **Strategic null-byte test**: skipped — YAGNI per 2-user fidato.
- **Strategic Step 9 distribuzione**: parzialmente — UI copy table è updated nel commit di Step 9 in modalità sync.

## Plan Review Summary (iter 2.1)

> **Verdetti finali**: acceptance approve (post-iter-2.1 fix), design approve, UX approve, strategic approve.
> Questa sezione aggrega le warning superstiti da tracciare durante `/build`.

### Warning superstiti da tracciare durante implementation

**Acceptance (5 → tutti tracciati come build-time refinement):**
- W1 — V1b extended copre i 3 focus push_event target (toggle_form → title, error → first invalid, save → add button). **Già applicato in iter 2.1**.
- W2 — Multi-error submit potrebbe beneficiare di un summary aria-live "Il form contiene N errori" in cima al form per orientamento screen-reader (oltre ai field-level errors di CoreComponents). Non blocker; valutare in V1a Lighthouse audit.
- W3 — F7 + click error → close → reopen: assicurare che la riapertura mostri form pulito (no aria-invalid stale) — coperto implicitamente da `reset_form/1` ma vale la pena un test esplicito durante Step 5 implementation.
- W4 — Single-idea base case (zero/one/many): coperto da Step 6 RED #6 ("submit con solo title"), ma non c'è scenario standalone di "lista con 1 idea". Trascurabile data la copertura.
- W5 — XSS sul render post-submit (vs render della lista pre-esistente): coperto come parte di Step 6 RED #9 implicitamente (description con HTML triggera XSS check sulla lista che include la nuova idea). OK.

**Design (3 → 2 risolti in iter 2.1, 1 minor):**
- W6 — Spec drift su `change_idea/2`: **risolto in iter 2.1** (Step 9 ora include sync di `docs/specs/add-idea-base.md`).
- W7 — Plan vs spec divergent Gherkin: **risolto in iter 2.1** (stesso Step 9 sync).
- W8 — `focus_first_invalid/1` cross-step: introdotto in Step 6 (per il branch error del save handler), espanso in Step 7. Tracking: durante `/build` mantenere il primo RED test di Step 6 per error-path almeno scheletrico.

**UX (4 → 1 risolto in iter 2.1, 3 minor):**
- W9 — Flash live-region politeness pinning: **risolto in iter 2.1** (Step 9 RED #2 + A12).
- W10 — V1b step 7 deterministic: **risolto in iter 2.1** (V1b step 6 esplicitamente parla di tab order successivo).
- W11 — F7 hit area: **risolto in iter 2.1** (A12: ≥44×44 CSS px sul `✕`).
- W12 — Multi-error summary aria-live (overlap con W2): da valutare in V1a; se Lighthouse a11y ≥95 senza, accettare; sennò aggiungere come fast-follow.

**Strategic (4 → tutti già accettati o risolti):**
- W13 — Step 8/9 boundary: distribuzione UI copy mantenuta come sync finale in Step 9 — accettata.
- W14 — P1 1000-idea fixture: **rimosso**.
- W15 — Description 5000 cap: **rimosso** (A2).

### Reviewer observations (preservate per contesto)

- **Acceptance**: copertura scenarios molto solida (boundary, mixed-error, tie-break, double-click, DB-failure). F1 split focus-return è il fix giusto. Le canonical strings pinned byte-for-byte chiudono la copy drift.
- **Design**: A1-A12 pre-build decision section è il move giusto (locks settled choices). Step 4 split + push_event focus + CoreComponents inputs sono tutti choice canoniche. Domain/web boundary rispettato. Spec sync in Step 9 chiude il rischio drift.
- **UX**: tutti i 4 blocker iter 1 risolti con decisioni testabili. Error-recovery story strong (focus jump, value preservation, field-associated errors). A12 hit-area + flash live-region chiudono i gap a11y subtle.
- **Strategic**: scope discipline mantenuta. Out-of-scope items rispettati. Each step independently committable on trunk.

### Net assessment

Plan è **implementation-ready**. Le warning tracciate sopra sono tutte refinement di livello implementation, non strutturali. None require structural revision before starting.
