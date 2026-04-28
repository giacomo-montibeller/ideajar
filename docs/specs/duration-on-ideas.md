# Spec: Duration on ideas + duration filter

> Slice 5 of the ideajar project. Adds an optional `duration` enum field to
> ideas (form + schema + migration) and a 2-state duration filter row
> alongside the existing slice-4 category filter. Introduces roving
> tabindex on the filter row (R5 of slice 4 trigger fires).

## Intent Description

Slice 5 introduce il concetto **durata stimata** di un'idea come campo
opzionale a 5 valori canonici (`poche_ore`, `mezza_giornata`, `giornata`,
`weekend`, `piu_giorni`), e aggiunge un filtro durata 2-state sopra la
lista delle idee, accanto al filtro categoria già esistente (slice 4).

**Form add-idea**: nuovo fieldset `Durata` sotto `Categorie`,
single-select via 5 chip con `aria-pressed`. Click su chip già pressed =
toggle off (`duration → nil`). Durata è opzionale: il form si submitta
anche senza selezione, l'idea viene salvata con `duration: nil`.

**Lista idee**: filter row riorganizzata in un singolo
`<section aria-label="Filtra per:">` con due sub-blocchi labellati
`Categorie` e `Durata` (role=group + aria-label). Filtro durata è
2-state per chip (off → on → off), OR implicito tra chip selezionati.
Combina in AND con il filtro categoria già presente.

**Idee con `duration: nil`** sono nascoste quando ≥1 chip durata è on
(decisione UX divergente da `CONTEXT.md` riga 81: chi filtra per durata
sta cercando attivamente idee di una specifica durata, quindi un'idea
senza durata stimata non rientra nel match). Quando nessun chip durata è
on, le idee NULL passano (filtro inattivo). `CONTEXT.md` viene
aggiornato come parte di questa slice (chiude la "Decisione UX aperta"
lato durata; per i filtri futuri di slice 6-7 la decisione sarà
rivalutata caso per caso).

