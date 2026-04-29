# Spec: Budget on ideas + budget filter

> Slice 6 of the ideajar project. Adds an optional `estimated_cost`
> integer field to ideas (form + schema + migration) and a single-select
> 2-state cumulative budget filter alongside the slice-4 category and
> slice-5 duration filters. NULL-exclude semantics uniform with slice 5.
> Triggers two refactors: `Ideajar.Ideas.Filter` module extraction (R5-1)
> and `IdeajarWeb.Components.ChipBase` extraction (R5-2). **Removes the
> slice-4/5 filter-status live-region completely** as a deliberate UX
> decision.

## Intent Description

Slice 6 introduce il concetto **fascia di prezzo** sulle idee come campo
opzionale `:integer` in euro pieni (no centesimi), e aggiunge un filtro
cumulativo "fino a X" 2-state nella filter row sopra la lista delle
idee, accanto ai filtri categoria (slice 4) e durata (slice 5).

**Modello del prezzo**: per un'idea, il prezzo è uno tra:
- **non indicato** (`estimated_cost = nil`) — campo opzionale, default
- **gratis** (cost = 0)
- **fino a X€** dove X ∈ {20, 50, 100, 200, 500} (5 fasce intermedie)
- **oltre 1000€** (cost = 1000, fascia "molto caro")

**Form add-idea**: nuovo fieldset `Budget` sotto `Durata`, single-select
via 7 chip canonici con `aria-pressed`. I label sono descrittivi
(`gratis`, `fino a 20€`, …, `oltre 1000€`). DB stora l'integer del
bucket (0/20/50/100/200/500/1000). Click su chip già pressed = toggle off
(`@selected_cost → nil`). Bucket discreti per design — l'utente non può
inserire cifre arbitrarie come `175€`. Trade-off accettato: l'app è uno
strumento di scoperta-idee per una coppia, non contabilità; la
precisione del bucket è sufficiente.

**Lista idee**: filter row gains a third sub-block `Filtra per budget`
con **gli stessi 7 chip del form** (simmetrico), single-select 2-state
con semantica **cumulativa "fino a X"**: cliccando un chip si attiva il
filtro `WHERE estimated_cost <= ^value AND estimated_cost IS NOT NULL`.
Esempi:
- chip `gratis` (value 0): solo idee gratis (cost = 0)
- chip `fino a 20€` (value 20): gratis + fino-a-20 (cost ∈ {0, 20})
- chip `fino a 50€` (value 50): cost ∈ {0, 20, 50}
- … (cumulative)
- chip `oltre 1000€` (value 1000): tutte le idee con prezzo (qualsiasi
  bucket priced)

**NULL-exclude uniforme**: quando ≥1 chip budget è on, le idee con
`estimated_cost: nil` sono nascoste. Pattern **uniforme con slice 5
durata**. CONTEXT.md `Decisione su filtri non applicabili` rivista per
documentare il pattern unificato: filtri numerici/enum su campi
opzionali escludono i NULL quando attivi. Per filtri futuri (distanza
slice 7, search slice 8) la decisione resta da rivalutare ma il default
è NULL-exclude.

**Live-region filter-status RIMOSSO**: slice 6 elimina completamente il
`<div role="status" aria-live="polite" id="filter-status">` introdotto
in slice 4 ed esteso in slice 5. Decisione consapevole post-implementazione
slice 5: l'announce era percepito come noise. Conseguenze cascade:

- Compound suffix logic rimossa (slice 5 AA20).
- Action prefix logic (`<nome> opzionale,` ecc.) rimossa.
- `IdeajarWeb.Pluralization` helper diventa orphan → eliminato.
- Slice 4 acceptance A4/A16 e slice 5 A5/A13/AA9/AA20 → **deprecated**.
- Tutti i test slice 4/5 che asseriscono testo live-region → riscritti.

**Refactor R5-1 — `Ideajar.Ideas.Filter` modulo dedicato**: rule of 4
fires (required + optional + durations + max_cost). `apply_filters/2`
privata di `Ideajar.Ideas` (slice 5) viene estratta in
`Ideajar.Ideas.Filter.apply/2` come public function.

**Refactor R5-2 — `IdeajarWeb.Components.ChipBase` extraction**: 3°
chip family fires (BudgetChip dopo CategoryChip + DurationChip).
`chip_base_class/0` privata duplicata viene estratta in
`IdeajarWeb.Components.ChipBase`.

**3° rover RovingTabindex**: filter sub-block budget ha proprio
`phx-hook="RovingTabindex"` indipendente dai 2 rover di slice 4/5.

**Card idea**: nuovo budget badge accanto al duration badge (slice 5).
Label IT esattamente uguale al chip (`gratis`, `fino a 20€`, …,
`oltre 1000€`).

**Out of scope**: `lat/lng/location_name` e mappa (slice 7), filtro
distanza (slice 7), text search (slice 8), sort per costo, modifica
`estimated_cost` su idea esistente, valuta diversa da euro, custom
budget value (utente non può inserire `175€` — bucket only).

## User-Facing Behavior

