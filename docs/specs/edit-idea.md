# Spec: Edit an idea (slice 14)

> Slice 14. Adds the missing CRUD operation to the workspace: a couple
> can now modify an existing idea (title, description, link, categories,
> duration, budget, location) from the list view. Reuses the slice 2
> add-idea form **inline** in an `:edit` mode, applies the same
> `Idea.changeset/2` for validation parity. The card grows a ✏️ button
> next to the existing 🗑 (slice 12). Last-write-wins between the two
> devices, with the realistic `:not_found` race (delete-vs-edit) handled
> explicitly. No optimistic concurrency token, no history, no undo,
> no bulk edit, no notifications.

## Intent Description

Slice 14 chiude l'ultimo gap CRUD del workspace: oggi la coppia può
**creare**, **listare**, **filtrare** e **cancellare** un'idea, ma non
modificarla. Conseguenza pratica: una correzione banale (typo nel
titolo, link aggiornato, categoria sbagliata) costringe a cancellare
e ricreare, perdendo ordine in lista.

L'obiettivo è permettere la modifica completa dei campi che oggi il
form di creazione gestisce, **riusando lo stesso form inline** e la
**stessa funzione di changeset** così che validation, errori e UI
restino in un unico posto. La modifica vive nella stessa LiveView
della lista (`/`) — niente rotte nuove, niente modali. Cliccando una
nuova icona ✏️ sulla card, il form passa da modalità "Aggiungi idea"
a "Modifica idea" pre-popolato con i valori correnti. Submit applica
una nuova `Ideas.update_idea/2`.

**Concurrency**: il modello è last-write-wins. Per una coppia di 2
utenti la frequenza di edit simultanei è praticamente nulla; la
ceremonia di un token `expected_updated_at` non vale il costo. L'unica
race realistica è "edit-vs-delete" — A apre edit, B cancella nel
frattempo, A submit: gestita esplicitamente con `:not_found` →
flash `"Quest'idea è stata cancellata da un altro dispositivo."`,
form chiuso, lista refreshata.

**No-op submit**: se l'utente apre il form e lo submit-a senza aver
cambiato nulla, la LiveView rileva l'assenza di changes via
`changeset.changes == %{}` e chiude silenziosamente — nessun flash,
nessun roundtrip al DB. Onesto: nessuna modifica davvero applicata,
nessun messaggio "Idea modificata" che sarebbe ingannevole.

A11y e focus management seguono lo schema di slice 12: l'apertura
del form sposta il focus sul primo campo (title), Esc o Annulla
chiudono senza salvare, alla chiusura il focus torna al pulsante ✏️
della card sorgente. Sul submit con successo, flash `"Idea modificata"`
e refresh della lista filtrata — se l'idea editata ora non match più
i filtri attivi, sparisce correttamente dalla view.

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
    # Honest no-op: nothing was modified → no "Idea modificata" lie

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
    # No optimistic concurrency check — for a 2-user app the realistic
    # collision frequency is near-zero; explicit token + UX for the
    # rare case is over-engineering.

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
    # Deferred to slice 15+ if user pain emerges.

  Scenario: Slice 14 does NOT add bulk edit
    When I look at the list view
    Then there is no multi-select checkbox column
    And there is no "edit selected" toolbar action

  Scenario: Slice 14 does NOT add a separate /ideas/:id/edit route
    When I read the router
    Then no new route is added for editing

  Scenario: Slice 14 does NOT add optimistic concurrency
    When I read Ideas.update_idea/2 and the form
    Then no `expected_updated_at` (or similar) hidden field is rendered
    And no `:stale` error class is returned
    # Last-write-wins by design — see Intent Description.

  Scenario: Slice 14 does NOT notify the partner of an edit
    When the idea is edited on device A
    Then device B receives no push notification, no email, no PubSub broadcast
