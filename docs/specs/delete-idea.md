# Spec: Eliminare un'idea (con conferma esplicita)

> Slice add-on (post slice 8). Sblocca la rimozione di idee dalla lista; la modifica resta out of scope (slice futura).
> Nessuna nuova migration: `idea_categories.idea_id` ha già `on_delete: :delete_all` dalla migration iniziale (`priv/repo/migrations/20260503000001_initial_schema.exs`), quindi il cascade sui link di categoria è gratuito a livello DB.

## Intent Description

Su ogni card della lista idee compare in alto a destra un bottone-icona **"🗑"** con `aria-label="Elimina idea"`. Click → si apre una **modal di conferma** "Eliminare questa idea?" che mostra il titolo dell'idea (HTML-escaped) e due bottoni: **`Annulla`** (default focus) e **`Elimina`** (azione distruttiva, stile rosso). `Esc`, click sul backdrop o click su `Annulla` chiudono la modal senza effetti. Click su `Elimina` → `Ideajar.Ideas.delete_idea/1` rimuove la riga; il cascade FK sul join `idea_categories` distrugge i link di categoria collegati. Lista rerender, modal chiusa, flash `"Idea eliminata"`, focus sulla card successiva (o sul bottone `+ Aggiungi idea` se la lista resta vuota).

Spazio condiviso: nessuna ownership, nessun audit. Hard delete: la riga sparisce dal DB, niente `deleted_at`. Race con altro device che ha già eliminato la stessa idea → no-op silenzioso a dominio (`{:error, :not_found}`), flash `"Idea già eliminata"` + refresh lista. Errore DB inatteso → flash `"Eliminazione non riuscita, riprova"` con `role="alert"`, lista invariata.

LiveView `mount/3` continua a verificare `session["authenticated"] == true` (defense-in-depth slice 1). Tutti gli eventi di delete richiedono lo stesso plug `:require_auth` del resto della LiveView.

## User-Facing Behavior

