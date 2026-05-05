# Plan: Slice 14 — Edit an idea

**Created**: 2026-05-05
**Branch**: main (trunk-based)
**Status**: approved
**Spec**: `docs/specs/edit-idea.md`

## Build conventions (carried from slice 1-13)

- Strict TDD per ogni step. Test scritti prima del codice; ogni step lascia main verde.
- Pre-step gate: `mix compile --warnings-as-errors && mix format --check-formatted && mix credo && mix deps.audit && mix test`.
- commit-message skill option 1 for every commit.
- Trunk-based su `main`, no feature branch.
- Riuso del pattern slice 12 per cancel/focus/a11y; riuso del form add (slice 2) inline.
- Spec è la fonte di verità — scenari e acceptance copiati 1:1.

## Goal

Slice 14 chiude l'ultimo gap CRUD del workspace aggiungendo la modifica di un'idea esistente. Il flusso vive nella stessa LiveView di `/`: cliccando una nuova icona ✏️ sulla card, il form add esistente passa in modalità `:edit` pre-popolato, **inline** come oggi (no modal, no backdrop). Submit applica `Ideas.update_idea/2` (un nuovo context function con `Repo.transaction`, `not_found` check via `Repo.get`, validation tramite il `Idea.changeset/2` esistente). Last-write-wins tra device — l'unica race gestita esplicitamente è `:not_found` (delete-vs-edit). No optimistic concurrency token, no undo, no history. Zero nuove rotte, zero migration, zero Hex deps.

## Decisioni architetturali pre-build

- **DD-S14-1 — Riuso del form add via `form_mode` assign, INLINE in entrambe le modalità.** Niente template separato, niente modal, niente backdrop. Un nuovo assign `form_mode :: :add | {:edit, idea_id} | nil` controlla heading e submit-label. Add e edit sono visivamente identici eccetto per i due testi e il valore dei campi.

- **DD-S14-2 — `Idea.changeset/2` riusato, no `update_changeset/2`.** Validation parity garantita strutturalmente: stessa funzione, stessi messaggi (V2/V3 nello spec). DRY non-negoziabile.

- **DD-S14-3 — Last-write-wins (no optimistic concurrency).** Per una coppia di 2 utenti la frequenza di edit simultanei è praticamente nulla; aggiungere token + UX di race è ceremonia non giustificata. L'unica race realmente gestita è `:not_found` (delete-vs-edit), parallel slice 12.

- **DD-S14-4 — `update_idea/2` atomico in `Repo.transaction`.** Failure su qualsiasi sub-step rollback completo. Coerente con `delete_idea` di slice 12. Test pin C6: changeset failure su edit non lascia categorie semi-aggiornate.

- **DD-S14-5 — Helper privato `change_idea_with_categories/2` condiviso.** Estratto dalla logica di `create_idea/1` (risoluzione `category_ids` via `Categories.list_by_ids/1` + `put_assoc(:categories, …)`). Riusato da `create_idea` e `update_idea`. DRY senza duplicazione.

- **DD-S14-6 — No-op detection nella LiveView via helper esplicito.** `Idea.changeset/2` con `put_assoc(:categories, ...)` registra un change `:replace` anche quando i category struct sono gli stessi (semantica Ecto del put_assoc). Quindi `changeset.changes == %{}` non è sufficiente. La LV usa un helper privato `no_meaningful_changes?(idea, params)` che confronta:
  1. ogni scalar field (`title`, `description`, `url`, `duration`, `estimated_cost`, `location_name`, `lat`, `lng`) tra `idea` e i `params` cast-ati
  2. il **set sorted di category_ids** tra `idea.categories |> Enum.map(& &1.id) |> Enum.sort` e `params["category_ids"] |> Enum.map(&String.to_integer/1) |> Enum.sort`

  Se entrambi sono uguali → close form senza chiamare `update_idea/2`, senza flash, senza DB write. Test pin esplicito: idea con categorie `[mare, montagna]`, form re-submit con stesse `category_ids` in qualsiasi ordine, no altri field changes → no DB write.

- **DD-S14-7 — Bottone ✏️ stessa shape del 🗑.** `min-w-[44px] min-h-[44px]`, aria-label dinamica `"Modifica <title>"`, native `<button>` (Enter/Space activate natively). Posizionato a sinistra del 🗑. ID `#edit-btn-<idea_id>` per il focus restoration.

- **DD-S14-8 — Focus management identico a slice 12.** Apri → push_event focus su `#edit-title`; chiudi (cancel/Esc/success/no-op/not_found) → push_event focus su `#edit-btn-<id>` della card sorgente. Pinned via `assert_push_event` test su tutti i path di chiusura.

- **DD-S14-9 — Cancel flow due vie (Annulla / Esc).** Stesso pattern slice 12 ridotto. **NESSUN backdrop** (form inline, non modal). NESSUN dirty-check confirmation. Click su Annulla / `phx-key="Escape"` convergono su `cancel_edit`.