```

## Architecture Specification

### Components

| Componente | Tipo | Responsabilità |
|---|---|---|
| `Ideajar.Ideas.update_idea/2` | Context function (new) | Riceve `(idea_id, attrs)`. `Repo.get` → se nil `{:error, :not_found}`. Altrimenti applica `Idea.changeset/2` + `put_assoc(:categories, _)` (riuso del helper privato già usato da `create_idea`) + `Repo.update`. Tutto in `Repo.transaction` per coerenza con `delete_idea` (slice 12). |
| `Ideajar.Ideas.Idea.changeset/2` | Existing — reused as-is | Stessa funzione di add-idea. Validation parity strutturale. |
| `IdeajarWeb.IdeaLive.Index` | LiveView (modified) | 3 nuovi event: `request_edit`, `cancel_edit`, `submit_edit`. Nuovo assign `form_mode :: {:edit, idea_id} \| nil` (in modalità add il form è semplicemente aperto con `form_mode = nil`; non esiste un atom `:add`). La LV detect le no-changes prima di chiamare `update_idea/2` per il silent close. |
| `lib/ideajar_web/live/idea_live/index.html.heex` | Template (modified) | Card cresce con un `<button>` ✏️ tra il body e il "🗑" esistente. Heading + submit-label commutano in base a `form_mode`. **Nessun hidden field** (no concurrency token). **Nessun backdrop / modal wrapper** — il form resta inline come per add. |

### Interfaces

**`Ideajar.Ideas.update_idea/2`**:
```elixir
@spec update_idea(integer(), map()) ::
        {:ok, Idea.t()}
        | {:error, :not_found}
        | {:error, Ecto.Changeset.t()}
def update_idea(idea_id, attrs) do
  Repo.transaction(fn ->
    case Repo.get(Idea, idea_id) |> Repo.preload(:categories) do
      nil ->
        Repo.rollback(:not_found)

      %Idea{} = idea ->
        idea
        |> change_idea_with_categories(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated} -> Repo.preload(updated, :categories, force: true)
          {:error, changeset} -> Repo.rollback(changeset)
        end
    end
  end)
end
```

`change_idea_with_categories/2` è un helper privato del modulo `Ideas`
estratto dalla logica già esistente in `create_idea/1`: risolve i
`category_ids` via `Categories.list_by_ids/1`, applica
`Idea.changeset/2`, e fa `put_assoc(:categories, …)`. Estrazione
serve la DRY tra create e update.

**LiveView event flow:**
```
phx-click="request_edit" phx-value-id={idea.id}
  → Ideas.get_idea_with_categories!(id)
  → assign(:form_mode, {:edit, idea.id})
  → assign(:edit_origin_btn_id, "edit-btn-#{idea.id}")
  → assign(:edit_form, Idea.changeset(idea, %{}))
  → push_event(:focus, %{to: "#idea-title"})

phx-click="cancel_edit"  /  phx-key="Escape"
  → assign(:form_mode, nil)
  → push_event(:focus, %{to: assigns.edit_origin_btn_id})

phx-submit="submit_edit"
  → build changeset from params, detect changes
  → if changes is empty:
      assign(:form_mode, nil) + push_event focus    # silent no-op
  → else:
      Ideas.update_idea(id, attrs)
      → on {:ok, _}:    refresh list + flash "Idea modificata" + close form + push_event focus
      → on {:error, :not_found}:  flash "Quest'idea è stata cancellata…" + close + refresh list + push_event focus
      → on {:error, %Changeset{}}:  re-render form with errors + push_event focus to first errored field
```

### Constraints

- **No new schema field, no migration.** Riuso totale dello schema esistente.
- **No new route.** Form vive in `/` LiveView, modalità via assign.
- **No optimistic concurrency.** Last-write-wins. L'unica race rilevata e gestita è `:not_found` (slice 12 parity).
- **No hidden field, no `expected_updated_at`.** Esplicito out-of-scope test pin.
- **Form inline per `:add` E per `:edit`.** Stessa presentazione, solo il contenuto (heading + submit label + valori) cambia. Nessun backdrop, nessun modal wrapper.
- **No-op submit detection in LiveView via helper esplicito**: `Idea.changeset/2` con `put_assoc(:categories, ...)` registra un change `:replace` anche quando i category struct sono identici. Quindi `changeset.changes == %{}` da solo non basta. La LV usa `no_meaningful_changes?(idea, attrs)` (arity 2) che confronta scalar fields + sorted category_ids — `attrs` ha già le `category_ids` risolte da `compose_form_attrs/2`. Se identici → close form senza flash, senza DB write. Onesto, niente messaggio bugiardo.
- **`Idea.changeset/2` riusato**, no funzione `update_changeset/2` separata.
- **`change_idea_with_categories/2` extracted as private context helper**, riusato da create + update. DRY.
- **Atomic rollback via `Repo.transaction`** parallel `delete_idea` slice 12.
- **Focus management**: apri → `#idea-title`, chiudi (cancel/Esc/success/not_found) → `#edit-btn-<id>`. Pinned via test.
- **Tap target ≥ 44×44 px** sul nuovo bottone ✏️ (slice 12 parity).
- **Aria-label dinamico**: `"Modifica <title>"`, parallelo `"Elimina <title>"` di slice 12. Il title viene escapato automaticamente da HEEx in attribute context.
- **`Ideas.update_idea/2` è filter-unaware**: `function_exported?(Ideas, :update_idea, 3)` deve essere `false`. Il refresh della lista filtrata è responsabilità della LV.
- **No new Hex deps.**