**Roving tabindex**: introdotto come step 1 della slice. Due rover
indipendenti nella filter row (uno per Categorie, uno per Durata):
ArrowLeft/ArrowRight navigano in gruppo, Tab esce. Form chip restano
sequenziali (apertura singola del form, l'utente compila e submit).

**Backend**: `Ideas.list_ideas/1` esteso con `durations: [atom]` (terza
filter clause). Rule of 3 fires → REFACTOR step estrae `apply_filters/2`
come funzione privata in `Ideajar.Ideas` (no nuovo modulo dedicato).

**Card idea**: nuovo badge durata accanto ai badge categoria quando
`duration` non è nil.

**Out of scope**: `estimated_cost` e budget slider (slice 6),
`lat/lng/location_name` e mappa (slice 6/7), filtro distanza (slice 7),
text search (slice 8), sort per durata, modifica `duration` su idea
esistente, `Ideajar.Ideas.Filter` modulo dedicato (rinviato), URL
params / deep-link.

## User-Facing Behavior

```gherkin
Feature: Add a duration to ideas and filter the list by duration

  Background:
    Given my browser holds a valid signed session cookie
    And the workspace has the canonical 8 seeded categories
    And the workspace has these ideas:
      | title             | categories       | duration       |
      | Caffè al volo     | passeggiata      | poche_ore      |
      | Sirolo            | mare, viaggio    | weekend        |
      | Uffizi            | museo, cultura   | giornata       |
      | Stadio            | sport            | mezza_giornata |
      | Parigi 4 giorni   | viaggio, cultura | piu_giorni     |
      | Bagno improvviso  | mare             |                |

  # ── Form: add idea with duration ─────────────────────────────────
  Scenario: Selecting a duration chip stores the duration on save
    Given the add-idea form is expanded with title "Test" and one category selected
    When I click the "weekend" duration chip
    Then the chip has aria-pressed="true"
    And no other duration chip has aria-pressed="true"
    When I click "Salva"
    Then a new idea is saved with duration "weekend"

  Scenario: Selecting and unselecting a duration chip leaves duration NULL
    Given the add-idea form is expanded with title "Test" and one category selected
    When I click the "weekend" duration chip
    And I click the "weekend" chip again
    Then "weekend" has aria-pressed="false"
    And no duration chip has aria-pressed="true"
    When I click "Salva"
    Then a new idea is saved with duration NULL

  Scenario: Submitting the form without selecting any duration chip leaves duration NULL
    Given the add-idea form is expanded with title "Test" and one category selected
    And no duration chip is pressed
    When I click "Salva"
    Then a new idea is saved with duration NULL

  Scenario: Selecting a different duration chip swaps the selection (single-select enforcement)
    Given the add-idea form is expanded with the "weekend" duration chip pressed
    When I click "giornata"
    Then "giornata" has aria-pressed="true"
    And "weekend" has aria-pressed="false"

  Scenario: Submitting an invalid duration string is rejected with the canonical error
    When I dispatch a save event with duration "schifoso"
    Then the form re-renders with error "Durata non valida"
    And the idea is not persisted

  # ── Idea card: render duration badge ────────────────────────────
  Scenario: Idea cards show a duration badge when duration is set
    When I visit "/"
    Then the "Sirolo" card shows a duration badge "weekend"
    And the "Bagno improvviso" card does not show a duration badge

  # ── Filter row: two sub-blocks ──────────────────────────────────
  Scenario: Visiting / shows the filter row with both Categorie and Durata sub-blocks
    When I visit "/"
    Then the filter row has aria-label "Filtra per:"
    And it contains a sub-group with aria-label "Filtra per categoria" containing 8 filter chips
    And it contains a sub-group with aria-label "Filtra per durata" containing 5 filter chips
    And the categorie sub-block shows the visible sub-label "Categorie"
    And the durata sub-block shows the visible sub-label "Durata"
    And every duration filter chip has data-duration-filter-state="off"

  # ── Filter: 2-state cycle ───────────────────────────────────────
  Scenario: Clicking a duration filter chip cycles off → on → off
    When I click the "weekend" duration filter chip
    Then "weekend" has data-duration-filter-state="on"
    And "weekend" has aria-label "weekend attiva"
    And the chip shows a check icon
    When I click "weekend" again
    Then "weekend" has data-duration-filter-state="off"
    And "weekend" has aria-label "weekend"
    And the chip shows no check icon

  # ── Filter: matching ─────────────────────────────────────────────
  Scenario: One duration chip filters to ideas with that duration
    When I activate the "weekend" duration filter
    Then I see "Sirolo"
    And I do not see "Caffè al volo", "Uffizi", "Stadio", "Parigi 4 giorni", "Bagno improvviso"

  Scenario: Multiple duration chips form an OR
    When I activate "weekend" and "giornata" duration filters
    Then I see "Sirolo" and "Uffizi"
    And I do not see "Bagno improvviso"

  # ── NULL exclusion (closes CONTEXT.md "Decisione UX aperta") ────
  Scenario: Ideas with NULL duration are hidden when any duration filter is active
    Given "Bagno improvviso" has duration NULL
    When I activate the "weekend" duration filter
    Then I do not see "Bagno improvviso"

  Scenario: Ideas with NULL duration are visible when no duration filter is active
    When I visit "/"
    Then I see "Bagno improvviso"

  # ── Combined: duration × category filters ───────────────────────
  Scenario: Duration filter combines with category filter as AND
    When I cycle category "viaggio" to required
    And I activate the "weekend" duration filter
    Then I see "Sirolo"
    And I do not see "Parigi 4 giorni"
    # ↑ Parigi has viaggio but duration=piu_giorni, not weekend

  Scenario: Combined filter with no match shows the empty-result state
    Given the workspace has no idea with category "passeggiata" AND duration "weekend"
    When I cycle category "passeggiata" to required
    And I activate the "weekend" duration filter
    Then I see "Nessuna idea per i filtri attivi."
    And I see "Mostra tutte"

  # ── Live-region count ───────────────────────────────────────────
  Scenario: Activating the duration filter updates the live-region with action and count
    Given I am on "/"
    When I activate the "weekend" duration filter
    Then the live-region announces "weekend attiva, 1 idea"
    When I activate "giornata"
    Then the live-region announces "giornata attiva, 2 idee"
    When I deactivate "weekend"
    Then the live-region announces "weekend rimossa, 1 idea"

  Scenario: Live-region appends compound-state suffix when both filter groups are active
    Given the category filter has "mare" required
    When I activate the "weekend" duration filter
    Then the live-region announces "weekend attiva, 1 idea, filtri categoria attivi"
    When I cycle category "sport" to optional
    Then the live-region announces "sport opzionale, 2 idee, filtri durata attivi"
    When I click "Mostra tutte"
    Then the live-region announces "Filtri rimossi, 6 idee"
    # ↑ Filtri rimossi never has a suffix (both groups now empty)

  # ── Helper text discoverability (NULL exclusion) ────────────────
  Scenario: Filter sub-block durata always shows the NULL-exclusion helper
    When I visit "/"
    Then the duration filter sub-block contains the text "Le idee senza durata sono nascoste quando un filtro è attivo."
    When I activate the "weekend" duration filter
    Then the helper text is still rendered

  # ── Empty state with duration filter ─────────────────────────────
  Scenario: Duration filter matching zero ideas shows the empty-result state
    Given the workspace has no ideas with duration "piu_giorni" except "Parigi 4 giorni"
    And "Parigi 4 giorni" is removed
    When I activate the "piu_giorni" duration filter
    Then I see "Nessuna idea per i filtri attivi."
    And the duration filter chip row remains rendered
    And "piu_giorni" still has data-duration-filter-state="on"

  Scenario: "Mostra tutte" resets both category and duration filters
    Given I have category "mare" required and duration "weekend" active
    When I click "Mostra tutte"
    Then every category filter chip has data-filter-state="off"
    And every duration filter chip has data-duration-filter-state="off"
    And I see all 6 ideas
    And the live-region announces "Filtri rimossi, 6 idee"

  # ── Form vs filter state isolation ───────────────────────────────
  Scenario: Resetting filters does not touch the form duration selection
    Given the add-idea form is expanded with form duration "weekend" pressed
    And the duration filter has "giornata" active
    When I click "Mostra tutte"
    Then the form duration "weekend" chip is still aria-pressed="true"
    And the filter "giornata" has data-duration-filter-state="off"

  Scenario: Activating a filter chip does not touch the form chip selection
    Given the add-idea form is expanded with form duration "weekend" pressed
    When I activate the duration filter "giornata"
    Then the form "weekend" chip is still aria-pressed="true"
    And the filter "giornata" has data-duration-filter-state="on"

  # ── Persistence (LV-session only) ────────────────────────────────
  Scenario: Refresh resets the duration filter
    Given I have duration "weekend" active
    When I reload "/"
    Then every duration filter chip has data-duration-filter-state="off"

  # ── Hostile inputs (defense-in-depth) ────────────────────────────
  Scenario: toggle_duration_filter with an unknown duration string is a no-op
    When I dispatch toggle_duration_filter with duration "supercalifragilistic"
    Then no filter state changes
    And the LV process does not crash

  Scenario: toggle_duration_filter with a non-string payload is a no-op
    When I dispatch toggle_duration_filter with duration 42
    Then no filter state changes

  Scenario: Form save with a duration outside the whitelist is rejected
    When I dispatch save with duration "<script>"
    Then the form re-renders with error "Durata non valida"
    And no idea is persisted

  # ── Roving tabindex ──────────────────────────────────────────────
  Scenario: ArrowRight on a category filter chip moves focus within the category sub-group
    Given focus is on the "passeggiata" filter chip
    When I press ArrowRight
    Then focus moves to the "mare" filter chip
    And only the focused chip has tabindex="0" within the category sub-group

  Scenario: ArrowRight wraps from the last to the first chip in a sub-group
    Given focus is on the last duration filter chip ("piu_giorni")
    When I press ArrowRight
    Then focus moves to the first duration filter chip ("poche_ore")

  Scenario: ArrowLeft from the first chip wraps to the last
    Given focus is on the first category filter chip ("passeggiata")
    When I press ArrowLeft
    Then focus moves to the last category filter chip ("viaggio")

  Scenario: Tab from inside the category sub-group moves to the duration sub-group entry chip
    Given focus is on a chip inside the category filter sub-group
    When I press Tab
    Then focus moves to the duration sub-group's tab-stop chip
    # Two separate rovers; Tab traverses between sub-groups, arrows within

  Scenario: Form chip keyboard navigation remains sequential (Tab, no rover)
    Given the add-idea form is expanded
    When I press Tab from inside the form's category fieldset
    Then focus moves to the next form field via Tab order
    And ArrowRight on a form chip does not move focus

  # ── Slice 4 regression ──────────────────────────────────────────
  Scenario: Ideas.list_ideas/1 with no opts still returns every idea
    When I call Ideas.list_ideas([])
    Then every idea is returned ordered by inserted_at DESC then id DESC

  Scenario: Ideas.list_ideas/1 combines category and duration filters in AND
    When I call list_ideas([required: [@mare_id], durations: [:weekend]])
    Then I get only ideas with mare AND duration=weekend

  Scenario: Ideas.list_ideas/1 with empty durations list does not exclude NULL
    When I call list_ideas([durations: []])
    Then I get every idea, including those with NULL duration
    # Empty list = filter inactive; equivalent to omitting the opt

  # ── Out-of-scope guard ──────────────────────────────────────────
  Scenario: There is no other filter UI in slice 5
    When I visit "/"
    Then no element matches the texts "Budget", "Distanza", "Cerca"
    # Note: "Durata" is now valid and must be present in the filter row

  # ── XSS regression ──────────────────────────────────────────────
  Scenario: A malicious duration label is escaped on render
    Given a synthetic test fixture with duration label "<script>" injected via the badge component
    When I visit "/"
    Then the page does not execute the injected script
    And the badge text appears literally as escaped characters
```

## Architecture Specification

### Components

| Componente | Tipo | Responsabilità |
|---|---|---|
| `Ideajar.Ideas.Idea` (esteso) | Schema Ecto | Aggiunge `field :duration, Ecto.Enum, values: [:poche_ore, :mezza_giornata, :giornata, :weekend, :piu_giorni]`. Cast da string nel changeset; `nil` ammesso. |
| `Ideajar.Ideas.Duration` (nuovo) | Modulo puro | `values/0 :: [atom]` whitelist canonica. `parse/1 :: {:ok, atom} \| :error` (no raise, usa `to_existing_atom`). `label/1 :: String.t()` per UI IT (`:poche_ore → "poche ore"`, `:piu_giorni → "più giorni"`, ecc.). Single source of truth per form, filter, hostile-input handler. |
| `Ideajar.Ideas` (esteso) | Context | `list_ideas/1` accetta nuova opt `durations: [atom]`. Refactor (REFACTOR step finale): estratta `apply_filters/2` privata che compone le 3 clausole (required, optional, durations). `change_idea/2` accetta `duration` come stringa e la cast via Ecto.Enum. |
| `IdeajarWeb.IdeaLive.Index` (esteso) | LiveView | Mount aggiunge `@duration_filter :: MapSet.t(atom)` (default vuoto) e `@selected_duration :: atom \| nil` per il form. Nuovi handler: `toggle_duration_filter` (parse via `Duration.parse/1`, no-op su error), `toggle_form_duration` (single-select enforcement). `clear_filters` (esistente) esteso a resettare anche `@duration_filter`. Live-region prefix esteso (`weekend attiva, …`, `weekend rimossa, …`). |
| `IdeajarWeb.Components.DurationChip` (nuovo) | Function components | Due funzioni distinte (mutual exclusion ARIA contracts): `form_chip/1` con `aria-pressed`, `filter_chip/1` con `aria-label` dinamico + `data-duration-filter-state`. |
| `IdeajarWeb.Hooks.RovingTabindex` (nuovo, JS) | LiveView hook | Hook su contenitore con `data-roving-tabindex-group="<id>"`: intercetta ArrowLeft/ArrowRight e sposta `tabindex` (0 sul focused, -1 sugli altri); wrap aritmetico last↔first; Home/End ai bordi. Tab non intercettato. |
| Template `index.html.heex` (esteso) | HEEx | Filter row: due `<div role="group" aria-label="Filtra per categoria/durata">` annidati nella section `Filtra per:`, ognuno con il proprio `phx-hook="RovingTabindex"`. Sub-label visivo `Categorie`/`Durata` come `<p class="text-xs">`. Sub-block durata include sempre helper text `Le idee senza durata sono nascoste quando un filtro è attivo.` Form: nuovo fieldset `Durata` sotto `Categorie`. Card idea: nuovo `<.duration_badge :if={idea.duration}>` accanto alla `<ul aria-label="Categorie">`. |

### Interfaces

**Schema (esteso):**
```elixir
schema "ideas" do
  field :title, :string
  field :description, :string
  field :url, :string
  field :duration, Ecto.Enum,
    values: [:poche_ore, :mezza_giornata, :giornata, :weekend, :piu_giorni]
  many_to_many :categories, Category, ...
  timestamps()
end
```

**Migration:**
```elixir
alter table(:ideas) do
  add :duration, :string, null: true
end
# SQLite stores Ecto.Enum as TEXT. No backfill required.
# Reversibility: down drops the column (loss-free pre-popolamento;
# documentato che rollback post-popolamento perde dati).
```

**Domain API:**
```elixir
@spec list_ideas() :: [Idea.t()]
@spec list_ideas(opts :: keyword()) :: [Idea.t()]
  # opts:
  #   required: [integer]   # categorie tutte presenti (slice 4)
  #   optional: [integer]   # almeno una categoria presente (slice 4)
  #   durations: [atom]     # NEW — duration ∈ list; NULL escluso quando non vuoto
  # Empty list per ogni opt = clausola inattiva.

defmodule Ideajar.Ideas.Duration do
  @spec values() :: [atom]
  @spec parse(any) :: {:ok, atom} | :error
  @spec label(atom) :: String.t()
end
```

**LiveView assigns (estesi):**
- `@filter_state :: %{integer => :optional | :required}` (slice 4, invariato)
- `@duration_filter :: MapSet.t(atom)` — id assenti = off; reset on `clear_filters`, refresh, mount
- `@selected_duration :: atom | nil` — single-select state del form, separato da `@selected_category_ids`
- `@last_filter_action :: String.t()` (slice 4, esteso a frasi durata)

**LiveView events:**
- `cycle_filter` (slice 4, invariato)
- `toggle_duration_filter` con `%{"duration" => "<value>"}` — toggle in `@duration_filter`; whitelist via `Duration.parse/1`; unknown/non-string = no-op silenzioso
- `toggle_form_duration` con `%{"duration" => "<value>"}` — single-select enforcement: se `@selected_duration == parsed`, imposta a `nil`; altrimenti imposta a `parsed`. Unknown = no-op
- `clear_filters` (slice 4, esteso): resetta sia `@filter_state` sia `@duration_filter`. Non tocca `@selected_duration` (form state).

**Componenti:**
```elixir
# DurationChip.form_chip/1 — single-select, aria-pressed
attr :duration, :atom, required: true, values: ...
attr :pressed?, :boolean, default: false
# Renders <button aria-pressed={...} phx-click="toggle_form_duration"
#         phx-value-duration={duration}>{label}</button>

# DurationChip.filter_chip/1 — 2-state, aria-label dinamico
attr :duration, :atom, required: true, values: ...
attr :state, :atom, default: :off, values: [:off, :on]
attr :tabindex, :integer, default: -1
# Renders <button aria-label={dynamic} data-duration-filter-state={state}
#         tabindex={...} phx-click="toggle_duration_filter"
#         phx-value-duration={duration}>{label}{:check_icon if on}</button>
```

### Constraints

- **Duration optional**: `duration: nil` sempre valido lato schema, form, persistence.
- **NULL exclusion in filter**: quando `durations:` opt è non-vuota, `WHERE duration IN (^selected)` (no `OR NULL`). Decisione consapevole: chi filtra per durata sta restringendo attivamente; un'idea senza durata non è "sicuramente non weekend", ma **non confermata weekend**, quindi esclusa. Empty list o opt omessa = clausola inattiva, NULL passa.
- **CONTEXT.md update**: `CONTEXT.md` riga 80-81 ("Decisione UX aperta" su filtri non applicabili) viene aggiornato in questa slice. Per `duration` la regola è "NULL escluso quando filtro attivo". Per altri filtri futuri (estimated_cost, distanza) la decisione resta da rivalutare slice per slice.
- **Whitelist enforced via existing atoms**: `Duration.parse/1` è il single-source-of-truth. Usa `String.to_existing_atom/1` (sicuro: tutti i 5 atom canonici sono compilati nel modulo `Duration`).
- **Single-select form**: enforcement lato server in `toggle_form_duration`; il chip form non garantisce single-select via HTML (è un button, non un radio). Il render derivato da `@selected_duration` rende solo uno chip pressed=true alla volta.
- **Toggle off form**: clic su chip già pressed → `@selected_duration = nil` → chip torna a pressed=false. Permette undo senza un'affordance "clear" separata.
- **Filter is read-only**: 4 filtri attivi possibili (categoria-required, categoria-optional, durata, e in slice 4 anche `clear_filters`). Componibili in AND tra tipi.
- **Two rovers, not one**: Categoria-filter rover indipendente dal Durata-filter rover. Tab attraversa i due gruppi; frecce navigano in gruppo. Form chip restano nel tab order standard (no rover).
- **`apply_filters/2` privata, no nuovo modulo**: rule of 3 (required + optional + durations) fires, ma `Ideajar.Ideas.Filter` modulo dedicato è premature module-itis per la scala attuale. Estrazione a modulo se slice 6+ aggiunge altri filtri (rule of 4).
- **HEEx auto-escape** sul rendering del badge durata e del chip label.
- **Hostile inputs**: `toggle_duration_filter` e `toggle_form_duration` con duration fuori whitelist o non-string → no-op silenzioso. Save con duration manomessa via devtools/curl → changeset error `"Durata non valida"`.
- **Backward compat slice 4**: `Ideas.list_ideas/0` invariato; `Ideas.list_ideas/1` con `durations: nil/[]` o opt assente → comportamento slice-4 invariato (NULL passa, filtro inattivo).
- **A11y**: filter chip durata `<button>` con `aria-label` dinamico (`"weekend"` / `"weekend attiva"`); `data-duration-filter-state="off|on"`. Form chip durata `<button>` con `aria-pressed="true|false"`. Hit area ≥ 44×44 CSS px (riuso classi slice 3/4). Cue visivo non-color (WCAG 1.4.11): off = no icon, on = `<.icon name="hero-check" />`.
- **Sub-group ARIA**: `<div role="group" aria-label="Filtra per categoria">` e `<div role="group" aria-label="Filtra per durata">` come ancore screen-reader dentro `<section aria-label="Filtra per:">`. Aria-label esplicitamente disambiguato per non collidere con `<legend>Durata</legend>` del form fieldset (altrimenti SR sentirebbe "Durata" twice in close proximity con context ambiguo). Sub-label visivo (`<p class="text-xs">Categorie</p>`, `<p class="text-xs">Durata</p>`) resta breve per economia visiva.
- **Helper text NULL-exclusion**: il filter sub-block durata renderizza sempre (anche con filtro inattivo) il testo statico `Le idee senza durata sono nascoste quando un filtro è attivo.` come `<p class="text-xs text-base-content/70">` sotto il sub-label e sopra il chip group. Risolve il "NULL exclusion undiscoverable" gap.
- **Live-region compound-state**: quando l'azione corrente è su un gruppo e l'altro gruppo ha ≥1 filtro attivo, il prefix è seguito da `, filtri categoria attivi` o `, filtri durata attivi`. `Filtri rimossi` non ha mai suffix. Esempi: `weekend attiva, 1 idea` (solo durata) vs `weekend attiva, 1 idea, filtri categoria attivi` (compound).

### Dependencies

Nessuna nuova dipendenza Hex. Hook `RovingTabindex` è codice locale in
`assets/js/`.

### Out of scope

- `estimated_cost` e budget filter (slice 6)
- `lat/lng/location_name` e mappa (slice 6 o 7)
- Filtro distanza (slice 7)
- Text search (slice 8)
- Sort per durata
- Modifica `duration` su idea esistente
- Statistiche distribuzione durata
- `Ideajar.Ideas.Filter` modulo dedicato (rinviato a slice 6+ se rule of 4 fires)
- URL params / deep-link
- Migrazione retroattiva su idee esistenti (NULL ammesso, no backfill)

## Acceptance Criteria

### Functional / behavioral

- [ ] **F1** — Tutti gli scenari Gherkin automatabili passano (DataCase + LiveViewTest).
- [ ] **F2** — Schema: `Idea.changeset/2` accetta `duration` come stringa, valida via Ecto.Enum, NULL ammesso.
- [ ] **F3** — Submit form senza duration → idea persistita con `duration: nil`.
- [ ] **F4** — Single-select form: cliccando un duration chip diverso, il precedente ritorna a `aria-pressed="false"`.
- [ ] **F5** — Toggle off form: cliccando il chip pressed, ritorna a `false` e `@selected_duration` ritorna a `nil`.
- [ ] **F6** — `Ideas.list_ideas([])` invariato dalla slice 4 (regression test esplicito).
- [ ] **F7** — `Ideas.list_ideas([durations: [:weekend]])` ritorna solo idee con `duration = :weekend`, escludendo NULL.
- [ ] **F8** — `Ideas.list_ideas([durations: [:weekend, :giornata]])` ritorna union (OR).
- [ ] **F9** — `Ideas.list_ideas([required: [@mare_id], durations: [:weekend]])` combina in AND tra clausole.
- [ ] **F10** — `Ideas.list_ideas([durations: []])` equivalente a `[durations: nil]` o opt assente: NULL passa.
- [ ] **F11** — Filter chip durata 2-state cycle (off → on → off).
- [ ] **F12** — `clear_filters` resetta sia `@filter_state` (categoria) sia `@duration_filter` (durata); lascia intoccato `@selected_duration`.
- [ ] **F13** — Idea card mostra duration badge solo quando `idea.duration != nil`.

### Accessibility

- [ ] **A1** — Form chip ha `aria-pressed="true|false"` corretto, derivato da `@selected_duration`.
- [ ] **A2** — Filter chip ha `aria-label` esattamente `<nome>` o `<nome> attiva`.
- [ ] **A3** — Filter chip ha `data-duration-filter-state` esattamente `off` o `on`.
- [ ] **A4** — Cue visivo non-color (WCAG 1.4.11): off = no icon, on = `hero-check` riusato dalla slice 4.
- [ ] **A5** — Live-region action prefix esteso: `<nome> attiva, `, `<nome> rimossa, `; `Filtri rimossi, ` su `clear_filters` (riuso slice 4).
- [ ] **A6** — Roving tabindex Categorie: ArrowRight/ArrowLeft navigano in gruppo, Tab esce, `tabindex="0"` solo sul chip focused; wrap last↔first.
- [ ] **A7** — Roving tabindex Durata: stesso comportamento, gruppo indipendente.
- [ ] **A8** — Tab da Categorie a Durata: focus si sposta sul tab-stop del prossimo gruppo (chip con tabindex=0).
- [ ] **A9** — Form chip: nessun rover; ArrowRight non muove focus; Tab order sequenziale.
- [ ] **A10** — Hit area chip ≥ 44×44 CSS px.
- [ ] **A11** — Sub-group ARIA: `<div role="group" aria-label="Filtra per categoria">` e `<div role="group" aria-label="Filtra per durata">`; lo screen reader annuncia il gruppo all'ingresso. Sub-label visivo separato (`<p class="text-xs">Categorie</p>`, `<p class="text-xs">Durata</p>`).
- [ ] **A12** — Helper text NULL-exclusion: filter row sub-block durata contiene sempre `Le idee senza durata sono nascoste quando un filtro è attivo.`
- [ ] **A13** — Live-region compound-state suffix: quando l'altro gruppo ha ≥1 filtro on, l'announce è suffixato con `, filtri categoria attivi` o `, filtri durata attivi`. `Filtri rimossi` mai suffixato.
- [ ] **A14** — DOM id distinctness: form chip durata `form-duration-chip-<atom>` vs filter chip durata `filter-duration-chip-<atom>` (no collision con slice 3/4).

### Security / robustness

- [ ] **S1** — `toggle_duration_filter` con duration fuori whitelist → no-op silenzioso (test esplicito).
- [ ] **S2** — `toggle_duration_filter` con payload non-string (es. integer 42) → no-op, no crash.
- [ ] **S3** — `toggle_form_duration` con duration fuori whitelist → no-op.
- [ ] **S4** — Save con duration manomessa via devtools/curl ("schifoso", "<script>") → changeset error `"Durata non valida"`, idea non persistita.
- [ ] **S5** — `Duration.parse/1` non lancia su input arbitrari (no `String.to_atom/1`; solo `to_existing_atom/1` su whitelist).
- [ ] **S6** — XSS regression: badge durata renderizzato con HEEx auto-escape (test sintetico con label malicious).
- [ ] **S7** — `clear_filters` su filtri vuoti → idempotente, no-op.

### Operational / data

- [ ] **O1** — Migration `ALTER TABLE ideas ADD COLUMN duration TEXT` su SQLite, eseguita via `mix ecto.migrate`. Test su roundtrip schema.
- [ ] **O2** — Migration reversibile loss-free pre-popolamento; documentato che rollback post-popolamento droppa la colonna (perdita dati). Migration test con `--include migration`.
- [ ] **O3** — Performance: `list_ideas` con 3 filtri attivi <50ms su 100 idee (sanity check, non hard SLA).
- [ ] **O4** — Esempio query SQL emessa: pinned in unit test focalizzato su `apply_filters/2`, per sicurezza pre-`ecto_sqlite3` regression.

### Validation venue

- [ ] **V1** — Screenshot mobile (iPhone 13 + Pixel 7 + 360px Pixel 4a): form con duration chip, filter row con entrambi sub-block, idea card con badge durata, empty-result state combinato.
- [ ] **V1a** — Lighthouse a11y mediana ≥95 su 3 run con filter mix categoria+durata.
- [ ] **V1b** — Keyboard-only walkthrough: arrow keys nei rover, Tab tra gruppi, Enter su chip, submit form solo via tastiera.

### Documentation

- [ ] **D1** — `docs/conventions.md` UI copy table aggiornata con stringhe slice 5 (form label, 5 chip durata, helper, sub-label, aria-label, live-region prefix, badge, errore).
- [ ] **D2** — `CONTEXT.md` aggiornato per riflettere la decisione "NULL escluso quando filtro durata attivo" (chiusura della "Decisione UX aperta" lato durata; filtri futuri da rivalutare).
- [ ] **D3** — `test/ideajar_web/live/idea_live/index_test.exs`: out-of-scope guard rimuove `Durata` dalla lista negativa; conserva `Budget`, `Distanza`, `Cerca`.
- [ ] **D4** — `test/ideajar/docs_test.exs`: nuova `describe` per slice-5 UI copy che asserisce ogni stringa canonica.

### UI copy aggiunta (canonical)

| Elemento                                | Testo IT                                  |
|-----------------------------------------|-------------------------------------------|
| Label fieldset durata (form)            | `Durata` (no asterisco — opzionale)       |
| Helper text form duration               | (nessuno — campo opzionale)               |
| Chip durata 1                           | `poche ore`                               |
| Chip durata 2                           | `mezza giornata`                          |
| Chip durata 3                           | `giornata`                                |
| Chip durata 4                           | `weekend`                                 |
| Chip durata 5                           | `più giorni`                              |
| Errore duration invalida                | `Durata non valida`                       |
| Sub-label filter Categorie (visivo)     | `Categorie`                               |
| Sub-label filter Durata (visivo)        | `Durata`                                  |
| Aria-label sub-block categorie (SR)     | `Filtra per categoria`                    |
| Aria-label sub-block durata (SR)        | `Filtra per durata`                       |
| Helper text NULL-exclusion              | `Le idee senza durata sono nascoste quando un filtro è attivo.` |
| Aria-label filter chip off              | `<nome>`                                  |
| Aria-label filter chip on               | `<nome> attiva`                           |
| Live-region action prefix on            | `<nome> attiva, `                         |
| Live-region action prefix off           | `<nome> rimossa, `                        |
| Live-region compound suffix categoria   | `, filtri categoria attivi`               |
| Live-region compound suffix durata      | `, filtri durata attivi`                  |
| Badge durata su idea card               | `<nome>` (label IT del valore)            |

## Consistency Gate

- [x] Intent is unambiguous — la decisione divergente da CONTEXT.md è esplicita e inquadrata, non implicita
- [x] Every behavior in the intent has at least one corresponding BDD scenario
- [x] Architecture constrains implementation without over-engineering (apply_filters/2 privata, no Filter module, hook JS minimo)
- [x] Same concepts named consistently (chip/filter/durata, off/on, attiva/rimossa, sub-group)
- [x] No artifact contradicts another (CONTEXT.md update tracciato come D2 acceptance, non come contraddizione interna)

**Verdict: PASS** — ready for `/plan`.