```gherkin
Feature: Add a budget bucket to ideas and filter the list by max budget

  Background:
    Given my browser holds a valid signed session cookie
    And the workspace has the canonical 8 seeded categories
    And the workspace has these ideas:
      | title              | duration       | estimated_cost |
      | Caffè al volo      | poche_ore      | 0              |
      | Sirolo             | weekend        | 200            |
      | Uffizi             | giornata       | 50             |
      | Stadio             | mezza_giornata | 100            |
      | Parigi 4 giorni    | piu_giorni     | 1000           |
      | Bagno improvviso   | (NULL)         | (NULL)         |

  # ── Form: add idea with budget ──────────────────────────────────
  Scenario: Selecting a budget chip stores the bucket value on save
    Given the add-idea form is expanded with title "Test" and one category selected
    When I click the "fino a 100€" budget chip
    Then the chip has aria-pressed="true"
    When I click "Salva"
    Then a new idea is saved with estimated_cost 100

  Scenario: The "gratis" chip stores 0
    Given the form is open with title and one category set
    When I click "gratis" and "Salva"
    Then the new idea has estimated_cost 0

  Scenario: The "oltre 1000€" chip stores 1000
    Given the form is open
    When I click "oltre 1000€" and Salva
    Then the new idea has estimated_cost 1000

  Scenario: Toggling off the budget chip leaves estimated_cost NULL
    Given the form is open with "fino a 100€" pressed
    When I click "fino a 100€" again
    Then the chip is aria-pressed="false"
    When I click "Salva"
    Then the new idea has estimated_cost NULL

  Scenario: Submitting the form without a budget chip leaves estimated_cost NULL
    Given the form is open with title and one category, no budget chip pressed
    When I click "Salva"
    Then the new idea has estimated_cost NULL

  Scenario: Single-select swap on form chips
    Given the form is open with "fino a 100€" pressed
    When I click "fino a 200€"
    Then "fino a 200€" has aria-pressed="true"
    And "fino a 100€" has aria-pressed="false"

  Scenario: Submitting an out-of-whitelist budget is rejected
    When I dispatch save with estimated_cost "175"
    Then the form re-renders with error "Budget non valido"
    And the idea is not persisted

  Scenario: Submitting a non-numeric budget is rejected
    When I dispatch save with estimated_cost "abc"
    Then the form re-renders with error "Budget non valido"

  Scenario: Negative budget is rejected
    When I dispatch save with estimated_cost "-50"
    Then the form re-renders with error "Budget non valido"

  # ── Idea card: render budget badge ──────────────────────────────
  Scenario: Idea cards show a budget badge when estimated_cost is set
    When I visit "/"
    Then the "Sirolo" card shows a budget badge "fino a 200€"
    And the "Caffè al volo" card shows a budget badge "gratis"
    And the "Parigi 4 giorni" card shows a budget badge "oltre 1000€"
    And the "Bagno improvviso" card does not show a budget badge

  # ── Filter row: third sub-block ─────────────────────────────────
  Scenario: Filter row contains a Budget sub-block with exactly 7 chips
    When I visit "/"
    Then the filter row contains a sub-group with aria-label "Filtra per budget"
    And the budget sub-block has the visible sub-label "Budget"
    And it contains exactly 7 filter chips
    And the chips show "gratis", "fino a 20€", "fino a 50€", "fino a 100€", "fino a 200€", "fino a 500€", "oltre 1000€"

  Scenario: Filter row sub-block order
    When I visit "/"
    Then the filter row contains in DOM source order:
      | aria-label             |
      | Filtra per categoria   |
      | Filtra per durata      |
      | Filtra per budget      |

  Scenario: Helper text below the budget sub-block warns about NULL-exclude
    When I visit "/"
    Then the budget sub-block contains the text "Le idee senza prezzo sono nascoste quando un filtro è attivo."

  # ── Filter: cumulative single-select 2-state ───────────────────
  Scenario: Clicking the "gratis" filter shows only gratis ideas
    When I click the "gratis" budget filter chip
    Then "gratis" has data-budget-filter-state="on"
    And "gratis" has aria-label "gratis attiva"
    And the chip shows a check icon
    And I see "Caffè al volo" (cost 0)
    And I do not see any other idea

  Scenario: Clicking "fino a 20€" filter shows ideas up to 20€
    When I click the "fino a 20€" budget filter chip
    Then I see "Caffè al volo" (cost 0)
    And I do not see "Uffizi" (cost 50) or "Sirolo" (cost 200) or "Bagno improvviso" (NULL)

  Scenario: Clicking "fino a 100€" filter shows ideas up to 100€ cumulatively
    When I click the "fino a 100€" budget filter chip
    Then I see "Caffè al volo" (0), "Uffizi" (50), "Stadio" (100)
    And I do not see "Sirolo" (200) or "Parigi 4 giorni" (1000) or "Bagno improvviso" (NULL)

  Scenario: Clicking "oltre 1000€" filter shows all priced ideas
    When I click the "oltre 1000€" budget filter chip
    Then I see all 5 priced ideas (cost 0, 50, 100, 200, 1000)
    And I do not see "Bagno improvviso" (NULL)

  Scenario: Clicking a different budget chip swaps the cap (single-select)
    Given the budget filter has "fino a 100€" on
    When I click "fino a 50€"
    Then "fino a 50€" has data-budget-filter-state="on"
    And "fino a 100€" has data-budget-filter-state="off"

  Scenario: Clicking the active chip turns it off
    Given the budget filter has "fino a 100€" on
    When I click "fino a 100€" again
    Then "fino a 100€" has data-budget-filter-state="off"
    And no budget filter chip is on

  # ── NULL-exclude uniform with slice 5 duration ─────────────────
  Scenario: Ideas with NULL estimated_cost are hidden when any budget filter is active
    Given "Bagno improvviso" has estimated_cost NULL
    When I activate any budget filter chip
    Then I do not see "Bagno improvviso"

  Scenario: Ideas with NULL estimated_cost are visible when no budget filter is active
    When I visit "/"
    Then I see "Bagno improvviso"

  # ── Combined filter: 3 groups AND ───────────────────────────────
  Scenario: Triple combined filter applies AND across the three groups
    When I cycle category "viaggio" to required
    And I activate duration filter "weekend"
    And I activate budget filter "fino a 200€"
    Then I see "Sirolo"
    And I do not see "Parigi 4 giorni"
    # Sirolo: viaggio + weekend + cost 200 (≤ 200) → match
    # Parigi: viaggio yes + piu_giorni (≠ weekend) + cost 1000 (> 200) → out

  Scenario: Triple combined no-match shows the empty-result state
    Given the workspace has no idea matching all three filters
    When I activate filters with no matching idea
    Then I see "Nessuna idea per i filtri attivi."
    And I see a "Mostra tutte" button

  # ── Mostra tutte: resets all three filter groups ────────────────
  Scenario: Mostra tutte clears category + duration + budget filters
    Given category "mare" required, duration "weekend" on, budget "fino a 100€" on
    When I click "Mostra tutte"
    Then every category filter chip has data-filter-state="off"
    And every duration filter chip has data-duration-filter-state="off"
    And every budget filter chip has data-budget-filter-state="off"
    And I see all 6 ideas

  # ── Form/filter isolation ───────────────────────────────────────
  Scenario: Activating a budget filter does not touch the form chip
    Given the add-idea form is expanded with form budget "fino a 200€" pressed
    When I activate the budget filter "fino a 100€"
    Then the form "fino a 200€" chip is still aria-pressed="true"
    And the filter "fino a 100€" has data-budget-filter-state="on"

  Scenario: Mostra tutte does not touch the form budget selection
    Given the form is expanded with form budget "fino a 200€" pressed
    And the filter has budget "fino a 100€" on
    When I click "Mostra tutte"
    Then the form "fino a 200€" chip is still aria-pressed="true"
    And the budget filter is now off

  Scenario: Filter survives form submission
    Given budget filter "fino a 200€" is on
    When I open the form, set form budget "fino a 100€", submit a valid idea
    Then the budget filter "fino a 200€" is still on
    And the new idea (cost 100) is in the rendered list (matches ≤200)

  Scenario: New idea with cost above the active budget filter is hidden
    Given budget filter "fino a 50€" is on
    When I open the form, set form budget "fino a 200€", submit
    Then the new idea is created in DB but hidden in the list

  Scenario: New idea with NULL cost is hidden when budget filter is active
    Given budget filter "fino a 50€" is on
    When I submit a valid idea without selecting any budget chip
    Then the new idea (cost NULL) is created in DB but hidden in the list
    # NULL-exclude uniform with slice 5 duration

  # ── No live-region announcement (slice 6 removal) ───────────────
  Scenario: Filter changes produce no aria-live announcement
    When I activate the "fino a 100€" budget filter
    Then no element with role="status" exists in the rendered HTML
    And no element with aria-live="polite" exists in the filter row
    # Slice 6 removes the slice 4/5 filter-status live-region entirely.

  Scenario: Cycling a category filter no longer announces via aria-live
    When I cycle category "mare" to required
    Then no aria-live region updates with action prefix or count

  Scenario: Mostra tutte no longer announces "Filtri rimossi"
    Given any filter is on
    When I click "Mostra tutte"
    Then the page does not contain "Filtri rimossi" anywhere
    And no aria-live region announces the reset

  # ── Roving tabindex (third sub-block rover) ────────────────────
  Scenario: ArrowRight on a budget filter chip moves focus within the budget sub-group
    Given focus is on the "gratis" filter chip
    When I press ArrowRight
    Then focus moves to the "fino a 20€" filter chip
    And only the focused chip has tabindex="0" within the budget sub-group

  Scenario: ArrowRight wraps from the last to the first chip in the budget sub-group
    Given focus is on the "oltre 1000€" filter chip
    When I press ArrowRight
    Then focus moves to the "gratis" filter chip

  Scenario: Tab from inside the budget sub-group exits the rover
    Given focus is on a chip inside the budget filter sub-group
    When I press Tab
    Then focus moves out of the sub-group (next focusable element)

  # ── Form chip: no rover ────────────────────────────────────────
  Scenario: Form budget chips remain in standard tab order (no rover)
    Given the add-idea form is open
    When I press Tab from inside the form budget fieldset
    Then ArrowRight does not move focus among form budget chips
    And Tab moves to the next focusable form element

  # ── Hostile inputs ─────────────────────────────────────────────
  Scenario: toggle_budget_filter with non-numeric value is no-op
    When I dispatch toggle_budget_filter with cost "not-a-number"
    Then no filter state changes
    And the LV process does not crash

  Scenario: toggle_budget_filter with out-of-whitelist integer is no-op
    When I dispatch toggle_budget_filter with cost "175"
    Then no filter state changes

  Scenario: toggle_form_budget with hostile value is no-op
    When I dispatch toggle_form_budget with cost "<script>"
    Then form state unchanged

  # ── Out-of-scope guard ─────────────────────────────────────────
  Scenario: There is no other filter UI in slice 6
    When I visit "/"
    Then no element matches the texts "Distanza", "Cerca"
    # "Budget" is now legitimate (filter sub-block label, form fieldset legend, badge)

  # ── XSS regression (badge label) ───────────────────────────────
  Scenario: A malicious budget label is escaped on render
    Given a synthetic test fixture with budget label "<script>" injected via the badge component
    When I visit "/"
    Then the page does not execute the injected script
    And the badge text appears literally as escaped characters

  # ── Domain layer: list_ideas/1 with :max_cost opt ──────────────
  Scenario: Ideas.list_ideas/1 with :max_cost filters cumulatively with NULL-exclude
    When I call Ideas.list_ideas([max_cost: 100])
    Then I get all ideas with estimated_cost <= 100 AND estimated_cost IS NOT NULL

  Scenario: Ideas.list_ideas/1 with :max_cost 0 returns only gratis ideas
    When I call list_ideas([max_cost: 0])
    Then I get only ideas with estimated_cost == 0

  Scenario: Ideas.list_ideas/1 with :max_cost 1000 returns all priced ideas
    When I call list_ideas([max_cost: 1000])
    Then I get all ideas with estimated_cost IS NOT NULL

  Scenario: Ideas.list_ideas/1 with :max_cost nil is no-op (filter inactive)
    When I call list_ideas([max_cost: nil])
    Then every idea is returned (including NULL)

  Scenario: Ideas.list_ideas/1 combines all three filter clauses in AND
    When I call list_ideas([required: [@viaggio_id], durations: [:weekend], max_cost: 500])
    Then I get only ideas with viaggio AND weekend AND cost ≤ 500 AND cost IS NOT NULL

  Scenario: Ideas.list_ideas/0 still returns every idea
    When I call Ideas.list_ideas/0
    Then every idea is returned ordered by inserted_at DESC then id DESC

  # ── Refactor: Ideajar.Ideas.Filter module ─────────────────────
  Scenario: The filter logic lives in a dedicated module
    When I inspect the codebase
    Then Ideajar.Ideas.Filter module exists
    And it exports apply/2 :: (Ecto.Query.t, keyword) -> Ecto.Query.t
    And Ideajar.Ideas.list_ideas/1 delegates filter composition to Filter.apply/2

  # ── Refactor: ChipBase extraction ─────────────────────────────
  Scenario: Chip base class is shared across all chip families
    When I inspect the codebase
    Then IdeajarWeb.Components.ChipBase module exists with chip_base_class/0
    And CategoryChip, DurationChip, BudgetChip all reuse ChipBase.chip_base_class/0
    And no chip_base_class/0 private duplicate remains in any chip module
```