### Dependencies

- `Ecto.Repo` — `get`, `transaction`, `rollback`, `update`, `preload` (esistenti).
- `Ideajar.Ideas.Idea.changeset/2` (esistente).
- `Ideajar.Ideas.Categories.list_by_ids/1` (esistente).
- `Ecto.Changeset.put_assoc/4` (esistente).
- Nessuna nuova dipendenza esterna.

### Out of scope

- Storia / audit trail
- Undo dopo save (deferred slice 15+ se emerge dolore reale)
- Bulk edit (multi-select)
- Dirty-state confirmation prima di chiudere
- Diff view "prima/dopo"
- Drag & drop riordino
- Edit dei timestamps
- Field-by-field inline edit
- Real-time sync push tra device (PubSub broadcast su edit)
- Route dedicato `/ideas/:id/edit`
- Notifica al partner
- **Optimistic concurrency** (token `expected_updated_at`, `:stale` error class, ISO8601 round-trip)
- **Modal-with-backdrop edit form** (form resta inline come per add)

## Acceptance Criteria

### Context layer

- [ ] **C1** — `Ideas.update_idea/2` exists con signature `(id, attrs) :: {:ok, Idea.t()} | {:error, :not_found | Changeset.t()}`.
- [ ] **C2** — `Repo.get` non trova → `{:error, :not_found}`.
- [ ] **C3** — Successo → `{:ok, idea}` con `categories` preloaded e fresh.
- [ ] **C4** — Validation failure → `{:error, %Ecto.Changeset{}}` per: title vuoto, url malformato, 0 categorie, duration invalido, budget invalido, location parziale.
- [ ] **C5** — `Repo.transaction` wrappa l'intera operazione.
- [ ] **C6** — Test pin: changeset failure (es. titolo valido + categorie zero) lascia l'idea su DB **invariata** — `idea.categories` non si svuota se l'update fallisce.
- [ ] **C7** — Test pin: `update_idea/2` è filter-unaware — `function_exported?(Ideas, :update_idea, 3) == false` (sola arity 2 ammessa).

### Validation parity

- [ ] **V1** — `Idea.changeset/2` riusato per edit, no funzione separata `update_changeset/2`.
- [ ] **V2** — Stessi error messages: `"Il titolo è obbligatorio"`, `"Il link deve iniziare con http:// o https://"`, `"Seleziona almeno una categoria"`, `"Durata non valida"`, `"Budget non valido"`, `"Posizione incompleta"` / `"Posizione non valida"`.
- [ ] **V3** — Test pin: per ogni regola di validazione, l'errore prodotto su edit è byte-identico a quello prodotto su add.

### LiveView events

- [ ] **L1** — `request_edit` con `%{"id" => raw}` apre il form in modalità edit pre-popolata.
- [ ] **L2** — `cancel_edit` chiude il form senza salvare.
- [ ] **L3** — `submit_edit` builds the changeset, detects no-changes, and either closes silently OR calls `Ideas.update_idea/2`.
- [ ] **L4** — Su `{:ok, _}` (with real changes): refresh lista + flash `"Idea modificata"` + form chiuso + focus.
- [ ] **L5** — Su no-changes: form chiuso, **NO flash**, no DB write, focus.
- [ ] **L6** — Su `{:error, :not_found}`: flash `"Quest'idea è stata cancellata da un altro dispositivo."` + form chiuso + lista refreshata + focus.
- [ ] **L7** — Su `{:error, %Changeset{}}`: re-render form con errori + focus al primo campo con errore.
- [ ] **L8** — `request_edit` con id sconosciuto: no-op silenzioso (no flash, no crash).

### UI / a11y