- **DD-S14-10 — Filter interaction = riuso refresh helper.** Dopo `{:ok, _}` da `update_idea/2`, la LV richiama il già-esistente helper di refresh lista filtrata. Se l'idea editata non match più i filtri, sparisce naturalmente. `update_idea/2` è filter-unaware (test pin C7).

- **DD-S14-11 — Test approach.** Unit test su `Ideas.update_idea/2` per i 3 rami (`:ok`, `:not_found`, `:changeset_error`). Integration test su `IdeajarWeb.IdeaLive.Index` per i 3 nuovi event handler con varianti happy + race + validation + no-op. Pin focus via `assert_push_event` su ogni path di chiusura. Pin OS via schema-fields + router-routes inspection (più robusto di file-grep).

- **DD-S14-12 — Pin out-of-scope.** Schema-field check (no `:previous_title`/`:version`/`:edit_history`), router check (no `/ideas/:id/edit`), function check (no `update_changeset/2`), template check (no `expected_updated_at` hidden field anywhere, no `class="backdrop"` nel form).

## Acceptance Criteria

> Mappatura uno-a-uno con `docs/specs/edit-idea.md`.

### Context layer
- [ ] **C1** — `Ideas.update_idea/2` exists con signature `(id, attrs) :: {:ok, Idea.t()} | {:error, :not_found | Changeset.t()}`.
- [ ] **C2** — `Repo.get` non trova → `{:error, :not_found}`.
- [ ] **C3** — Successo → `{:ok, idea}` con `categories` preloaded fresh (forced reload).
- [ ] **C4** — Validation failure → `{:error, %Ecto.Changeset{}}` per ogni regola (title vuoto, url malformato, 0 categorie, duration invalido, budget invalido, location parziale).
- [ ] **C5** — `Repo.transaction` wrappa l'operazione.
- [ ] **C6** — Test pin: changeset failure (es. titolo valido + categorie zero) lascia l'idea su DB **invariata** — `idea.categories` non si svuota se l'update fallisce.
- [ ] **C7** — Test pin: `function_exported?(Ideajar.Ideas, :update_idea, 3) == false` — la funzione è filter-unaware.

### Validation parity
- [ ] **V1** — Stessa funzione `Idea.changeset/2` per add e edit (no `update_changeset/2`).
- [ ] **V2** — Stessi error messages: `"Il titolo è obbligatorio"`, `"Il link deve iniziare con http:// o https://"`, `"Seleziona almeno una categoria"`, `"Durata non valida"`, `"Budget non valido"`, `"Posizione incompleta"` / `"Posizione non valida"`.
- [ ] **V3** — Test pin: ogni regola di validazione produce errore byte-identico tra add e edit.

### LiveView events
- [ ] **L1** — `request_edit` con `%{"id" => raw}` apre il form pre-popolato in `:edit` mode.
- [ ] **L2** — `cancel_edit` chiude il form senza salvare.
- [ ] **L3** — `submit_edit` builds the changeset, detects no-changes, branches accordingly.
- [ ] **L4** — Su `{:ok, _}` (with real changes): refresh lista + flash `"Idea modificata"` + form chiuso + focus.
- [ ] **L5** — Su no-changes: form chiuso, **NO flash**, no DB write, focus.
- [ ] **L6** — Su `{:error, :not_found}`: flash `"Quest'idea è stata cancellata da un altro dispositivo."` + form chiuso + lista refreshata + focus.
- [ ] **L7** — Su `{:error, %Changeset{}}`: re-render form con errori + focus al primo campo con errore. **"Primo campo"** = primo `field` per ordine di `changeset.errors` (il primo entry della keyword list), mappato all'`#edit-<field>` corrispondente nel DOM. Test pin: changeset con errori `[title: ..., url: ...]` → `assert_push_event(view, "ideajar:focus", %{to: "#edit-title"})`.
- [ ] **L8** — `request_edit` con id sconosciuto: no-op silenzioso (no flash, no crash).

### UI / a11y
- [ ] **U1** — Card ha `<button>` ✏️ con `aria-label="Modifica <title>"`, `min-w-[44px] min-h-[44px]`, posizionato a sinistra del 🗑.
- [ ] **U2** — Pulsante è un `<button>` HTML nativo (no `tabindex="-1"`); test pin sull'element type.
- [ ] **U3** — Heading commuta tra `"Aggiungi idea"` e `"Modifica idea"` in base a `form_mode`.
- [ ] **U4** — Submit button label commuta tra `"Aggiungi"` e `"Salva modifiche"`.
- [ ] **U5** — Negative pin: NESSUN hidden input `expected_updated_at` nel form (in qualsiasi modalità).
- [ ] **U6** — Focus management:
  - apri → push_event `:focus` to `#edit-title`
  - chiudi (cancel/Esc/success/no-op/not_found) → push_event `:focus` to `#edit-btn-<id>`