## Architecture Specification

### Components

| Componente | Tipo | Responsabilità |
|---|---|---|
| `Ideajar.Ideas.Idea` (esteso) | Schema Ecto | Aggiunge `field :estimated_cost, :integer`. Cast da string nel changeset; `nil` ammesso; whitelist guard via `validate_inclusion(:estimated_cost, Budget.values())` con custom error `"Budget non valido"`. |
| `Ideajar.Ideas.Budget` (nuovo) | Modulo puro | `values/0 :: [integer]` whitelist canonica `[0, 20, 50, 100, 200, 500, 1000]`. `parse/1 :: {:ok, integer} \| :error` cast string → int + whitelist check. `label/1 :: String.t()` (`0 → "gratis"`, `20-500 → "fino a <n>€"`, `1000 → "oltre 1000€"`). |
| `Ideajar.Ideas.Filter` (nuovo, R5-1 extraction) | Modulo puro | `apply/2 :: (Ecto.Query.t, keyword) -> Ecto.Query.t` compose le 4 clausole (required, optional, durations, max_cost). Public function. Helpers privati `apply_required/2`, `apply_optional/2`, `apply_durations/2`, `apply_max_cost/2`. Sostituisce `apply_filters/2` privata di `Ideajar.Ideas` (slice 5). |
| `Ideajar.Ideas` (esteso) | Context | `list_ideas/1` accetta nuova opt `max_cost: integer \| nil`. Body delega a `Filter.apply/2`. Helpers privati `apply_*` rimossi (estratti in `Filter`). |
| `IdeajarWeb.Components.ChipBase` (nuovo, R5-2 extraction) | Helper module | `chip_base_class/0` public function. Tutti e 3 i chip family riallineati. |
| `IdeajarWeb.Components.BudgetChip` (nuovo) | Function components | `form_chip/1` (single-select form, `aria-pressed`) + `filter_chip/1` (2-state filter, `aria-label` dinamico, `data-budget-filter-state`). DOM ids `form-budget-chip-<value>` / `filter-budget-chip-<value>`. Mutua esclusione type-level dei contracts. |
| `IdeajarWeb.IdeaLive.Index` (esteso + cleanup) | LiveView | Mount aggiunge `@selected_cost :: integer \| nil` (form) e `@cost_filter :: integer \| nil` (filter). Nuovi handler `toggle_form_budget`, `toggle_budget_filter`. `clear_filters` esteso. **Rimossi**: `@last_filter_action_prefix`, `@last_filter_action_suffix` (live-region removal). `cycle_filter`, `toggle_duration_filter`, `clear_filters` puliti dalla logic action prefix/suffix. |
| `IdeajarWeb.Pluralization` | (DELETED) | Rimosso. Slice 4 introdotto, slice 6 elimina (orphan post live-region removal). |
| Template `index.html.heex` (esteso + cleanup) | HEEx | Form: nuovo fieldset `Budget` con 7 chip dopo `Durata`. Filter row: nuovo sub-block `<div role="group" aria-label="Filtra per budget">` con sub-label visivo + helper text NULL-exclusion + 7 chip + 3° rover. Card idea: nuovo `<.budget_badge>` accanto a `<.duration_badge>`. **Rimosso**: `<div role="status" aria-live="polite" id="filter-status">`. |