- [ ] **U1** — Card include `<button>` ✏️ con `aria-label="Modifica <title>"`, `min-w-[44px] min-h-[44px]`, posizionato a sinistra del 🗑.
- [ ] **U2** — Il pulsante è un `<button>` HTML nativo (Enter/Space lo attivano natively); test pin dell'elemento + assenza di `tabindex="-1"`.
- [ ] **U3** — Form section heading commuta tra `"Aggiungi idea"` e `"Modifica idea"` in base a `form_mode`.
- [ ] **U4** — Submit button label commuta tra `"Salva"` (slice 2 esistente, `:add` mode) e `"Salva modifiche"` (`:edit` mode).
- [ ] **U5** — **Nessun hidden input `expected_updated_at` nel form**, in qualsiasi modalità (negative pin).
- [ ] **U6** — Focus management:
  - apri → push_event `:focus` to `#idea-title`
  - chiudi (cancel / Esc / submit success / not_found / no-op) → push_event `:focus` to `#edit-btn-<id>`
- [ ] **U7** — Esc key chiude il form (`phx-window-keydown` con `phx-key="Escape"` → `cancel_edit`).
- [ ] **U8** — `assert_push_event(view, "ideajar:focus", ...)` pinned per: open, cancel close, submit-success close, not_found close, no-op close, validation-error focus.
- [ ] **U9** — Aria-label correttamente HTML-escaped per titoli con caratteri speciali (es. `"O'Brien & figli"`); test pin con un titolo che include `'` e `&`.

### Filter interaction

- [ ] **F1** — Dopo update riuscito, la lista re-fetcha rispettando i filtri attivi.
- [ ] **F2** — Filtro `mare` attivo, edit cambia categoria a `montagna` → idea sparisce.
- [ ] **F3** — Filtro `mare` attivo, edit cambia solo titolo → idea resta visibile con nuovo titolo.

### Out-of-scope guards

- [ ] **OS1** — Schema field guard: `:previous_title`, `:edit_history`, `:version` non sono in `Idea.__schema__(:fields)` (replace dello stale "no new migration" file-count pin).
- [ ] **OS2** — Nessuna nuova route. `IdeajarWeb.Router.__routes__()` invariato sui paths.
- [ ] **OS3** — Nessuna funzione `update_changeset/2` su `Ideajar.Ideas.Idea` (function_exported? = false).
- [ ] **OS4** — Flash post-save `"Idea modificata"` esatto, no toast con bottone Annulla.
- [ ] **OS5** — Nessun `expected_updated_at` (negative pin sui template).
- [ ] **OS6** — Nessun `phx-confirm` su Annulla / Esc (no dirty-check).
- [ ] **OS7** — Nessuna checkbox multi-select sulla card.
- [ ] **OS8** — Form rendered in `:add` E `:edit` non contiene un elemento con classe `backdrop` (negative pin: il form è inline, non modal).

### Operational

- [ ] **O1** — Nessun cambio a Dockerfile, runtime config, mix.exs, deploy workflow.
- [ ] **O2** — Nessun nuovo Hex dep.
- [ ] **O3** — Test suite resta verde (893+ esistenti + N nuovi).
- [ ] **O4** — Manual smoke su browser: open `/`, click ✏️ su un'idea, modifica titolo, submit, verifica titolo aggiornato in lista. Path race delete-vs-edit: aprire edit in tab A, delete in tab B, submit in A → flash `"…cancellata da un altro dispositivo"` + lista refreshata.

## Consistency Gate

- [x] **Intent unambiguo** — modifica completa di un'idea esistente, riuso form add inline, last-write-wins (no concurrency token), :not_found loud, no real-time sync, no history, no undo
- [x] **Ogni behavior ha BDD scenario** — entry point, pre-population, save (happy + validation + silent no-op), cancel (Annulla + Esc), :not_found race, last-write-wins explicit, filter interaction (sparizione + permanenza), out-of-scope guards
- [x] **Architecture senza over-engineering** — un solo nuovo context function, riuso changeset esistente, riuso form heex inline, zero nuove tabelle, zero nuove route, zero hidden fields concorrenza
- [x] **Termini consistenti** — `form_mode` (atom + tuple), `:not_found` (error tuple), pulsante `#edit-btn-<id>` (parallel `#delete-cancel-btn` di slice 12), `change_idea_with_categories` (helper privato condiviso)
- [x] **Nessuna contraddizione** — `Idea.changeset/2` riusato (no separate update changeset, OS3); `update_idea/2` resta loud su :not_found (parallel slice 12); flash post-save semplice senza undo (OS4); refresh lista filtrata vs filtri (F1-F3) coerente con pattern delete; no-op submit close silenzioso (no flash bugiardo); form inline coerente per add ed edit (no asymmetry)

**Verdict: PASS** — ready for `/plan`.
