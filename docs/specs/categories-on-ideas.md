# Spec: Categorie seeded e assegnabili alle idee

> Slice 3 of the ideajar project (see `CONTEXT.md` and the slice list in
> `docs/specs/`). Builds on slice 2 (add base idea) by tagging every idea
> with one or more categories from a fixed, seeded list. Slice 4 will add
> filtering by category — out of scope here.

## Intent Description

Slice 3 estende la LiveView slice 2 con tagging multi-categoria. Il set è
seeded in migration (8 voci broad: `passeggiata, mare, museo, ristorante,
sport, cultura, cinema, viaggio`) e read-only — la coppia condivide un
vocabolario stabile per supportare slice 4 (filter). Il form add-idea
espone una sezione `Categorie` con chip toggleabili (`<button
type="button" aria-pressed=…>`); almeno una categoria obbligatoria,
validata a livello changeset. La card di un'idea renderizza i suoi tag in
`display_order` come piccoli badge. Le idee dev di slice 2 vengono
cancellate da una migration dedicata (`wipe_slice2_dev_ideas`, distinta
dalla DDL del join table; test data, in prod questo sarà gestito
separatamente da slice 9).

Fuori scope esplicito: filtri per categoria (slice 4), search per nome
categoria (slice 8), badge colorati, UI di gestione categorie.

## User-Facing Behavior