### Interfaces

**Schema (esteso):**
```elixir
schema "ideas" do
  field :title, :string
  field :description, :string
  field :url, :string
  field :duration, Ecto.Enum, values: Duration.values()
  field :estimated_cost, :integer
  many_to_many :categories, Category, ...
  timestamps()
end
```

**Migration:**
```elixir
alter table(:ideas) do
  add :estimated_cost, :integer, null: true
end
```

**Domain API:**
```elixir
@spec list_ideas() :: [Idea.t()]
@spec list_ideas(opts :: keyword()) :: [Idea.t()]
  # opts:
  #   required: [integer]
  #   optional: [integer]
  #   durations: [atom]
  #   max_cost: integer | nil
  #     # NEW — estimated_cost ≤ max AND IS NOT NULL (NULL-exclude)
  #     # nil/missing = clausola inattiva (NULL-pass implicit)

defmodule Ideajar.Ideas.Budget do
  @spec values() :: [integer]    # [0, 20, 50, 100, 200, 500, 1000]
  @spec parse(any) :: {:ok, integer} | :error
  @spec label(integer) :: String.t()
    # 0 → "gratis"
    # 20-500 → "fino a 20€" / "fino a 50€" / "fino a 100€" / "fino a 200€" / "fino a 500€"
    # 1000 → "oltre 1000€"
end

defmodule Ideajar.Ideas.Filter do
  @spec apply(Ecto.Query.t(), keyword()) :: Ecto.Query.t()
end
```