- [ ] **U7** — Esc key chiude il form (`phx-window-keydown` con `phx-key="Escape"` → `cancel_edit`).
- [ ] **U8** — `assert_push_event(view, "ideajar:focus", ...)` pinned per **ogni** path di chiusura: open, cancel, submit-success, no-op, not_found, validation-error.
- [ ] **U9** — Aria-label HTML-escape: test pin con title `"Caffè & relax"` rendered in card e nella validazione editor (Phoenix HEEx escaping in attribute context).

### Filter interaction
- [ ] **F1** — Update riuscito refresha lista rispettando filtri attivi.
- [ ] **F2** — Filtro `mare` attivo, edit cambia categoria a `montagna` → idea sparisce.
- [ ] **F3** — Filtro `mare` attivo, edit cambia solo titolo → idea resta visibile con nuovo titolo.

### Out-of-scope guards
- [ ] **OS1** — Schema-field pin: `:previous_title`, `:edit_history`, `:version` NOT in `Idea.__schema__(:fields)` (replace del fragile file-count pin).
- [ ] **OS2** — Nessuna nuova route. `IdeajarWeb.Router.__routes__()` non contiene path per edit.
- [ ] **OS3** — `refute function_exported?(Ideajar.Ideas.Idea, :update_changeset, 2)`.
- [ ] **OS4** — Flash post-save `"Idea modificata"` esatto, no toast con bottone Annulla.
- [ ] **OS5** — Negative template pin: NESSUN occorrenza di `expected_updated_at` in `index.html.heex`.
- [ ] **OS6** — Nessun `phx-confirm` su Annulla / Esc (no dirty-check).
- [ ] **OS7** — Nessuna checkbox multi-select sulla card markup.
- [ ] **OS8** — Negative template pin: NESSUN elemento con classe `backdrop` nel form section (form è inline).

### Operational
- [ ] **O1** — Nessun cambio a Dockerfile, runtime, mix.exs, deploy workflow.
- [ ] **O2** — Nessun nuovo Hex dep.
- [ ] **O3** — Test suite resta verde (893+ esistenti + N nuovi).
- [ ] **O4** — Manual smoke: open `/`, ✏️ su un'idea, modifica titolo, submit → titolo aggiornato in lista. Path :not_found: aprire edit in tab A, delete in tab B, submit in A → flash `"…cancellata da un altro dispositivo"`.

## User-Facing Behavior