```gherkin
Feature: Tag ideas with one or more curated categories

  Background:
    Given my browser holds a valid signed session cookie
    And the workspace has no ideas
    And the system has the canonical 8 seeded categories with display_order:
      | order | name        |
      | 1     | passeggiata |
      | 2     | mare        |
      | 3     | museo       |
      | 4     | ristorante  |
      | 5     | sport       |
      | 6     | cultura     |
      | 7     | cinema      |
      | 8     | viaggio     |

  # ── Form: chip rendering ────────────────────────────────────────
  Scenario: Opening the form shows all 8 categories as toggleable chips
    Given I am on "/"
    When I click "+ Aggiungi idea"
    Then I see a labelled fieldset whose legend reads "Categorie *"
    And the fieldset has a helper text "Scegli almeno una categoria"
    And the fieldset contains exactly 8 chips in display_order
    And every chip has type="button" and aria-pressed="false"
    And every chip has a hit area of at least 44×44 CSS px

  Scenario: Each chip toggles its aria-pressed state on click
    Given the add-idea form is expanded
    When I click the "mare" chip
    Then the "mare" chip has aria-pressed="true"
    When I click "mare" again
    Then "mare" has aria-pressed="false"

  Scenario: Multiple chips can be selected at once
    Given the add-idea form is expanded
    When I click "mare", "museo", "viaggio"
    Then those three chips are aria-pressed="true"
    And the other five are aria-pressed="false"

  # ── Submit: validation ──────────────────────────────────────────
  Scenario: Submitting with at least one category creates the idea
    Given the add-idea form is expanded
    When I fill "Mare a Sirolo" as the title
    And I select chips "mare" and "viaggio"
    And I submit
    Then the idea "Mare a Sirolo" is created
    And the rendered card shows the badges "mare" and "viaggio" in display_order

  Scenario: Submitting with no category selected shows the validation error
    Given the add-idea form is expanded
    When I fill "Cinema stasera" as the title
    And I leave categories empty
    And I submit
    Then I see "Seleziona almeno una categoria" associated with the categories fieldset
    And the form remains expanded
    And the server emits a "ideajar:focus" event targeting the first chip
    And no idea is created

  Scenario: The category validation accumulates with title/url errors
    Given the add-idea form is expanded
    When I submit with empty title, link "ftp://x", and no category
    Then I see "Il titolo è obbligatorio"
    And I see "Il link deve iniziare con http:// o https://"
    And I see "Seleziona almeno una categoria"
    And no idea is created

  Scenario: A toggled-then-untoggled chip submits as no category
    Given the add-idea form is expanded
    When I click "mare" then click "mare" again
    And I fill "x" as the title and submit
    Then I see "Seleziona almeno una categoria"

  # ── List: render ────────────────────────────────────────────────
  Scenario: Idea card renders its categories in display_order
    Given the workspace has an idea "Cinema stasera" tagged "cinema" and "cultura"
    When I visit "/"
    Then the rendered card shows badges in this order: "cultura", "cinema"

  Scenario: An idea with all 8 categories renders all 8 badges in display_order
    Given the workspace has an idea tagged with all 8 categories
    When I visit "/"
    Then the rendered card shows all 8 badges in display_order

  # ── Reset semantics ─────────────────────────────────────────────
  Scenario: Closing then reopening the form clears chip selection (F7-extension)
    Given the form is expanded with "mare" selected
    When I click the "✕" close icon
    And I click "+ Aggiungi idea"
    Then no chip is aria-pressed="true"

  Scenario: After successful save, reopening the form clears chip selection
    Given an idea was just saved with "mare" selected
    When I click "+ Aggiungi idea"
    Then no chip is aria-pressed="true"

  # ── Persistence semantics ───────────────────────────────────────
  Scenario: Manually re-invoking the seed-categories migration up/0 is a no-op
    Given the seed-categories migration has been applied
    When the migration's up/0 is invoked a second time on the same DB
    Then the categories table still has exactly 8 rows
    And no exception is raised

  Scenario: PRIMARY KEY on idea_categories prevents duplicate (idea_id, category_id) inserts
    Given an idea has the "mare" category attached
    When Repo.insert_all/3 attempts to insert (idea.id, mare.id) again
    Then a UNIQUE/PRIMARY KEY constraint error is raised
    And the join table still has exactly one row for that pair

  Scenario: Deleting an idea cascades on idea_categories but leaves categories intact
    Given an idea tagged "mare" and "museo"
    When the idea is deleted via Repo.delete/1
    Then the rows in idea_categories for that idea are removed
    And the rows in categories for "mare" and "museo" still exist

  Scenario: Attempting to delete a category that an idea references is blocked
    Given an idea references the "mare" category
    When I attempt to delete the "mare" row directly via Repo.delete/1
    Then the database raises a foreign key constraint error

  # ── Hostile inputs (S2/S3) ─────────────────────────────────────
  Scenario Outline: Calling Ideas.create_idea/1 with hostile category_ids returns "Categoria non valida"
    Given the workspace has the canonical 8 categories
    When Ideas.create_idea/1 is called with title "x" and category_ids <value>
    Then the call returns {:error, changeset}
    And errors[:categories] is exactly "Categoria non valida"
    And no exception is raised

    Examples:
      | value          |
      | [999999]       |
      | [-1]           |
      | [0]            |
      | [1.5]          |
      | ["abc"]        |
      | [""]           |
      | [nil]          |
      | [valid, 99999] |

  Scenario: Duplicate category_ids are silently de-duplicated server-side
    When I submit "x" with category_ids [2, 2, 3]
    Then the idea is created with exactly two categories: "mare" and "museo"

  Scenario: Mixed-type duplicates ["1", 1] dedupe to one category
    When Ideas.create_idea/1 is called with category_ids ["2", 2]
    Then the idea is created with exactly one category whose id == 2

  Scenario: XSS — a category whose name contains HTML is escaped on render
    Given a category exists whose name is "<script>alert(1)</script>" (inserted directly via Repo, bypassing the seed)
    And an idea is tagged with that category
    When the LiveView at "/" is rendered
    Then the rendered HTML contains "&lt;script&gt;alert(1)&lt;/script&gt;"
    And the rendered HTML does NOT contain the literal "<script>alert(1)</script>"
    And the same escape applies to the chip render when the form is open

  # ── Auth boundary (S4) ─────────────────────────────────────────
  Scenario: Unauthenticated mount cannot reach the chip form
    Given my browser holds no session cookie
    When the LiveView at "/" attempts to mount
    Then the mount returns a redirect to "/login?return_to=%2F"
    And @categories is never assigned to the socket

  # ── Out-of-scope guard ─────────────────────────────────────────
  Scenario: There is no UI to manage categories
    When I visit "/"
    Then no element with text matching /Aggiungi|Modifica|Elimina|Gestisci categori[ae]/i is rendered
    And the only categories-related phx-click in the page is "toggle_category"

  Scenario: Ideajar.Categories module exposes only list_categories/0 and list_by_ids/1
    When the application is loaded
    Then Ideajar.Categories.__info__(:functions) does not contain :create_category, :update_category, or :delete_category
    And it does contain :list_categories and :list_by_ids
```