**LiveView assigns (estesi):**
- `@selected_duration` (slice 5, invariato)
- `@selected_cost :: integer | nil` (NEW — form single-select)
- `@filter_state` (slice 4, invariato)
- `@duration_filter` (slice 5, invariato)
- `@cost_filter :: integer | nil` (NEW — filter single-select; integer non MapSet)
- ~~`@last_filter_action_prefix`~~ — **REMOVED** (slice 6 live-region delete)
- ~~`@last_filter_action_suffix`~~ — **REMOVED** (slice 6 live-region delete)

**LiveView events:**
- `cycle_filter` (slice 4) — refactor: rimossa logic action prefix/suffix.
- `toggle_form_duration` (slice 5) — invariato.
- `toggle_duration_filter` (slice 5) — refactor: rimossa logic action prefix/suffix.
- `toggle_form_budget` (NEW) con `%{"cost" => "<value>"}` — single-select form via `Budget.parse/1`. Toggle off se uguale; swap altrimenti.
- `toggle_budget_filter` (NEW) con `%{"cost" => "<value>"}` — 2-state single-select filter, semantica cumulativa "fino a X". Hostile/non-string/out-of-whitelist → no-op.
- `clear_filters` — esteso a `assign(:cost_filter, nil)`. Rimossa logic action prefix/suffix.

**Componenti:**
```elixir
# BudgetChip.form_chip/1
attr :cost, :integer, required: true, values: Budget.values()
attr :pressed?, :boolean, default: false

# BudgetChip.filter_chip/1
attr :cost, :integer, required: true, values: Budget.values()  # 7 valori (simmetrico)
attr :state, :atom, default: :off, values: [:off, :on]
attr :tabindex, :integer, default: -1
```

### Constraints