```gherkin
Feature: Eliminare un'idea con conferma esplicita

  Background:
    Given my browser holds a valid signed session cookie marking this device as authenticated
    And the workspace currently contains the ideas:
      | id | title                | categories         |
      | 1  | "Mare a Sirolo"      | "Mare,Weekend"     |
      | 2  | "Cinema stasera"     | "Sera"             |
      | 3  | "Museo del Castello" | "Cultura,Weekend"  |

  # ── Affordance del bottone su ciascuna card ─────────────────────────
  Scenario: Each idea card exposes a delete button
    When I visit "/"
    Then each idea card contains a button with aria-label "Elimina idea"
    And each delete button has type="button"
    And each delete button is keyboard-focusable

  # ── Apertura della modal ────────────────────────────────────────────
  Scenario: Clicking the delete icon opens the confirm modal with focus on Annulla
    Given I am on "/"
    When I click the delete button on the "Mare a Sirolo" card
    Then a modal with role="dialog" and aria-modal="true" becomes visible
    And the modal title reads "Eliminare questa idea?"
    And the modal body contains the text 'Elimina l\'idea "Mare a Sirolo". L\'idea sarà rimossa definitivamente.'
    And the modal exposes a "Annulla" button (type="button")
    And the modal exposes an "Elimina" button (type="button", style danger)
    And the server emits a "ideajar:focus" event targeting the "Annulla" button
    And the workspace still contains the 3 ideas

  Scenario: The modal title is HTML-escaped against XSS in the idea title
    Given the workspace contains an idea with title "<script>alert(1)</script>"
    When I click the delete button on that card
    Then the rendered modal HTML contains "&lt;script&gt;alert(1)&lt;/script&gt;"
    And the rendered modal HTML does not contain the literal "<script>alert(1)</script>"

  # ── Chiusura senza effetti ──────────────────────────────────────────
  Scenario Outline: Closing the modal leaves the workspace unchanged
    Given the delete modal for "Mare a Sirolo" is open
    When I <action>
    Then the modal is no longer visible
    And the workspace still contains 3 ideas
    And the server emits a "ideajar:focus" event targeting the delete button on the "Mare a Sirolo" card

    Examples:
      | action                                         |
      | click "Annulla"                                |
      | press the Escape key                           |
      | click the modal backdrop outside the dialog    |

  # ── Conferma: percorso felice ───────────────────────────────────────
  Scenario: Confirming the deletion removes the idea, closes the modal, and shows a success flash
    Given the delete modal for "Mare a Sirolo" is open
    When I click "Elimina"
    Then the modal is no longer visible
    And the idea "Mare a Sirolo" is no longer in the rendered list
    And the workspace contains exactly 2 ideas
    And a flash "Idea eliminata" with role="status" is shown
    And the server emits a "ideajar:focus" event targeting the delete button on the next card
    # next card = the card immediately after the deleted one in render order

  Scenario: Deleting the only idea leaves the empty state and focuses the add button
    Given the workspace contains exactly one idea "Solo questa"
    And the delete modal for "Solo questa" is open
    When I click "Elimina"
    Then the workspace contains 0 ideas
    And I see the empty-state message "Nessuna idea ancora. Aggiungine una qui sopra."
    And the server emits a "ideajar:focus" event targeting "#add-idea-button"

  Scenario: Deleting the last card in the list focuses the previous card's delete button
    Given the workspace contains the ideas "Prima", "Seconda", "Terza" in render order
    And the delete modal for "Terza" is open
    When I click "Elimina"
    Then the workspace contains 2 ideas
    And the server emits a "ideajar:focus" event targeting the delete button on the "Seconda" card

  # ── Cascade su idea_categories ──────────────────────────────────────
  Scenario: Deleting an idea tears down its category links
    Given the idea "Mare a Sirolo" is linked to categories "Mare" and "Weekend"
    And the delete modal for "Mare a Sirolo" is open
    When I click "Elimina"
    Then the row in idea_categories with idea_id = 1 no longer exists for category "Mare"
    And the row in idea_categories with idea_id = 1 no longer exists for category "Weekend"
    And the categories "Mare" and "Weekend" still exist in the categories table
    # categories themselves survive (FK on_delete: :restrict on category_id)

  # ── Race / concorrenza ──────────────────────────────────────────────
  Scenario: Confirming deletion of an idea already removed by another device shows a "already deleted" flash and refreshes
    Given the delete modal for "Cinema stasera" is open
    And another device has already deleted "Cinema stasera"
    When I click "Elimina"
    Then the modal is no longer visible
    And a flash "Idea già eliminata" with role="status" is shown
    And the rendered list reflects the current DB state without "Cinema stasera"
    And the LiveView process did not crash

  Scenario: The Elimina button is disabled while the deletion is in flight
    Given the delete modal for "Mare a Sirolo" is open
    When the form is being submitted
    Then the "Elimina" button has the phx-disable-with attribute equal to "Eliminazione…"
    And tapping it again before the response would be ignored client-side

  # ── Errore DB inatteso ──────────────────────────────────────────────
  Scenario: An unexpected Repo failure surfaces a generic flash without crashing
    Given the delete modal for "Mare a Sirolo" is open
    And the persistence layer will fail with an unexpected error on delete
    When I click "Elimina"
    Then I see a flash "Eliminazione non riuscita, riprova" with role="alert"
    And the modal remains visible (so the user can retry or cancel)
    And the workspace still contains 3 ideas
    And the LiveView process did not crash

  # ── Mount auth (defense-in-depth, parallelo a slice 2) ──────────────
  Scenario: A delete event from an unauthenticated session is rejected
    Given my browser presents a session cookie that does not validate
    When I attempt to send a "request_delete" event with id=1
    Then the LiveView redirects me to "/login?return_to=%2F"
    And the workspace still contains the 3 ideas

  # ── Filtri attivi (compatibilità slice 4-8) ─────────────────────────
  Scenario: Deleting an idea while a filter is active preserves the filter
    Given I have applied the category filter "Weekend"
    And the rendered list shows only "Mare a Sirolo" and "Museo del Castello"
    And the delete modal for "Mare a Sirolo" is open
    When I click "Elimina"
    Then the rendered list shows only "Museo del Castello"
    And the URL still encodes the "Weekend" filter
```

> Nota: gli scenari sopra coprono i casi richiesti dalla `feature-file-validation`:
> negativi (race, errore DB, sessione non valida), edge (lista vuota dopo delete, ultima
> card della lista, filtri attivi), errori espliciti con copy IT canonico,
> idempotency soft via `phx-disable-with`. XSS sul titolo escluso da raw rendering
> nello scenario dedicato.

## Architecture Specification