```gherkin
Feature: Edit an idea

  Background:
    Given an authenticated user on the idea list at "/"
    And there is at least one idea visible in the list

  # ── Entry point ────────────────────────────────────────────────
  Scenario: Idea card shows a pencil button next to the trash button
    When I look at any idea card
    Then the card has a "✏️" button labelled "Modifica <title>"
    And the pencil button has min-w-44 min-h-44 tap target
    And the pencil button sits to the left of the existing "🗑" button
    And the pencil button is a native <button> element (Enter and Space activate it natively)

  Scenario: Clicking the pencil button opens the form in edit mode
    When I click the "✏️" button on an idea
    Then the add/edit form appears inline at the top of the page
    And the form section heading reads "Modifica idea"
    And every field is pre-filled with the idea's current values
    And the submit button label reads "Salva modifiche"
    And focus is moved to the title input

  # ── Pre-population ─────────────────────────────────────────────
  Scenario: All fields are pre-populated from the idea
    Given an idea "Sirolo" with description "spiaggia bianca", url
      "https://example.org/sirolo", categories ["mare"], duration
      "mezza_giornata", estimated_cost 50, location "Sirolo, Marche"
      with valid lat/lng
    When I open the edit form for that idea
    Then title is "Sirolo"
    And description is "spiaggia bianca"
    And url is "https://example.org/sirolo"
    And the "mare" category chip is selected
    And duration is "mezza_giornata"
    And the budget slider is at the index that maps to 50
    And the location reference shows "Sirolo, Marche"

  Scenario: Optional fields render empty when the idea has no value
    Given an idea with no duration, no estimated_cost, and no location
    When I open the edit form for that idea
    Then duration is unselected
    And the budget slider is at the "no budget" index
    And the location field is empty

  # ── Saving ─────────────────────────────────────────────────────
  Scenario: Submitting valid edits persists the changes and closes the form
    Given the edit form is open on idea "Sirolo"
    When I change the title to "Sirolo (riviera del Conero)"
    And I submit the form
    Then Ideas.update_idea/2 is invoked with the new attributes
    And the persisted idea has title "Sirolo (riviera del Conero)"
    And the form closes
    And the list refreshes
    And a flash message reads "Idea modificata"
    And focus returns to the "✏️" button of the card

  Scenario: Validation errors keep the form open with messages
    Given the edit form is open
    When I clear the title and submit
    Then the form stays open
    And the title field shows "Il titolo è obbligatorio"
    And no update is persisted
    And focus is moved to the title input

  Scenario: Editing categories reuses the same changeset rule
    Given the edit form is open
    When I deselect every category chip and submit
    Then the form stays open
    And an error reads "Seleziona almeno una categoria"

  Scenario: Submitting without any change closes the form silently
    Given the edit form is open on an idea
    When I submit without modifying any field
    Then the form closes
    And NO flash message is shown
    And the idea on disk is unchanged (no DB write, no updated_at bump)
    And focus returns to the "✏️" button of the card

  # ── Cancellation ───────────────────────────────────────────────
  Scenario: Annulla button closes the form without saving
    Given the edit form is open with unsaved changes
    When I click "Annulla"
    Then the form closes
    And the idea on disk is unchanged
    And focus returns to the "✏️" button of the card

  Scenario: Esc key closes the form without saving
    Given the edit form is open
    When I press Escape
    Then the form closes
    And the idea on disk is unchanged

  Scenario: No dirty-check confirmation on cancel
    Given the edit form is open with unsaved changes
    When I trigger any cancel action (Annulla / Esc)
    Then the form closes immediately
    And no "are you sure" prompt is shown

  # ── Concurrency (delete-vs-edit only) ──────────────────────────
  Scenario: Editing an idea that another device deleted fails loud
    Given device A has the edit form open on an idea
    And device B deletes the same idea
    When device A submits its form
    Then Ideas.update_idea/2 returns {:error, :not_found}
    And the form closes
    And the list refreshes (the idea is gone)
    And a flash reads "Quest'idea è stata cancellata da un altro dispositivo."

  Scenario: Editing an idea after the other device already edited it (last-write-wins)
    Given device A has the edit form open on idea "Sirolo"
    And device B saves a different edit, advancing updated_at
    When device A submits its form
    Then Ideas.update_idea/2 succeeds
    And device A's edits overwrite B's
    And a flash reads "Idea modificata"

  # ── Filter interaction ─────────────────────────────────────────
  Scenario: Edit changes that drop the idea from the active filter remove it from the list
    Given the active filter is category "mare"
    And idea "Sirolo" is currently visible (it has category "mare")
    When I open the edit form on "Sirolo"
    And I deselect "mare" and select "montagna" instead
    And I submit
    Then the idea persists with the new category set
    And the list refresh excludes "Sirolo" because it no longer matches the filter
    And a flash reads "Idea modificata"

  Scenario: Edit changes that keep the idea matching the filter keep it visible
    Given the active filter is category "mare"
    And idea "Sirolo" is currently visible
    When I edit "Sirolo" and only change the title
    And I submit
    Then the idea is still visible in the list
    And the title in the card reflects the edit

  # ── Out-of-scope guards ────────────────────────────────────────
  Scenario: Slice 14 does NOT add an audit/history trail
    When I read the schema, the migration history, and the LiveView
    Then no `idea_history` / `idea_versions` table exists
    And no `previous_*` columns appear on `ideas`

  Scenario: Slice 14 does NOT add an undo affordance after save
    When I look at the flash message after a successful save
    Then the flash reads exactly "Idea modificata"
    And there is no "Annulla" action embedded in the flash

  Scenario: Slice 14 does NOT add bulk edit
    When I look at the list view
    Then there is no multi-select checkbox column

  Scenario: Slice 14 does NOT add a separate /ideas/:id/edit route
    When I read the router
    Then no new route is added for editing

  Scenario: Slice 14 does NOT add optimistic concurrency
    When I read Ideas.update_idea/2 and the form
    Then no `expected_updated_at` (or similar) hidden field is rendered
    And no `:stale` error class is returned

  Scenario: Slice 14 does NOT notify the partner of an edit
    When the idea is edited on device A
    Then device B receives no push notification, no email, no PubSub broadcast
```

## Steps

> Ogni step segue RED → GREEN → REFACTOR. Il pre-step gate gira prima di ogni RED. Gli step sono 8 (rispetto ai 9 iniziali) — la rimozione dell'optimistic concurrency ha eliminato lo step "race paths".

### Step 1 — `Ideas.update_idea/2` con tutti i rami

**Complexity**: standard
**Scenarios**: "Submitting valid edits persists…", "Validation errors keep the form open…", "Editing an idea that another device deleted…"
**Spec mapping**: C1, C2, C3, C4, C5, C6, C7

**RED** (`test/ideajar/ideas_test.exs` extension):
- "update_idea/2 returns {:ok, idea} on success with categories preloaded"
- "update_idea/2 returns {:error, :not_found} when the id does not exist"
- "update_idea/2 returns {:error, %Changeset{}} for each validation rule" (title empty, url bad, 0 categories, duration invalid, budget invalid, location partial)
- "update_idea/2 rolls back atomically on changeset failure" — pin C6: setup idea con cat ["mare"], chiama update_idea con title valido + categories []; verifica che dopo il fail, l'idea su DB ha ancora cat ["mare"] (non vuoto)
- "Ideas.update_idea/3 is NOT exported" — pin C7 filter-unaware contract

**GREEN** (`lib/ideajar/ideas.ex`):
- Implementa `update_idea/2` con la signature dello spec (no `expected_updated_at`)
- `Repo.transaction do ... end`, `Repo.get` + preload(:categories), `Repo.rollback(:not_found)` se nil
- Estrai `change_idea_with_categories/2` come helper privato condiviso, da `create_idea/1` esistente; risolve `category_ids` via `Categories.list_by_ids/1` + `Idea.changeset/2` + `put_assoc(:categories, ...)`
- `Repo.update`, on error `Repo.rollback(changeset)`, on success `Repo.preload(updated, :categories, force: true)` per ritornare lo struct fresco