- **Budget optional**: `estimated_cost: nil` sempre valido lato schema, form, persistence.
- **NULL-exclude nel filtro**: `WHERE estimated_cost <= ^max AND estimated_cost IS NOT NULL`. Empty/nil opt = clausola inattiva. **Pattern uniforme con slice 5 durata**. CONTEXT.md `## Decisione su filtri non applicabili` rivista per documentare l'uniformità.
- **Filter chip count = 7, simmetrico al form**: niente asimmetria. `Budget.values/0` è la single-source whitelist sia per form sia per filter.
- **Single-select form + filter**: `@selected_cost :: integer | nil` e `@cost_filter :: integer | nil` (single int). Toggle off via clic su chip pressed; swap via clic su chip diverso.
- **Whitelist enforced**: `Budget.parse/1` single-source. Form changeset valida via `validate_inclusion(:estimated_cost, Budget.values())` con custom error `"Budget non valido"`.
- **Live-region filter-status RIMOSSO**: cascade dalla decisione UX. Conseguenze:
  - Slice 4 A4/A16 → deprecated, marker in conventions.md.
  - Slice 5 A5/A13/AA9/AA20 → deprecated, marker in conventions.md.
  - `IdeajarWeb.Pluralization` → deleted (orphan).
  - Tutti i test slice 4/5 che asseriscono live-region content → riscritti per asserire **assenza** del live-region.
- **Refactor R5-1 — `Ideajar.Ideas.Filter` extraction**: rule of 4 fires.
- **Refactor R5-2 — `IdeajarWeb.Components.ChipBase` extraction**: 3° chip family fires.
- **3° rover RovingTabindex**: filter sub-block budget ha `phx-hook="RovingTabindex"` `data-roving-tabindex-group="filter-budgets"`.
- **HEEx auto-escape** sul rendering del badge.
- **Hostile inputs**: handler con cost out-of-whitelist o non-numeric → no-op silenzioso. Save con cost manomessa → changeset error `"Budget non valido"`.
- **Backward compat**: `Ideas.list_ideas/0` invariato; `Ideas.list_ideas/1` con `max_cost: nil` invariato dalla slice 5.
- **A11y**: filter chip budget `<button>` con `aria-label` dinamico (`"<label>"` off / `"<label> attiva"` on); `data-budget-filter-state="off|on"`. Form chip `aria-pressed`. Hit area ≥ 44×44 (via `ChipBase`). Cue visivo non-color: off no icon, on `<.icon name="hero-check" />`.
- **Sub-group ARIA**: `<div role="group" aria-label="Filtra per budget">`. Sub-label visivo `Budget`. Helper text NULL-exclusion `Le idee senza prezzo sono nascoste quando un filtro è attivo.` sempre presente.

### Dependencies

Nessuna nuova dipendenza Hex.

### Out of scope

- `lat/lng/location_name` e mappa Leaflet (slice 7)
- Filtro distanza Haversine (slice 7)
- Text search (slice 8)
- Sort per `estimated_cost`
- Modifica `estimated_cost` su idea esistente
- Valuta diversa da euro (no localization)
- Custom budget value (utente NON può inserire `175€` — bucket only)
- Statistiche distribuzione costo

## Acceptance Criteria

### Functional / behavioral

- [ ] **F1** — Tutti gli scenari Gherkin automatabili passano (DataCase + LiveViewTest).
- [ ] **F2** — Schema: `Idea.changeset/2` accetta `estimated_cost` come stringa numerica, NULL ammesso, error `"Budget non valido"` per non-int o out-of-whitelist o negative.
- [ ] **F3** — Submit form senza budget chip → idea persistita con `estimated_cost: nil`.
- [ ] **F4** — Submit form con `gratis` → `estimated_cost: 0`.
- [ ] **F5** — Submit form con `oltre 1000€` → `estimated_cost: 1000`.
- [ ] **F6** — Single-select form: cliccando chip diverso, precedente ritorna a `aria-pressed="false"`.
- [ ] **F7** — Toggle off form: cliccando chip pressed, ritorna a `false` e `@selected_cost = nil`.
- [ ] **F8** — `Ideas.list_ideas([])` invariato dalla slice 5.
- [ ] **F9** — `Ideas.list_ideas([max_cost: 100])` ritorna `WHERE estimated_cost <= 100 AND IS NOT NULL`.
- [ ] **F10** — `Ideas.list_ideas([max_cost: 0])` ritorna solo idee con `cost = 0`.
- [ ] **F11** — `Ideas.list_ideas([max_cost: 1000])` ritorna tutte le idee priced (NULL escluse).
- [ ] **F12** — `Ideas.list_ideas([max_cost: nil])` ≡ no filter (idee con qualsiasi cost o NULL).
- [ ] **F13** — `Ideas.list_ideas([required: [_], durations: [_], max_cost: _])` combina in AND tra clausole (NULL-exclude per cost).
- [ ] **F14** — Filter chip 2-state cycle (off → on → off).
- [ ] **F15** — Filter single-select swap.
- [ ] **F16** — `clear_filters` resetta categoria + durata + budget; lascia intoccato form `@selected_cost`.
- [ ] **F17** — Idea card mostra budget badge solo quando `idea.estimated_cost != nil`.
- [ ] **F18** — Badge label esattamente uguale al chip label (`gratis`, `fino a 20€`, …, `oltre 1000€`).
- [ ] **F19** — Filter survives form submission.
- [ ] **F20** — New idea outside active budget filter is hidden (cost > max o cost NULL — entrambi nascosti).

