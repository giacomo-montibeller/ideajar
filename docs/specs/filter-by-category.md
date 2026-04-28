# Spec: Filter ideas list by category

> Slice 4 of the ideajar project. Builds on slice 3 (categories on ideas) by
> adding a tri-state filter chip row above the ideas list. No DB schema
> change; the filter is read-only and lives in LiveView session state.

## Intent Description

Slice 4 estende la home LiveView con un **filtro tri-state** per categoria
sopra la lista delle idee. Riusa il vocabolario delle 8 categorie seedate
(slice 3) e la famiglia visiva del `CategoryChip`, esteso a 3 stati invece
di 2:

- **off** (gray): filtro inattivo per quella categoria
- **opzionale** (green, icona `✓`): l'idea passa il filtro se contiene
  almeno una delle categorie verdi (clausola OR)
- **obbligatoria** (red, icona `✓✓`): l'idea deve contenere tutte le
  categorie rosse (clausola AND)

Espressione del filtro: `(ogni obbligatoria presente) AND (nessuna
opzionale selezionata OR almeno una opzionale presente)`. Niente filtri
selezionati = tutte le idee.

Un live region `aria-live="polite"` annuncia il count post-filtro agli
screen reader. Empty state dedicato quando il filtro non matcha
(`Nessuna idea per i filtri attivi.` + bottone `Mostra tutte`) — i chip
filter restano visibili per toggle individuali, mentre `Mostra tutte`
resetta solo lo state filtro (non il chip-selection del form add-idea,
che è state distinto).

Stato persistente solo in LV session (refresh = reset). Fuori scope:
filtro per durata/budget/distanza (slice 5-7), text search (slice 8),
URL params per deep-link (rinviato a slice 8), filter chip personalizzati
dall'utente, operatori NOT.

## User-Facing Behavior

```gherkin
Feature: Filter the ideas list with tri-state category chips

  Background:
    Given my browser holds a valid signed session cookie
    And the workspace has the canonical 8 seeded categories
    And the workspace has these ideas:
      | title         | categories          |
      | Sirolo        | mare, viaggio       |
      | Uffizi        | museo, cultura      |
      | Stadio        | sport               |
      | Bagno mattina | mare, sport         |
      | Cinema serale | cinema, cultura     |

  # ── Default state ──────────────────────────────────────────────
  Scenario: Visiting / with no filter shows every idea
    When I visit "/"
    Then I see all 5 ideas
    And every filter chip has data-filter-state="off"
    And the live-region announces "5 idee"

  # ── Tri-state cycle ────────────────────────────────────────────
  Scenario: Clicking a chip cycles off → optional → required → off
    Given I am on "/"
    When I click the "mare" filter chip
    Then "mare" has data-filter-state="optional"
    And "mare" has aria-label "mare opzionale"
    And the chip shows a single check icon
    When I click "mare" again
    Then "mare" has data-filter-state="required"
    And "mare" has aria-label "mare obbligatoria"
    And the chip shows a double check icon
    When I click "mare" again
    Then "mare" has data-filter-state="off"
    And "mare" has aria-label "mare"
    And the chip shows no check icon

  # ── Optional (OR) ──────────────────────────────────────────────
  Scenario: One optional chip filters to ideas tagged with that category
    When I cycle "sport" to optional
    Then I see "Stadio" and "Bagno mattina"
    And I do not see "Sirolo", "Uffizi", "Cinema serale"

  Scenario: Multiple optional chips form an OR
    When I cycle "sport" and "cultura" to optional
    Then I see "Stadio", "Bagno mattina", "Uffizi", "Cinema serale"
    And I do not see "Sirolo"

  # ── Required (AND) ─────────────────────────────────────────────
  Scenario: One required chip filters to ideas tagged with that category
    When I cycle "mare" to required
    Then I see "Sirolo" and "Bagno mattina"

  Scenario: Multiple required chips form an AND
    When I cycle "mare" and "sport" to required
    Then I see only "Bagno mattina"

  # ── Mixed required + optional ──────────────────────────────────
  Scenario: Required AND (≥1 optional) constrains both clauses
    When I cycle "mare" to required and "sport" and "cultura" to optional
    # mare🔴 + sport🟢 + cultura🟢 → mare AND (sport OR cultura)
    Then I see "Bagno mattina"
    And I do not see "Sirolo"
    # ↑ Sirolo has mare but neither sport nor cultura

  # ── Live-region count ──────────────────────────────────────────
  Scenario: Filter changes update the live-region count
    Given I am on "/"
    When I cycle "sport" to optional
    Then the live-region announces "2 idee"
    When I cycle "mare" to required
    Then the live-region announces "1 idea"
    When I click "Mostra tutte"
    Then the live-region announces "5 idee"

  # ── Empty result state ─────────────────────────────────────────
  Scenario: Filter matching zero ideas shows the empty-result state
    Given the workspace contains no idea tagged "passeggiata"
    When I cycle "passeggiata" to required
    Then I see "Nessuna idea per i filtri attivi."
    And I see a "Mostra tutte" button
    And the filter chip row remains rendered
    And "passeggiata" still has data-filter-state="required"

  Scenario: "Mostra tutte" resets the filter state but leaves chips visible
    Given I have "mare" required and "sport" optional
    When I click "Mostra tutte"
    Then every filter chip has data-filter-state="off"
    And I see all 5 ideas
    And the chip row is still rendered

  # ── Form vs filter state isolation ─────────────────────────────
  Scenario: Resetting filters does not touch the add-form chip selection
    Given the add-idea form is expanded with "mare" selected as form chip
    And the filter has "sport" required
    When I click "Mostra tutte"
    Then the form's "mare" chip is still aria-pressed="true"
    And the filter chip row has all data-filter-state="off"

  Scenario: Cycling a filter chip does not touch the form chip selection
    Given the add-idea form is expanded with "mare" selected as form chip
    When I cycle the filter "mare" to required
    Then the form's "mare" chip is still aria-pressed="true"
    And the filter "mare" has data-filter-state="required"

  # ── Persistence (LV-session only) ──────────────────────────────
  Scenario: Refresh resets the filter state
    Given I have "mare" required
    When I reload "/"
    Then every filter chip has data-filter-state="off"
    And I see all 5 ideas

  # ── Hostile inputs (defense-in-depth) ──────────────────────────
  Scenario: cycle_filter with a non-integer id is a no-op
    When I dispatch the LV event cycle_filter with id "abc"
    Then no filter state changes
    And the LV process does not crash

  Scenario: cycle_filter with a non-existent category id is a no-op
    When I dispatch cycle_filter with id 999999
    Then no filter state changes

  # ── Slice-3 regression ─────────────────────────────────────────
  Scenario: Ideas.list_ideas/0 still returns every idea unfiltered
    When I call Ideas.list_ideas/0 (no args)
    Then every idea is returned ordered by inserted_at DESC then id DESC
    # Backwards-compatible alias for list_ideas([])

  # ── Out-of-scope guard ─────────────────────────────────────────
  Scenario: There is no other filter UI in slice 4
    When I visit "/"
    Then no element matches the texts "Durata", "Budget", "Distanza", "Cerca"
```