**REFACTOR**: estrai `change_idea_with_categories/2` come helper privato del modulo `Ideas`, riusato da `create_idea/1` e `update_idea/2`. DRY pulito.

**Files**: `lib/ideajar/ideas.ex`, `test/ideajar/ideas_test.exs`.

**Commit (draft)**: `Add Ideas.update_idea/2 with atomic rollback and shared changeset validation`

---

### Step 2 — Bottone ✏️ sulla card

**Complexity**: standard
**Scenarios**: "Idea card shows a pencil button next to the trash button"
**Spec mapping**: U1, U2

**RED** (`test/ideajar_web/live/idea_live/index_test.exs` new tests):
- "renders an edit button on every idea card"
- "edit button has aria-label `Modifica <title>`"
- "edit button properly HTML-escapes special characters in title (e.g., `Caffè & relax` → `aria-label=\"Modifica Caffè &amp; relax\"`)" — U9 pin
- "edit button has min-w-44 min-h-44 tap target classes"
- "edit button id is `edit-btn-<idea_id>`"
- "edit button is positioned to the LEFT of the trash button" — offset comparison nel rendered HTML
- "edit button has phx-click=request_edit and phx-value-id"
- "edit button is a native <button> element with no tabindex=\"-1\"" — U2 keyboard activation pin

**GREEN** (`lib/ideajar_web/live/idea_live/index.html.heex`): aggiungi `<button>` ✏️ con gli attributi richiesti. Stub handler in `index.ex` per evitare crash su click.

**Stub handler** (`index.ex`): `def handle_event("request_edit", _params, socket), do: {:noreply, socket}` — rimosso allo Step 3.

**REFACTOR**: nessuno.

**Files**: `lib/ideajar_web/live/idea_live/index.html.heex`, `lib/ideajar_web/live/idea_live/index.ex` (stub handler), test.

**Commit (draft)**: `Render the edit button on every idea card with its accessibility metadata`

---

### Step 3 — `request_edit` apre il form pre-popolato + focus

**Complexity**: standard
**Scenarios**: "Clicking the pencil button opens the form in edit mode", "All fields are pre-populated from the idea", "Optional fields render empty when the idea has no value"
**Spec mapping**: L1, L8, U3, U4, U6 (open half), U8 (open part)

**RED**:
- "request_edit with valid id assigns form_mode = {:edit, id}"
- "request_edit pre-populates form with the idea's title, description, url"
- "request_edit pre-populates duration when set, leaves it nil otherwise"
- "request_edit pre-populates budget slider when set, leaves it at 'no budget' otherwise"
- "request_edit pre-populates location_name + lat + lng when set, leaves them empty otherwise"
- "request_edit pre-populates the category chip selection from idea.categories"
- "form heading reads `Modifica idea` in :edit mode"
- "submit button label reads `Salva modifiche` in :edit mode"
- "request_edit pushes focus event to #edit-title" — `assert_push_event(view, "ideajar:focus", %{to: "#edit-title"})`
- "request_edit with unknown id is a no-op (no flash, no crash)" — L8 defensive
- "form does NOT contain hidden input named expected_updated_at" — U5 negative pin (anche in :edit mode)
- "form does NOT contain element with class `backdrop`" — OS8 negative pin
- "form remains inline (no modal wrapper around the form section)" — structural pin

**GREEN** (`index.ex`):
- Sostituisci stub. `handle_event("request_edit", %{"id" => raw}, socket)` → parse id → `Repo.get(Idea, id) |> Repo.preload(:categories)` (NON-bang per coerenza con R3 — id sconosciuto deve essere no-op, non crash)
- Se nil → `{:noreply, socket}` (no flash, no crash, defensive)
- Altrimenti → assign `form_mode: {:edit, id}`, `edit_origin_btn_id: "edit-btn-#{id}"`, `edit_form: Idea.changeset(idea, %{}) |> to_form(...)` (riuso del to_form pattern del form add)
- `push_event(socket, "ideajar:focus", %{to: "#edit-title"})`

**GREEN** (`index.html.heex`):
- Heading commuta in base a `@form_mode`
- Submit button label commuta in base a `@form_mode`
- Title field id `edit-title` (sempre, è lo stesso input)
- Form section visibile in `:add` AND `:edit` (controllato dal flag `form_visible?` esistente, che attiva su request_edit)
- **NESSUN** hidden field `expected_updated_at`. **NESSUN** backdrop. Form resta inline.

**REFACTOR**: se `form_mode` viene letto in 5+ posti, considera helper `edit_mode?/1`. Altrimenti nessuno.

**Files**: `index.ex`, `index.html.heex`, test.

**Commit (draft)**: `Open the form in edit mode pre-populated with the idea and shift focus to the title input`

---