### Filter row layout

- [ ] **L1** — Filter row contiene 3 sub-block in DOM source order: Categorie → Durata → Budget.
- [ ] **L2** — Filter chip budget count: esattamente 7 (simmetrico al form).
- [ ] **L3** — Form fieldset Budget contiene 7 chip.

### Accessibility

- [ ] **A1** — Form chip ha `aria-pressed="true|false"` corretto, derivato da `@selected_cost`.
- [ ] **A2** — Filter chip ha `aria-label` esattamente `<label>` (off) o `<label> attiva` (on). I label sono i 7 canonici (`gratis`, `fino a 20€`, …, `oltre 1000€`).
- [ ] **A3** — Filter chip ha `data-budget-filter-state` esattamente `off` o `on`.
- [ ] **A4** — Cue visivo non-color (WCAG 1.4.11): off = no icon, on = `<.icon name="hero-check" />`.
- [ ] **A5 (CRITICAL — slice 6 deprecation)** — **Live-region filter-status RIMOSSO** dal DOM. Verifica regression: `refute html =~ ~r/role="status"/` AND `refute html =~ ~r/aria-live="polite"/` scoped al filter row.
- [ ] **A6** — Roving tabindex budget: ArrowRight/ArrowLeft cycling within group (con wrap), Tab esce, primo chip `tabindex=0` altri `-1`.
- [ ] **A7** — Form chip budget: nessun rover, tab order standard.
- [ ] **A8** — Hit area chip ≥ 44×44 CSS px (via `ChipBase.chip_base_class/0`).
- [ ] **A9** — Sub-group ARIA: `<div role="group" aria-label="Filtra per budget">` con sub-label visivo `Budget`.
- [ ] **A10** — DOM id distinctness: `form-budget-chip-<value>`, `filter-budget-chip-<value>`. Distinct dai chip slice 3/4/5.
- [ ] **A11** — Helper text NULL-exclusion: filter row sub-block budget contiene sempre `Le idee senza prezzo sono nascoste quando un filtro è attivo.`

### Security / robustness

- [ ] **S1** — `toggle_budget_filter` con cost out-of-whitelist (`"175"`, `"-50"`) o non-numeric (`"abc"`, `""`) o non-string (42, [], %{}) → no-op silenzioso.
- [ ] **S2** — `toggle_form_budget` idem.
- [ ] **S3** — Save con `estimated_cost` manomessa via devtools/curl (`"abc"`, `"175"`, `"-50"`, `"<script>"`) → changeset error `"Budget non valido"`, idea non persistita.
- [ ] **S4** — `Budget.parse/1` non lancia su input arbitrari.
- [ ] **S5** — XSS regression badge: `Budget.label/1` hard-coded da modulo, no path injection. Test sintetico via mock label.
- [ ] **S6** — Mutua esclusione type-level dei due ARIA contracts in `BudgetChip`: `form_chip/1` non accetta `state`, `filter_chip/1` non accetta `pressed?`.
- [ ] **S7** — `clear_filters` è idempotente quando tutti i filtri sono già off (nessun error, nessun state change).

### Operational / data

- [ ] **O1** — Migration `AddEstimatedCostToIdeas` reversibile loss-free pre-popolamento. SQLite `ALTER TABLE ADD COLUMN estimated_cost INTEGER`. Test roundtrip + data preservation across rollback (parallelo slice 5 step 2 B3 fix).
- [ ] **O2** — `Ecto.Adapters.SQL.to_sql/2` su `list_ideas([max_cost: 100])` → SQL contiene `~r/"estimated_cost"\s+<=/i` AND `~r/IS\s+NOT\s+NULL/i` (NULL-exclude pinned).
- [ ] **O3** — Performance sanity: list_ideas con 4 filter attivi <100ms su 100 idee.
- [ ] **O4** — `Ideajar.Ideas.Filter.apply/2` testato indipendentemente con unit test su ogni clausola (4 clausole isolate + composizione).

### Refactor (R5-1, R5-2)

- [ ] **R1** — `Ideajar.Ideas.Filter` modulo esiste, esporta `apply/2`.
- [ ] **R2** — `Ideajar.Ideas.list_ideas/1` delega filter chain a `Filter.apply/2` (no più `apply_filters/2` privata).
- [ ] **R3** — Tutti i test slice 4/5 list_ideas/1 passano invariati (regression).
- [ ] **R4** — `IdeajarWeb.Components.ChipBase` modulo esiste con `chip_base_class/0` public.
- [ ] **R5** — `CategoryChip`, `DurationChip`, `BudgetChip` riusano `ChipBase.chip_base_class/0` (no `defp chip_base_class` duplicato).

### Live-region deprecation (slice 6)