## Architecture Specification

### Components

| Componente | Tipo | Responsabilità |
|---|---|---|
| `Ideajar.Categories` | Context (`lib/ideajar/categories.ex`) | API read-only del dominio: `list_categories/0` ordinate per `display_order`; `list_by_ids/1` con cast int safe + dedupe POST cast + all-or-nothing (boundary per Ideas); `preload_query/0` Ecto query ordinata. |
| `Ideajar.Categories.Category` | Schema (`lib/ideajar/categories/category.ex`) | `name` (string, NOT NULL UNIQUE), `display_order` (int, NOT NULL UNIQUE), `emoji` (string, NOT NULL — added in slice 14b), timestamps. |
| `Ideajar.Ideas.Idea` (esteso) | Schema esistente | `many_to_many :categories, Category, join_through: "idea_categories"` (default `on_replace: :raise`). Changeset usa `put_assoc(:categories, …)` + helper privato `validate_at_least_one_category/1` (verifica `get_field(cs, :categories)` perché `validate_length` salta silenziosamente quando il put_assoc non è stato chiamato). |
| `Ideajar.Ideas` (esteso) | Context esistente | `create_idea/1` ora accetta `"category_ids" => [int]`: la risoluzione passa per `Categories.list_by_ids/1`, su `:not_found` costruisce un changeset minimale con `add_error(:categories, Categories.invalid_message())` evitando il doppio errore. `list_ideas/0` preloada `:categories` via `Categories.preload_query/0`. |
| Migration `wipe_slice2_dev_ideas` | `priv/repo/migrations/<ts>_*.exs` | One-shot `execute("DELETE FROM ideas")` come `up/0`, `down/0` no-op. Separato dalla DDL del join per essere auditable in cronologia git. |
| Migration `create_categories_and_idea_categories` | `priv/repo/migrations/<ts>_*.exs` | (1) CREATE TABLE `categories` con UNIQUE indexes su `name` e `display_order`; (2) seed delle 8 categorie con `Repo.insert_all + on_conflict: :nothing, conflict_target: :name`; (3) CREATE TABLE `idea_categories` (composite PK, CASCADE su idea_id, RESTRICT su category_id); (4) `down/0` rimuove le tabelle nell'ordine inverso. |
| `IdeajarWeb.IdeaLive.Index` (esteso) | Esistente | Mount preloada `@categories` (lista immutabile per la sessione). Nuovo state `@selected_category_ids :: MapSet.t(integer)`. Handler `toggle_category` con `phx-value-id`. `save` passa `category_ids` al context. Reset analogo a F7 di slice 2 su toggle/close/save. |
| `IdeajarWeb.Components.CategoryChip` | Function component | `<button type="button" aria-pressed={…} phx-click="toggle_category" phx-value-id={id} class="…min-h-11 min-w-11">{name}</button>`. |

### Interfaces

**Domain API — `Ideajar.Categories`:**
```elixir
@spec list_categories() :: [Category.t()]    # ordered by display_order ASC
```

**Domain API — `Ideajar.Ideas` (esteso):**
```elixir
@spec create_idea(map()) :: {:ok, Idea.t()} | {:error, Ecto.Changeset.t()}
  # attrs ora supporta "category_ids" => [integer]
@spec list_ideas() :: [Idea.t()]
  # ritorna idee con :categories preloaded, sort interno per display_order
```

**DB schema (slice 3):**
```sql
CREATE TABLE categories (
  id            INTEGER PRIMARY KEY,
  name          TEXT NOT NULL UNIQUE,
  display_order INTEGER NOT NULL UNIQUE,
  inserted_at   TEXT_DATETIME NOT NULL,
  updated_at    TEXT_DATETIME NOT NULL
);
CREATE TABLE idea_categories (
  idea_id     INTEGER NOT NULL REFERENCES ideas(id) ON DELETE CASCADE,
  category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
  PRIMARY KEY (idea_id, category_id)
);
```