### Step 4 — `cancel_edit` (Annulla / Esc) + focus restore

**Complexity**: standard
**Scenarios**: "Annulla button closes the form without saving", "Esc key closes the form without saving", "No dirty-check confirmation on cancel"
**Spec mapping**: L2, U6 (close half), U7, U8 (cancel part), OS6

**RED**:
- "cancel_edit resets form_mode to nil and closes form"
- "cancel_edit pushes focus event back to #edit-btn-<id> of the originating idea" — `assert_push_event`
- "phx-key=Escape on the form area triggers cancel_edit"
- "Annulla button inside the form triggers cancel_edit"
- "cancel does NOT have phx-confirm on any of its triggers" — pin OS6
- "cancel_edit on an :add form leaves :add behavior intact" — regression guard (le funzionalità slice 2 di toggle_form non si rompono)

**GREEN** (`index.ex`):
- `handle_event("cancel_edit", _params, socket)` → assign `form_mode: nil, edit_form: nil, form_visible?: false` + push focus **solo se** `socket.assigns[:edit_origin_btn_id]` non-nil (defensive: cancel_edit potrebbe essere triggerato dall'Esc handler quando il form è in `:add` mode, dove `edit_origin_btn_id` non è settato — in quel caso ricadiamo sul behavior originale slice 2 senza push focus)

**GREEN** (`index.html.heex`):
- Form area diventa keyboard-aware: `phx-window-keydown` con `phx-key="Escape"` solo quando `@form_mode != :add` (per non rompere il :add esistente)
- Annulla button visibile in :edit mode (e in :add se già esiste come behavior; verificare e preservare)
- **NESSUN backdrop** — form inline, niente click-fuori-chiude

**REFACTOR**: nessuno.

**Files**: come Step 3.

**Commit (draft)**: `Close the edit form via Annulla or Esc and restore focus to the originating pencil button`

---

### Step 5 — `submit_edit` happy path + validation re-render + no-op detect

**Complexity**: standard
**Scenarios**: "Submitting valid edits persists the changes…", "Validation errors keep the form open…", "Editing categories reuses the same changeset rule", "Submitting without any change closes the form silently"
**Spec mapping**: L3, L4, L5, L7, V1, V2, V3, U6, U8 (success/no-op/error parts)

**RED**:
- "submit_edit with valid params calls Ideas.update_idea/2 and gets {:ok, _}"
- "submit_edit on success refreshes the filtered list"
- "submit_edit on success shows flash `Idea modificata`"
- "submit_edit on success closes the form (form_mode = nil)"
- "submit_edit on success pushes focus to #edit-btn-<id>" — `assert_push_event` su success path
- "submit_edit with NO meaningful changes closes form WITHOUT calling update_idea/2 and WITHOUT flash" — L5 pin via `no_meaningful_changes?/2`
- "submit_edit no-op test setup: idea with categories [mare, montagna], form re-submits category_ids=[mare_id, montagna_id] in same order, no other field changes — no DB write"
- "submit_edit no-op test setup: same idea, form re-submits category_ids in REVERSE order [montagna_id, mare_id] — still no DB write (sorted compare)"
- "submit_edit no-op pushes focus to #edit-btn-<id>"
- "submit_edit with empty title shows `Il titolo è obbligatorio` and form stays open"
- "submit_edit with malformed url shows `Il link deve iniziare…`"
- "submit_edit with 0 categories shows `Seleziona almeno una categoria`"
- "submit_edit with invalid duration shows `Durata non valida`"
- "submit_edit with invalid budget shows `Budget non valido`"
- "submit_edit on validation error focuses the first errored field" — `assert_push_event`
- "validation parity (V3): each error message produced on edit equals the one produced on add" — explicit V3 pin

**GREEN** (`index.ex`):
- `handle_event("submit_edit", params, socket)` → estrai id da `form_mode`, ricarica `idea` (con categorie) tramite `Repo.get + preload`
- `no_meaningful_changes?(idea, params)` (helper privato): confronta scalar fields + sorted category_ids. Se true → close form + push_event focus + NO flash.
- Altrimenti → `Ideas.update_idea(id, params)`
  - `{:ok, _}` → refresh helper esistente, flash `"Idea modificata"`, close form, push_event focus
  - `{:error, %Changeset{}}` → assign nuovo changeset al form, push_event focus al `#edit-<field>` del primo errore (`changeset.errors |> hd() |> elem(0)` mappato a id DOM)

**REFACTOR**: nessuno previsto.

**Files**: come Step 3.

**Commit (draft)**: `Persist edits via update_idea/2, close silently on no-op, and re-render with errors on validation failure`

---

### Step 6 — `submit_edit` `:not_found` race path

**Complexity**: standard
**Scenarios**: "Editing an idea that another device deleted fails loud", "Editing an idea after the other device already edited it (last-write-wins)"
**Spec mapping**: L6, U6, U8 (not_found part)

**RED**:
- "submit_edit on :not_found shows flash `Quest'idea è stata cancellata da un altro dispositivo.`"
- "submit_edit on :not_found closes the form"
- "submit_edit on :not_found refreshes the list (idea is gone)"
- "submit_edit on :not_found pushes focus to #edit-btn-<id>" (note: il bottone potrebbe non esistere più nel DOM; il push_event non è bloccante, ma documenta il caso e il browser fa scroll-to-top fallback)
- "submit_edit on a stale-but-still-existing record overwrites it (last-write-wins, no :stale flash)" — explicit pin che non c'è optimistic concurrency

**GREEN** (`index.ex`):
- Estendi handle_event submit_edit:
  - `{:error, :not_found}` → put_flash + close form + refresh list + push_event focus

**REFACTOR**: nessuno.

**Files**: `index.ex`, test.

**Commit (draft)**: `Surface the delete-vs-edit race so the user sees the deletion happened elsewhere`

---

### Step 7 — Filter interaction pin + out-of-scope guards

**Complexity**: trivial
**Scenarios**: "Edit changes that drop the idea from the active filter…", "Edit changes that keep the idea matching the filter…", "Slice 14 does NOT add…"
**Spec mapping**: F1, F2, F3, OS1, OS2, OS3, OS4, OS5, OS6, OS7, OS8

**RED** (integration tests + schema/router/template pins):
- "active category filter `mare` + edit Sirolo to `montagna` → Sirolo absent from rendered list after submit"
- "active category filter `mare` + edit only Sirolo title → Sirolo still visible with new title"
- "no active filter + edit any field → idea visible, no filter side-effect"
- OS1: `refute :previous_title in Idea.__schema__(:fields)`, `refute :edit_history in Idea.__schema__(:fields)`, `refute :version in Idea.__schema__(:fields)`
- OS2: nessun route nuova in `IdeajarWeb.Router.__routes__()` con `path =~ "edit"`
- OS3: `refute function_exported?(Ideajar.Ideas.Idea, :update_changeset, 2)` (after `Code.ensure_loaded!`)
- OS4: il flash dopo save success è esattamente `"Idea modificata"`, non contiene `"Annulla"`
- OS5: `refute File.read!("lib/ideajar_web/live/idea_live/index.html.heex") =~ "expected_updated_at"`
- OS6: `refute File.read!("lib/ideajar_web/live/idea_live/index.html.heex") =~ ~r/phx-click="cancel_edit".*phx-confirm/`
- OS7: nel rendered HTML della lista NON appare `<input type="checkbox"` dentro la card markup
- OS8: `refute html =~ ~r/<[^>]*class="[^"]*backdrop[^"]*"/` quando il form è in `:edit` mode

**GREEN**: F-pin emerge da implementazione step 5; OS-pin passano vacuamente sullo state corrente. Step esiste come regression guard.

**REFACTOR**: nessuno.

**Files**: test.

**Commit (draft)**: `Pin the slice 14 filter interaction and the out-of-scope boundary so future edits cannot quietly add history, undo, or optimistic concurrency`

---

### Step 8 — Pre-PR gate

**Complexity**: trivial
**Scenarios**: tutti
**Spec mapping**: O1, O2, O3

**RED**: la suite deve restare verde — `mix test` passa.

**GREEN**: esegui in sequenza `mix compile --warnings-as-errors && mix format --check-formatted && mix credo && mix deps.audit && mix test`. Tutto verde.

**REFACTOR**: nessuno. Manual smoke (O4) lo fa l'utente sul browser dopo il merge.

**Files**: nessuno.

**Commit**: nessuno aggiuntivo se i precedenti passano.

---

## Complexity Classification

| Step | Rating | Justification |
|---|---|---|
| 1 | standard | Nuovo context function con 3 rami, transaction, helper extraction |
| 2 | standard | Markup + a11y + button placement + HTML escaping |
| 3 | standard | Nuovo event handler + form mode toggle + pre-population di tutti i campi + focus + negative pins |
| 4 | standard | Cancel duale + focus restoration — pattern slice 12 ridotto |
| 5 | standard | Submit handler + happy + no-op detect + validation re-render — il cuore del flusso |
| 6 | standard | :not_found race + flash management |
| 7 | trivial | Filter pin emerge naturalmente + out-of-scope assertion pinning |
| 8 | trivial | Gate passive |

## Pre-PR Quality Gate

- [ ] `mix compile --warnings-as-errors` passa
- [ ] `mix format --check-formatted` passa
- [ ] `mix credo` passa
- [ ] `mix deps.audit` passa
- [ ] `mix test` passa (incluso i nuovi test edit)
- [ ] `/code-review` su `lib/ideajar/ideas.ex`, `lib/ideajar_web/live/idea_live/index.{ex,html.heex}`, `test/ideajar/ideas_test.exs`, `test/ideajar_web/live/idea_live/index_test.exs`
- [ ] Manual smoke su browser: open ✏️ → edit → submit → verify card aggiornata; aprire 2 tab, delete in tab A mentre tab B edita, save in B → flash `:not_found` + refresh

## Risks & Open Questions

- **R1 — Pre-population di tutti i campi.** Il form add è già complesso (slice 7a location, slice 9 budget slider). Pre-popolare tutto richiede attenzione su slider + autocomplete dropdown. *Mitigazione*: ogni campo ha un pin dedicato in Step 3 RED. Manual smoke obbligatorio.

- **R2 — Detect no-changes via `changeset.changes == %{}`.** Funziona per i campi che il form gestisce direttamente. Per le `categories` (many_to_many via `put_assoc`), `changeset.changes` può contenere `%{categories: [...]}` anche se le stesse della preload, perché `put_assoc` con stessi struct produce changes :replace. *Mitigazione*: confronta gli IDs (sorted) in pre-check, OPPURE accetta che "submit senza modifiche realmente apparenti" possa attraversare `update_idea/2`; il roundtrip costa nulla per il caso limite. Documentato nel test.

- **R3 — `request_edit` con id sconosciuto.** Se l'altro device cancella mentre il primo sta per fare clic su ✏️, il click arriva con un id valido nel DOM ma non in DB. La `Ideas.get_idea_with_categories!/1` con `!` farebbe crash. *Mitigazione*: usa la versione non-bang (`Repo.get`) e fallback no-op (L8). Test pin esplicito.

- **R4 — Backward compat di `change_idea_with_categories/2` extraction.** Estrarre il helper da `create_idea/1` cambia il path interno di add. Rischio basso (la suite slice 2-12 è verde), ma il cambio richiede regression confidence. *Mitigazione*: Step 1 GREEN testa anche `create_idea/1` post-refactor (suite esistente già lo copre).

- **R5 — Aria-label HTML escaping.** Phoenix HEEx escapa automaticamente le interpolazioni `{}` in attribute context. *Mitigazione*: Step 2 RED ha un pin con title `"Caffè & relax"` per validare il behavior.

- **R6 — Form inline può aprirsi off-screen su liste lunghe.** Il form vive in cima alla pagina (`<section>` slice 2). Se l'utente clicca ✏️ su una card a metà lista, il form apre fuori dal viewport. Il push_event focus su `#edit-title` causa il browser a scrollare nativamente sull'elemento (behavior default `focus()` su elementi non-visible è `scrollIntoView`). *Mitigazione*: ereditata dal browser; per couple-of-2 con liste corte (< 50 idee) il rischio è bassissimo. Se in futuro la lista cresce, valuta `scrollIntoView({behavior: 'smooth', block: 'start'})` esplicito nel JS hook. Non blocking per slice 14.

## Plan Review Summary

Quattro reviewer dispatchati in parallelo, due iterazioni. Verdict finale: **tutti approve**.

### Iteration 1 — needs-revision (4/4)

6 blocker totali consolidati, in gran parte risolvibili scope-level:
- **Acceptance B1 / Design B3**: contraddizione no-op (byte-equal vs updated_at bumping) → risolto con detect-and-close-silently nella LV (B nelle scelte utente).
- **Acceptance B2 / Design B1**: ISO8601 round-trip + DateTime comparison → moot, optimistic concurrency rimossa.
- **Acceptance B3**: keyboard activation per ✏️ non testato → pinned via U2 (native `<button>` + no `tabindex="-1"`).
- **Design B2**: `workflow_dispatch` ref handling — n/a per questa slice.
- **UX B1**: stale flash senza CTA → moot, no stale path.
- **Strategic W1 / Design W5 / UX W3**: optimistic concurrency over-engineered + asymmetry modal-vs-inline → entrambi risolti scope-level (A: drop concurrency, D: form inline per entrambi).

10 warning ad alto valore applicate: drop optimistic concurrency, no-op silent-close, form inline per entrambi, schema-field pin OS1, helper extraction `change_idea_with_categories`, filter-unaware contract C7, aria-label HTML escape U9.

### Iteration 2 — approve (4/4)

- **Acceptance**: APPROVED. 3 issue residue minor (R2 categories no-op, bang inconsistency Step 3, validation-error focus mechanism) — tutte applicate.
- **Design**: APPROVED. 4 issue minor (R2 mitigation undecided, no-op detection seam, no-op test fixture, OS3 redundancy) — applicate eccetto OS3 (accept-as-is, belt-and-suspenders).
- **UX**: APPROVED. 3 issue minor (scroll-into-view R6, R2 categories, edit_origin_btn_id nil-safe) — R6 documentata come risk con mitigazione browser-default, le altre 2 applicate.
- **Strategic**: APPROVED. 1 issue minor (R2 mitigation) — applicata.

### Decisioni dell'utente che hanno semplificato il plan

- **A: drop optimistic concurrency** — eliminato 5 issue tecniche (ISO8601, DateTime compare, missing field error, hidden field, stale flash CTA)
- **B: detect+silent close on no-op** — risolto la contraddizione "byte-equal vs updated_at bump"
- **C: defer undo a slice 15+** — nessuna espansione di scope
- **D: form inline per entrambi** — eliminato l'asymmetry modal-vs-inline + il backdrop-vs-Nominatim conflict