### Components

| Componente | Tipo | Responsabilità |
|---|---|---|
| `Ideajar.Ideas` | Context module (`lib/ideajar/ideas.ex`) | Aggiunge `delete_idea/1` (per id). Wrappa `Repo.delete/1`. Mantiene la regola "domain pure": nessun import da `IdeajarWeb.*`. |
| `Ideajar.Ideas.Idea` | Ecto schema | Nessuna modifica. Lo `many_to_many :categories` esistente con `join_through: "idea_categories"` non richiede change: il cascade è in DB. |
| Migration | — | **Nessuna nuova migration.** Il FK `idea_categories.idea_id references(:ideas, on_delete: :delete_all)` è già presente dalla migration iniziale (slice 1). Il delete a dominio non deve toccare `idea_categories` esplicitamente. |
| `IdeajarWeb.IdeaLive.Index` | LiveView esistente (`lib/ideajar_web/live/idea_live/index.ex` + heex) | Nuovi handle_event `"request_delete"`, `"cancel_delete"`, `"confirm_delete"`. Nuovo assign `@deletion`. Card rerender con bottone trash. Modal renderizzata condizionalmente. |
| Modal di conferma | HEEx markup inline nello `index.html.heex` (no LiveComponent dedicato — YAGNI per una sola modal) | `role="dialog"`, `aria-modal="true"`, `aria-labelledby`, focus iniziale via `JS.focus`, listener Esc + backdrop. |

### Interfaces

- **Domain API** — aggiunta a `Ideajar.Ideas`:
  ```elixir
  @spec delete_idea(integer()) ::
          {:ok, Idea.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def delete_idea(id) when is_integer(id) do
    case Repo.get(Idea, id) do
      nil -> {:error, :not_found}
      idea -> delete_struct_safe(idea)
    end
  end

  @doc false
  def delete_struct_safe(%Idea{} = idea) do
    try do
      Repo.delete(idea)
    rescue
      Ecto.StaleEntryError -> {:error, :not_found}
    end
  end
  ```
  Niente preload prima del delete: il cascade è in DB. Il `try/rescue` chiude la finestra di race in cui due processi superano `Repo.get/2` e il secondo `Repo.delete/1` solleva `Ecto.StaleEntryError` (mappato a `{:error, :not_found}` perché lato chiamante è semanticamente identico). `delete_struct_safe/1` è `@doc false`: test seam interno per F12, non parte dell'API pubblica.

- **LiveView assigns**:
  - `@deletion :: nil | %{id: integer(), title: String.t()}` — quando non-nil la modal è visibile e mostra il titolo (HEEx auto-escape).