## Architecture Specification

### Components

| Componente | Tipo | Responsabilità |
|---|---|---|
| `Ideajar.Ideas` (esteso) | Context | Nuova `list_ideas/1` con opts `[required: [int], optional: [int]]`. La vecchia `list_ideas/0` resta come default (`opts = []`). Query Ecto applica subquery `HAVING COUNT(distinct category_id) = ^required_count` per il required, `IN ^optional_ids` per l'optional. Preload categories ordinate via `Categories.preload_query/0`. |
| `IdeajarWeb.IdeaLive.Index` (esteso) | LiveView | Mount aggiunge `@filter_state :: %{integer => :optional \| :required}` (id assenti = off). Nuovi handler: `cycle_filter` (con id-string parse safe), `clear_filters`. Render della lista chiama `Ideas.list_ideas/1` con state derivato da `@filter_state`. Live-region `<div role="status" aria-live="polite">` annuncia "N idea/idee". |
| `IdeajarWeb.Components.CategoryChip` (esteso) | Function component | Aggiunge variante tri-state via attr `state :: :off \| :optional \| :required` (default `:off`) + `aria_label`/`event_name` configurabili. Backward-compat: il caller di slice 3 (form add-idea) continua a chiamare con `selected? :: boolean` mappato a `:off`/`:optional`. |
| `IdeajarWeb.IdeaLive.Index` template | HEEx | Sopra la lista: riga di chip filter sempre visibile, live-region count, empty-state dedicato quando lista filtrata vuota. Bottone `Mostra tutte` mostrato solo quando almeno un chip è in stato non-off. |

### Interfaces

**Domain API — `Ideajar.Ideas` (esteso):**
```elixir
@spec list_ideas() :: [Idea.t()]
@spec list_ideas(opts :: keyword()) :: [Idea.t()]
  # opts:
  #   required: [integer]   # ids che devono TUTTE essere presenti sull'idea
  #   optional: [integer]   # ids di cui ALMENO UNA deve essere presente
  # Returns ideas ordered by inserted_at DESC, id DESC; categories preloaded.
```

**LiveView assigns (estesi):**
- `@filter_state :: %{integer => :optional | :required}` — id assenti = off; reset on `clear_filters`, refresh, mount

**LiveView events (estesi):**
- `"cycle_filter"` con `%{"id" => id_string}` → cicla off → optional → required → off
- `"clear_filters"` → resetta `@filter_state` a `%{}`

**Componente CategoryChip esteso:**
```elixir
attr :id, :integer, required: true
attr :name, :string, required: true
attr :state, :atom, default: :off, values: [:off, :optional, :required]
attr :event_name, :string, default: "toggle_category"
attr :aria_describedby, :string, default: nil
```

### Constraints