- [ ] **D-LR1** — `<div role="status" aria-live="polite" id="filter-status">` assente dal DOM in `index.html.heex`.
- [ ] **D-LR2** — `IdeajarWeb.Pluralization` modulo eliminato (file rimosso).
- [ ] **D-LR3** — `@last_filter_action_prefix` e `@last_filter_action_suffix` assigns rimossi da `IdeajarWeb.IdeaLive.Index`.
- [ ] **D-LR4** — Handler `cycle_filter`, `toggle_duration_filter`, `clear_filters` puliti da logic action prefix/suffix.
- [ ] **D-LR5** — Test slice 4/5 che asserivano live-region content → riscritti come "no live-region present" o eliminati.

### Validation venue

- [ ] **V1** — Screenshot mobile (iPhone 13 + Pixel 7 + 360px Pixel 4a): form con budget chip, filter row 3 sub-block, idea card con badge budget+duration, empty-result combinato.
- [ ] **V1a** — Lighthouse a11y mediana ≥95.
- [ ] **V1b** — Keyboard-only walkthrough: 3 rover indipendenti, form chip Tab order, no live-region announcement.

### Documentation

- [ ] **D1** — `docs/conventions.md` UI copy table aggiornata con stringhe slice 6.
- [ ] **D2** — `docs/conventions.md` aggiorna le tabelle slice 4 e slice 5 per **deprecare** le stringhe live-region (action prefix on/off, count, compound suffix).
- [ ] **D3** — `CONTEXT.md` aggiornato: `## Decisione su filtri non applicabili` esteso per documentare l'uniformità NULL-exclude pattern (slice 5 durata + slice 6 budget).
- [ ] **D4** — `test/ideajar_web/live/idea_live/index_test.exs`: out-of-scope guard regex aggiornato (rimuove `Budget`; conserva `Distanza`, `Cerca`).
- [ ] **D5** — `test/ideajar/docs_test.exs`: nuova `describe "slice-6 UI copy"` con stringhe canoniche + nuova `describe "live-region deprecation"` che asserisce assenza degli strings.

### UI copy aggiunta (canonical)

| Elemento | Testo IT |
|---|---|
| Label fieldset budget (form) | `Budget` (no asterisco — opzionale) |
| Helper text form budget | (nessuno — campo opzionale) |
| Chip budget 1 (value 0) | `gratis` |
| Chip budget 2 (value 20) | `fino a 20€` |
| Chip budget 3 (value 50) | `fino a 50€` |
| Chip budget 4 (value 100) | `fino a 100€` |
| Chip budget 5 (value 200) | `fino a 200€` |
| Chip budget 6 (value 500) | `fino a 500€` |
| Chip budget 7 (value 1000) | `oltre 1000€` |
| Errore budget invalido | `Budget non valido` |
| Sub-label filter Budget (visivo) | `Budget` |
| Aria-label sub-block budget (SR) | `Filtra per budget` |
| Helper text NULL-exclusion | `Le idee senza prezzo sono nascoste quando un filtro è attivo.` |
| Aria-label filter chip off | `<label>` (es. `gratis`, `fino a 100€`, `oltre 1000€`) |
| Aria-label filter chip on | `<label> attiva` (es. `gratis attiva`, `fino a 100€ attiva`, `oltre 1000€ attiva`) |
| Badge budget su idea card | `<label>` (uguale al chip label) |

### UI copy deprecata (slice 6 live-region removal)

| Elemento (slice 4/5) | Testo IT (storico) | Status slice 6 |
|---|---|---|
| Live-region action prefix optional (slice 4) | `<nome> opzionale, ` | DEPRECATED — non più renderizzato |
| Live-region action prefix required (slice 4) | `<nome> obbligatoria, ` | DEPRECATED |
| Live-region action prefix off (slice 4) | `<nome> rimossa, ` | DEPRECATED |
| Live-region prefix clear (slice 4) | `Filtri rimossi, ` | DEPRECATED |
| Live-region count singolare (slice 4) | `1 idea` | DEPRECATED — Pluralization deleted |
| Live-region count plurale (slice 4) | `<N> idee` | DEPRECATED |
| Live-region duration prefix on (slice 5) | `<label> attiva, ` | DEPRECATED |
| Live-region duration prefix off (slice 5) | `<label> rimossa, ` | DEPRECATED |
| Live-region compound suffix categoria (slice 5) | `, filtri categoria attivi` | DEPRECATED |
| Live-region compound suffix durata (slice 5) | `, filtri durata attivi` | DEPRECATED |

## Consistency Gate

- [x] Intent unambiguo — NULL-exclude uniform e live-region removal sono entrambi esplicitati con razionale
- [x] Ogni behavior ha BDD scenario corrispondente
- [x] Architecture constrains without over-engineering — 3 module extractions sono tutte rule-triggered da slice 5 R-lines
- [x] Termini consistenti (chip, filter, "fino a X", NULL-exclude, deprecation)
- [x] No contradictions — NULL-exclude uniform è documentato, slice 5 R5-14 (NULL-pass per budget) è chiuso a favore di NULL-exclude

**Verdict: PASS** — ready for `/plan`.