- **LiveView events**:
  - `"request_delete"` con params `%{"id" => id}` → recupera l'idea da `@ideas` (no DB hit), `assign(socket, deletion: %{id: id, title: idea.title})` + `JS.focus("#delete-cancel-btn")`. Se l'id non è in `@ideas` (race con un'altra tab), reply silenzioso senza aprire modal.
  - `"cancel_delete"` → `assign(socket, deletion: nil)` + focus al bottone trash della card sorgente (id passato in params).
  - `"confirm_delete"` con params `%{"id" => id}` → `Ideas.delete_idea(id)`:
    - `{:ok, _}` → rerender lista da `Ideas.list_ideas(opts)` (preserva filtri attivi), `assign(deletion: nil)`, flash `"Idea eliminata"`, push focus al successor (logica "next card or add button").
    - `{:error, :not_found}` → flash `"Idea già eliminata"`, refresh lista, `assign(deletion: nil)`.
    - `{:error, _}` (catch-all DB error) → flash `"Eliminazione non riuscita, riprova"`, **modal resta visibile** (utente può ritentare o annullare).

- **HEEx markup (nuovo)**:
  ```heex
  <button
    type="button"
    id={"delete-btn-#{idea.id}"}
    aria-label="Elimina idea"
    phx-click="request_delete"
    phx-value-id={idea.id}
    class="trash-btn min-w-[44px] min-h-[44px]"
  >🗑<span class="sr-only">Elimina</span></button>

  <%= if @deletion do %>
    <div role="dialog" aria-modal="true"
         aria-labelledby="delete-modal-title"
         aria-describedby="delete-modal-body"
         id="delete-modal" phx-window-keydown="cancel_delete" phx-key="Escape">
      <div class="backdrop" phx-click="cancel_delete"></div>
      <div class="dialog">
        <h2 id="delete-modal-title">Eliminare questa idea?</h2>
        <p id="delete-modal-body">
          Elimina l'idea "<%= @deletion.title %>". L'idea sarà rimossa definitivamente.
        </p>
        <button id="delete-cancel-btn" type="button"
                phx-click="cancel_delete">Annulla</button>
        <button type="button" phx-click="confirm_delete"
                phx-disable-with="Eliminazione…"
                class="bg-red-700 hover:bg-red-800 text-white">Elimina</button>
      </div>
    </div>
  <% end %>
  ```
  Backdrop e `<div class="dialog">` sono **fratelli** nel DOM (no nesting): click sul dialog non bubble al backdrop. `cancel_delete` legge l'id da `socket.assigns.deletion.id`, non da params (`phx-window-keydown` non garantisce di propagare `phx-value-*`).

- **Focus management** (post-confirm):
  ```elixir
  defp focus_target_after_delete(ideas, deleted_id) do
    case Enum.find_index(ideas, &(&1.id == deleted_id)) do
      nil ->
        "#add-idea-button"
      i ->
        cond do
          length(ideas) == 1 -> "#add-idea-button"
          i < length(ideas) - 1 -> "#delete-btn-#{Enum.at(ideas, i + 1).id}"
          true -> "#delete-btn-#{Enum.at(ideas, i - 1).id}"
        end
    end
  end
  ```
  Restituisce un id DOM che il LiveView passa a `push_event("ideajar:focus", %{to: id})`, coerente con `index.ex:106` esistente (slice 2).

- **DB schema**: nessuna modifica. Cascade già coperto da `idea_categories.idea_id references(:ideas, on_delete: :delete_all)`.

### Constraints

- **Hard delete** — niente `deleted_at`, niente soft-delete. Allineato a "no audit trail / no created_by" del progetto.
- **Cascade in DB** — il context `delete_idea/1` non tocca `idea_categories` esplicitamente; affidiamoci al FK. Test a dominio verifica che la riga sul join sparisce dopo `delete_idea/1`.
- **No PubSub real-time** — coerente col resto delle slice. Il device B vede la sparizione solo al refresh.
- **Modal markup inline** — niente LiveComponent dedicato per una sola modal usata in un solo posto (YAGNI; promosso a componente solo se ne serve una seconda).
- **`phx-disable-with`** sul bottone "Elimina" per double-click protection (parallelo a slice 2 "Salva").
- **Auth defense-in-depth** — gli handler delete restano sotto `:require_auth`; mount continua a verificare la session.
- **HEEx auto-escape** sul titolo dell'idea nel body della modal (`<%= @deletion.title %>`, niente `raw/1`).
- **Focus trap** non implementato (KISS — la modal è semplice; rivedere se in futuro le modali diventano più complesse).
- **`Ecto.StaleEntryError` race-safe** — sotto concorrenza vera (due processi superano `Repo.get/2` e il secondo `Repo.delete/1` solleva `Ecto.StaleEntryError`), il dominio mappa l'eccezione a `{:error, :not_found}` via `try/rescue`. Lato chiamante è semanticamente identico ("la riga non c'è più"). Coperto da AC F12.

### Dependencies

Nessuna nuova dipendenza Hex. Nessuna nuova migration.

### Out of scope

- Edit idea (slice successiva).
- Soft delete / cestino / undo post-conferma.
- Bulk delete (selezione multipla).
- Delete da pagina dettaglio (non esiste).
- Audit log / "chi l'ha eliminata" (no `created_by` per design).
- Conferma via doppio click anziché modal.
- Real-time push tra device alla cancellazione.
- Animazione di rimozione card.

## Acceptance Criteria

### Functional / behavioral

- [ ] **F1** — Tutti gli scenari Gherkin automatabili passano come test ExUnit (`Phoenix.LiveViewTest` per il LiveView, `DataCase` per il context).
- [ ] **F2** — `Ideas.delete_idea/1` con id valido rimuove la riga; `Repo.get/2` post-delete ritorna `nil`.
- [ ] **F3** — `Ideas.delete_idea/1` con id inesistente ritorna `{:error, :not_found}` senza I/O di delete (`Repo.delete` mai chiamato).
- [ ] **F4** — `Ideas.delete_idea/1` su un'idea con N link in `idea_categories` rimuove la riga `ideas` e tutte le N righe in `idea_categories` per quell'`idea_id`. Le righe in `categories` restano invariate.
- [ ] **F5** — La modal di conferma mostra il titolo dell'idea HTML-escaped (test esplicito su titolo con `<script>`).
- [ ] **F6** — Click su `Annulla`, su backdrop o tasto `Esc` chiudono la modal senza effetto sul DB.
- [ ] **F7** — Dopo delete riuscito: flash `"Idea eliminata"`, lista rerender da `Ideas.list_ideas(opts)` con i filtri attivi preservati.
- [ ] **F8** — Race con altro device: `confirm_delete` su id già rimosso → flash `"Idea già eliminata"`, lista refresh, focus a `#add-idea-button`, no crash.
- [ ] **F9** — Errore DB inatteso (stub di `delete_idea_fun` che ritorna `{:error, %Ecto.Changeset{}}`): flash `"Eliminazione non riuscita, riprova"` con `role="alert"`, modal resta visibile (`@deletion` invariato), lista invariata, processo LV non crasha.
- [ ] **F12** — Atomicità race: due `delete_idea/1` in parallelo sullo stesso id non sollevano `Ecto.StaleEntryError`; il secondo riceve `{:error, :not_found}` via il `try/rescue` di A3.
- [ ] **F13** — Bottone `Elimina` ha attributo `phx-disable-with="Eliminazione…"` (assertion sull'attributo).

### Security

- [ ] **S1** — XSS: titolo `<script>alert(1)</script>` nel body modal renderizzato come testo escapato.
- [ ] **S2** — Auth: handler `request_delete`/`confirm_delete` con sessione non valida → redirect a `/login?return_to=%2F`. Test esplicito.
- [ ] **S3** — Idempotency soft: doppio click rapido sul bottone `Elimina` non causa due delete grazie a `phx-disable-with` + secondo `confirm_delete` che riceve `{:error, :not_found}`.

### Operational / data

- [ ] **O1** — Nessuna nuova migration. Cascade asserito comportamentalmente in F4.

### A11y / Validation venue

- [ ] **V1** — 2 screenshot mobile-viewport (modal aperta + lista post-delete o empty state) committati in `docs/screenshots/slice-12/`.
- [ ] **V1b** — Manual keyboard walkthrough verificato: Tab → trash → Enter → modal con focus su `Annulla` → Esc → modal chiusa con focus tornato al trash. Verifica diretta in browser, niente file di handoff.

### Documentation / handoff

- [ ] **D1** — `docs/conventions.md` "UI copy" table aggiornata con le stringhe canoniche di questa slice (vedi tabella sotto).

### UI copy aggiunta (canonical, da appendere a `docs/conventions.md`)

| Elemento | Testo IT |
|---|---|
| Aria-label bottone trash su card | `Elimina idea` |
| Modal title | `Eliminare questa idea?` |
| Modal body (template) | `Elimina l'idea "<title>". L'idea sarà rimossa definitivamente.` |
| Bottone modal annulla | `Annulla` |
| Bottone modal conferma (danger) | `Elimina` |
| `phx-disable-with` su `Elimina` | `Eliminazione…` |
| Flash success (`role="status"`) | `Idea eliminata` |
| Flash race (`role="status"`) | `Idea già eliminata` |
| Flash errore DB (`role="alert"`) | `Eliminazione non riuscita, riprova` |

## Consistency Gate

- [x] Intent is unambiguous — modal-only confirm, hard delete, cascade in DB, focus successor card / add button.
- [x] Every behavior has a corresponding BDD scenario — affordance, open, escape paths (×3), happy path, empty-state-after-delete, last-card focus, cascade, race, in-flight disable, DB error, auth, filter preservation, XSS escape.
- [x] Architecture constrains without over-engineering — nessuna nuova migration, modal inline (no LiveComponent), `Ideas.delete_idea/1` thin wrapper.
- [x] Terminology consistent — "modal di conferma", "Elimina", "Annulla", `idea_categories`, "successor card" usati identici nei 4 artefatti.
- [x] No contradictions — auth, focus pattern, copy IT, NULL/cascade behavior allineati a slice 1-8.

**Verdict: PASS** — ready for `/plan`.