- **Filter is read-only**: nessun DB write; nessun nuovo schema.
- **Backward compat**: `Ideas.list_ideas/0` non cambia comportamento (tutte le idee, ordering preservato). Pinned by regression test.
- **Filter state ≠ form selection**: due strutture distinte. Cycle filter non tocca form, e viceversa.
- **A11y**: ogni chip è `<button>` con `aria-label` dinamico (`"mare"` / `"mare opzionale"` / `"mare obbligatoria"`); `data-filter-state="off|optional|required"` come anchor per CSS+test. Live-region count via `role="status" aria-live="polite"`. Min 44×44 hit area come slice 3.
- **No `aria-pressed` sui filter chip**: stato è ternario, non binario. Slice-3 form chips mantengono `aria-pressed` (binario).
- **HEEx auto-escape** sul rendering.
- **Hostile inputs**: `cycle_filter` con id non-integer o id non esistente → no-op silenzioso.

### Dependencies

Nessuna nuova dipendenza Hex.

### Out of scope

- Filtri durata/budget/distanza (slice 5-7)
- Text search (slice 8)
- URL params / deep-link (rinviato a slice 8)
- Salvataggio filtri come "preset"
- Operatori NOT (es. "non sport")

## Acceptance Criteria

### Functional / behavioral
- [ ] **F1** — Tutti gli scenari Gherkin automatabili passano (LV via Phoenix.LiveViewTest, domain via DataCase).
- [ ] **F2** — `Ideas.list_ideas/1` con `[required: req, optional: opt]` ritorna idee secondo `(every required) AND (no optional OR ≥1 optional)`. Casi: solo required, solo optional, mix, vuoto.
- [ ] **F3** — `Ideas.list_ideas/0` invariato dalla slice 3: regression test `list_ideas() == list_ideas([])`.
- [ ] **F4** — Cycle ordine: off → optional → required → off; tre click consecutivi sullo stesso chip riportano allo stato iniziale.
- [ ] **F5** — `clear_filters` resetta solo `@filter_state`, non `@selected_category_ids` del form.
- [ ] **F6** — Empty result state mostra `Nessuna idea per i filtri attivi.` e il bottone `Mostra tutte`; chip restano renderizzati.
- [ ] **F7** — Refresh / re-mount → `@filter_state == %{}`.

### Accessibility
- [ ] **A1** — Ogni chip ha `aria-label` esattamente `<name>`, `<name> opzionale`, o `<name> obbligatoria` secondo lo stato.
- [ ] **A2** — Ogni chip ha `data-filter-state` esattamente `off`, `optional`, o `required`.
- [ ] **A3** — Cue visivo non-color (WCAG 1.4.11): off=no icon, optional=`<.icon name="hero-check" />`, required=2× check (decisione esatta in plan).
- [ ] **A4** — Live-region count: `<div role="status" aria-live="polite">{count} {idea|idee}</div>` aggiornato a ogni cambio filtro. Singolare/plurale italiano corretti.
- [ ] **A5** — Hit area chip ≥ 44×44 CSS px.
- [ ] **A6** — Tab order: dopo i chip dell'add-form (se aperto), i chip filter, poi `Mostra tutte`, poi la lista.

### Security / robustness
- [ ] **S1** — `cycle_filter` con id non-integer o non esistente → no-op. Test esplicito.
- [ ] **S2** — XSS regression: chip filter rendered con HEEx auto-escape.
- [ ] **S3** — `clear_filters` su filter già vuoto → idempotente, no-op.

### Operational / data
- [ ] **O1** — Nessuna nuova migration; nessun cambio di schema.
- [ ] **O2** — Performance: con scala 2-user (≤100 idee), query filtrata <50ms in test (sanity check).

### Validation venue
- [ ] **V1** — 4 screenshot mobile (iPhone 13 + Pixel 7 + 360px Pixel 4a): no filter, 1 chip optional, 1 required + 1 optional, empty result state.
- [ ] **V1a** — Lighthouse a11y mediana ≥95 su 3 run con filter mix.
- [ ] **V1b** — Keyboard-only walkthrough.

### Documentation
- [ ] **D1** — `docs/conventions.md` UI copy table aggiornata.

### UI copy aggiunta (canonical)

| Elemento | Testo IT |
|---|---|
| Bottone reset filtro | `Mostra tutte` |
| Empty state filter-no-match | `Nessuna idea per i filtri attivi.` |
| Aria-label chip off | `<nome>` |
| Aria-label chip optional | `<nome> opzionale` |
| Aria-label chip obbligatoria | `<nome> obbligatoria` |
| Live-region singolare | `1 idea` |
| Live-region plurale | `<N> idee` (incluso `0 idee`) |

## Consistency Gate

- [x] Intent is unambiguous
- [x] Every behavior has a corresponding BDD scenario
- [x] Architecture constrains without over-engineering
- [x] Terminology consistent (chip, filter, off/optional/required)
- [x] No contradictions between artifacts

**Verdict: PASS** — ready for `/plan`.