**LiveView assigns (estesi):**
- `@categories :: [Category.t()]` — preloaded at mount, mai mutato in sessione
- `@selected_category_ids :: MapSet.t(integer)` — stato form, reset su toggle/close/save
- `@form :: Phoenix.HTML.Form.t()` — invariato (categorie gestite fuori dal form data)

**LiveView events (estesi):**
- `"toggle_category"` con `%{"id" => id_string}` → toggle nel MapSet (server-side parse a integer)
- `"save"` con `%{"idea" => attrs}` → ora costruisce `Map.put(attrs, "category_ids", MapSet.to_list(@selected_category_ids))`

### Constraints

- **Validation** "almeno una categoria" è single source of truth a livello changeset, enforced da `validate_at_least_one_category/1` (helper privato in `Idea.changeset/2`). `validate_length/3` non viene usato perché salta silenziosamente quando l'associazione `:categories` è `nil` (mai inizializzata via `put_assoc`); il helper controlla `get_field(cs, :categories)` esplicitamente e aggiunge l'errore `Seleziona almeno una categoria` su lista vuota o assente.
- **Categories sono read-only** nel context: nessun `create_category/2`, `update_category/2`, `delete_category/1`. Modifica solo via migration.
- **Display order** è un'invariante: ogni seed ha `display_order` unico in 1..N. Render sempre per `display_order`.
- **Cascade**: `ON DELETE CASCADE` su `idea_categories.idea_id`; `ON DELETE RESTRICT` su `idea_categories.category_id` (protezione extra dato che non c'è UI di delete categoria).
- **HEEx auto-escape** sul render del nome categoria.
- **A11y dei chip**: `<fieldset>` con `<legend>Categorie</legend>` come group; ogni chip è un `<button>` focusabile con `aria-pressed`. Min 44×44 CSS px (WCAG 2.5.5). Wrapping responsivo su mobile. Errore validation associato al fieldset via `aria-describedby`.

### Dependencies

Nessuna nuova dipendenza Hex.

### Out of scope

- Filtri per categoria (slice 4)
- Search testuale che include nomi categoria (slice 8)
- UI di add/edit/delete categorie
- Badge colorati per categoria
- Ordinamento delle idee per categoria
- Re-ordering del display_order da utente

## Acceptance Criteria

### Functional / behavioral

- [ ] **F1** — Tutti gli scenari Gherkin automatabili passano (LiveView via `Phoenix.LiveViewTest`, domain via `DataCase`).
- [ ] **F2** — `Ideas.create_idea/1` con `category_ids: []` o senza la chiave → `{:error, changeset}` con `errors[:categories]` esattamente `Seleziona almeno una categoria`.
- [ ] **F3** — `Ideas.create_idea/1` con `category_ids: [valid_id]` → `{:ok, %Idea{categories: [%Category{}]}}` con la riga corrispondente in `idea_categories`.
- [ ] **F4** — `Ideas.list_ideas/0` ritorna idee con `:categories` preloaded e ordinate per `display_order` ASC.
- [ ] **F5** — Toggle di un chip già selezionato lo deseleziona (verificato via `view.assigns.selected_category_ids`).
- [ ] **F6** — Reset chip selection su form close + reopen.
- [ ] **F7** — Reset chip selection dopo successful save.

### Security

- [ ] **S1** — XSS: nome categoria sempre escapato in render (HEEx default). Test esplicito su categoria con nome contenente `<script>` (regression hardener: il seed reale non contiene HTML, ma il test pinna il comportamento).
- [ ] **S2** — `category_ids` con id non esistente in DB → `{:error, changeset}` con `errors[:categories]` esattamente `Categoria non valida`. Test esplicito con `category_ids: [999_999]`.
- [ ] **S3** — `category_ids` duplicati silenziosamente normalizzati (`[1, 1, 2]` → 2 categorie distinte sull'idea creata).

### Operational / data

- [ ] **O1** — Migration forward seeds 8 categorie con `display_order` 1..8 univoci.
- [ ] **O2** — Migration `down/0` rimuove `idea_categories` e `categories` nell'ordine corretto. Test round-trip up/down/up.
- [ ] **O3** — Migration idempotente forward: re-run di `mix ecto.migrate` non duplica righe in `categories`.
- [ ] **O4** — `ON DELETE CASCADE` su `idea_categories.idea_id` verificato via test (`Repo.delete!(idea)` rimuove le righe join).
- [ ] **O5** — `ON DELETE RESTRICT` su `idea_categories.category_id` verificato via test (`Repo.delete!(category)` con riga referenziata → errore).

### Validation venue

- [ ] **V1** — 4 screenshot mobile (iPhone 13 + Pixel 7): form aperto con tutti i chip non selezionati, form aperto con 3 chip selezionati, form con errore "Seleziona almeno una categoria", lista con 3 idee multi-category.
- [ ] **V1a** — Lighthouse a11y ≥95 sulla home con form aperto + mix di chip selezionati.
- [ ] **V1b** — Keyboard-only walkthrough:
  1. Tab attraverso `+ Aggiungi idea` → form aperto, focus su `#idea-title`.
  2. Tab → Titolo → Descrizione → Link → primo chip.
  3. Sui chip: Space toggle `aria-pressed`; Tab passa al chip successivo (no roving tabindex per slice 3).
  4. Tab dall'ultimo chip → bottone `Salva`.
  5. Verifica `aria-pressed` letto correttamente da screen reader (VoiceOver / NVDA spot check).

### Documentation

- [ ] **D1** — `docs/conventions.md` "UI copy" table aggiornata con: label `Categorie`, errori `Seleziona almeno una categoria` + `Categoria non valida`, e i nomi delle 8 categorie.

### UI copy aggiunta (canonical)

| Elemento | Testo IT |
|---|---|
| Legend del fieldset | `Categorie *` (asterisco visivo + sr-only "obbligatorio") |
| Helper text sotto legend | `Scegli almeno una categoria` |
| Errore "almeno una" | `Seleziona almeno una categoria` |
| Errore id invalido | `Categoria non valida` |
| Categoria 1 | `🚶 passeggiata` |
| Categoria 2 | `🏖️ mare` |
| Categoria 3 | `🏛️ museo` |
| Categoria 4 | `🍽️ ristorante` |
| Categoria 5 | `⚽ sport` |
| Categoria 6 | `🎭 cultura` |
| Categoria 7 | `🎬 cinema` |
| Categoria 8 | `✈️ viaggio` |

> **slice 14b update** — `Ideajar.Categories.Category` carries an additional `emoji` field (TEXT NOT NULL), populated by the `add_emoji_to_categories` migration with the canonical map above. Chips and badges render `<emoji> <name>`; the filter chip's `aria-label` stays emoji-free.

```gherkin
  # ── Slice 14b: emoji prefix on chips and badges ─────────────────
  Scenario: Form chip and filter chip render '<emoji> <name>'
    Given the workspace has the canonical 8 seeded categories with emoji
    And I am on "/"
    When I open the add-idea form and the filter row
    Then each form chip shows the canonical emoji immediately before the name (e.g. "🏖️ mare")
    And each filter chip shows the same prefix
    And the filter chip's aria-label remains exactly the name (or "<name> opzionale" / "<name> obbligatoria")

  Scenario: Idea card badges mirror the chip prefix
    Given the workspace has an idea "Mare a Sirolo" tagged "mare" and "viaggio"
    When I visit "/"
    Then the rendered card shows badges in display_order: "🏖️ mare", "✈️ viaggio"
```

## Consistency Gate

- [x] Intent is unambiguous
- [x] Every behavior has a corresponding BDD scenario
- [x] Architecture constrains without over-engineering
- [x] Terminology consistent (chip, categoria, display_order)
- [x] No contradictions between artifacts

**Verdetto: PASS** — ready for `/plan`.
