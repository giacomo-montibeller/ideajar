# Spec: Budget chip → slider conversion (filter + form)

> Slice 9. Converts the budget UI from a chip-group to an HTML5 range
> slider in BOTH the filter row sub-block and the form fieldset Budget.
> Filter slider keeps the slice-6 cumulative `max_cost <= X` semantics
> (NULL-exclude when active); form slider replaces the "no chip
> selected" idiom with index 0 = "non specificato" → `estimated_cost
> = nil`. Index mapping mirrors the slice-7b distance slider (0 = off,
> 1..7 = canonical values). The `BudgetChip` component is deleted
> entirely. Durata stays as multi-select chips (out of scope).

## Intent Description

Slice 9 uniforma il pattern UI dei filtri di range. Slice 7b ha
introdotto l'HTML5 slider per la distanza; slice 9 lo applica anche al
budget — un filtro che è già cumulative (`max_cost <= X`) e quindi è
naturalmente uno slider, NON un chip multi-state. Inoltre il form di
aggiunta idea passa da chip-toggle a slider, eliminando l'idiom "no
chip selected = nil" in favore di `index 0 = "Non specificato"`.

**Index mapping** (parallel slice 7b distanza):

Filter side (semantica `max_cost <= X`):
- `0` = off / no filter (NULL-cost passa)
- `1` = `0€` (filter "solo idee gratis")
- `2..7` = `20, 50, 100, 200, 500, 1000+€`

Form side (single-value `estimated_cost = X`):
- `0` = "Non specificato" → `estimated_cost = nil` (parallel current "no
  chip selected")
- `1..7` = i 7 valori canonici come integer

**Domain layer**: `Ideajar.Ideas.Budget` modulo esistente esteso con due
nuovi helper `index_to_value/1` (0..7 → `nil | integer`) e due funzioni
di labelling distinte per i due context:
- `Budget.filter_label/1` — "Disattivo" / "Gratis" / "fino a 20€" / etc / "oltre 1000€"
- `Budget.form_label/1` — "Non specificato" / "Gratis" / "20€" / etc / "1000+€"

`Filter.apply_max_cost/2` invariata (la semantica SQL non cambia, lo
schema cambia solo come la LV traduce `@max_budget_index` → integer
prima di passarlo a `list_ideas/1`).

**LiveView**:
- `@cost_filter :: integer | nil` → `@max_budget_index :: 0..7` (filter side)
- `@selected_cost :: integer | nil` → `@form_budget_index :: 0..7` (form side)
- Handler `toggle_budget_filter` → `update_max_budget` (defensive parse 0..7)
- Handler `toggle_form_budget` → `update_form_budget` (defensive parse 0..7)
- New handler `remove_budget_filter` (scoped reset filter slider a 0)
- `clear_filters` esteso per cascade reset di `@max_budget_index`
- `derive_filter_opts/1` mappa index via `Budget.index_to_value/1`
- `maybe_inject_budget` mappa index via `Budget.index_to_value/1`
- Save success cascade reset di `@form_budget_index` (parallel `reset_budget`)

**Template**:
- **Filter row**: il sub-block `Budget` (oggi chip group) rimpiazzato
  da `<form id="filter-budget-slider-form" phx-change="update_max_budget">`
  con HTML5 range slider 0..7. RovingTabindex rimosso (non più chip).
  Bottone scoped `Rimuovi filtro budget` quando `@max_budget_index > 0`.
  Helper text NULL-exclude invariato.
- **Form**: il fieldset `<legend>Budget</legend>` con chip group
  rimpiazzato da slider HTML5 0..7. Caption visibile `Budget: <valuetext>`.
  Niente bottone reset esplicito — slider drag-to-0 è il reset (parallel
  current "deseleziona chip"). Form già wrappato in `<.form for={@form}>`
  esistente.

**`BudgetChip` componente**: ELIMINATO completamente. File:
- `lib/ideajar_web/components/budget_chip.ex` → DELETE
- `test/ideajar_web/components/budget_chip_test.exs` → DELETE

**`BudgetBadge`** (rendering della card idea): NON eliminato — è la
visualizzazione del valore di un'idea, non un controllo input.

**Hostile inputs uniform list** (parallel slice 7b distanza):
`update_max_budget` e `update_form_budget` con index out-of-range (`-1`,
`8`, `999`), non-numeric (`"abc"`, `"3.5"`), missing key, non-binary →
no-op silenzioso. Server è authoritative; client `<input type="range">`
ha già `min`/`max` attribute ma può essere bypassato via devtools.

**Form wrapping** (lezione slice 7b): filter slider DEVE essere in un
`<form phx-change>` esplicito perché `phx-change` su input bare non fira
nel browser. Form slider è già dentro `<.form for={@form}>` esistente.

**CSS thumb touch target**: pattern slice 7b distanza esteso al filter
budget slider (`#filter-budget-slider`) e form budget slider
(`#form-budget-slider`) per ≥44×44 px touch target.

**NULL-exclude policy filter** (invariato slice 6 BB8): index 0 = off
(NULL-cost passa); index 1-7 = filter active, idee con `estimated_cost
= nil` ESCLUSE.

**Out of scope**:
- Conversione durata (multi-select OR è feature voluta, fuori scope)
- Custom budget value oltre i 7 buckets canonici
- Range slider min-max (es. "tra 50€ e 200€")
- Budget per persona vs totale
- Budget mensile / settimanale (semantic change)
- Highlight di budget match nelle card

## User-Facing Behavior

```gherkin
Feature: Budget filter and form input as slider instead of chips

  Background:
    Given my browser holds a valid signed session cookie
    And the workspace has these ideas:
      | title             | estimated_cost |
      | Caffè al volo     |              0 |
      | Uffizi            |             50 |
      | Stadio            |            100 |
      | Sirolo            |            200 |
      | Parigi 4 giorni   |           1000 |
      | Bagno improvviso  |                |

  # ── Filter slider — initial state ────────────────────────────────
  Scenario: Visiting / shows the filter budget sub-block as a slider, off by default
    When I visit "/"
    Then I see a sub-group with aria-label "Filtra per budget"
    And there is an <input type="range"> with min="0" max="7"
    And aria-valuenow="0"
    And aria-valuetext="Disattivo"
    And there is no "Rimuovi filtro budget" button
    And every idea is rendered (NULL-cost passes when filter inactive)

  # ── Filter slider — index → semantics ────────────────────────────
  Scenario: Filter slider at index 0 keeps every idea (NULL-cost passes)
    When the filter slider is at index 0
    Then every idea is rendered

  Scenario: Filter slider at index 1 (gratis) keeps only the gratis idea, NULL excluded
    When the filter slider is at index 1
    Then I see "Caffè al volo"
    And I do not see Uffizi, Stadio, Sirolo, Parigi 4 giorni
    And I do not see "Bagno improvviso" (NULL-exclude)

  Scenario: Filter slider at index 4 (fino a 100€) keeps cheap-to-100 ideas
    When the filter slider is at index 4
    Then I see "Caffè al volo", "Uffizi", "Stadio"
    And I do not see "Sirolo", "Parigi 4 giorni"
    And I do not see "Bagno improvviso" (NULL-exclude)

  Scenario: Filter slider at index 7 (oltre 1000€) keeps every priced idea, NULL excluded
    When the filter slider is at index 7
    Then I see Caffè, Uffizi, Stadio, Sirolo, Parigi
    And I do not see "Bagno improvviso"

  Scenario: Filter slider aria-valuetext follows the canonical IT label
    When the filter slider is at index 3
    Then aria-valuenow="3"
    And aria-valuetext="fino a 50€"
    When the filter slider is at index 7
    Then aria-valuetext="oltre 1000€"

  Scenario: Filter slider phx-change is debounced 200ms
    When I drag the filter slider rapidly through 5 positions in 100ms
    Then only one server update_max_budget event is dispatched (after 200ms idle)

  # ── Filter reset ────────────────────────────────────────────────
  Scenario: "Rimuovi filtro budget" button is rendered when slider > 0
    Given the filter slider is at index 4
    Then I see a "Rimuovi filtro budget" button
    When I click it
    Then the slider returns to index 0
    And the button disappears
    And every idea is rendered again

  Scenario: "Mostra tutte" resets the budget slider to 0 alongside other filters
    Given category mare required + filter budget slider 4 + reference Sirolo + slider 50 km + search "spiaggia"
    When I click "Mostra tutte"
    Then the filter budget slider returns to 0
    And every other filter is reset

  Scenario: Refresh resets the filter budget slider (LV remount)
    Given the filter slider is at index 4
    When I reload "/"
    Then the slider is at index 0

  Scenario: Form submission does NOT reset the filter slider
    Given the filter slider is at index 4
    When I open the form and submit a valid idea
    Then the filter slider remains at index 4

  # ── Form slider — initial state ─────────────────────────────────
  Scenario: Opening the form shows the budget slider at 0 ("non specificato")
    When I open the form
    Then I see a budget slider with aria-valuenow="0"
    And aria-valuetext="Non specificato"
    And no chip-group is rendered for budget

  Scenario: Form slider at index 0 means estimated_cost = nil on submit
    Given the form is open
    And the budget slider is at index 0
    When I submit a valid idea
    Then the new idea has estimated_cost = nil

  Scenario: Form slider at index 4 (100€) means estimated_cost = 100
    Given the form is open
    And the budget slider is at index 4
    When I submit a valid idea
    Then the new idea has estimated_cost = 100

  Scenario: Form slider aria-valuetext uses the form-side label (not "fino a")
    When the form slider is at index 3
    Then aria-valuetext="50€"
    When the form slider is at index 7
    Then aria-valuetext="1000+€"

  # ── Form slider reset ───────────────────────────────────────────
  Scenario: Save success resets the form budget slider to 0
    Given a valid idea is submitted with budget slider at index 4
    Then after save success: the slider returns to index 0

  # ── BudgetChip component eliminated ─────────────────────────────
  Scenario: BudgetChip module no longer exists in the codebase
    When I inspect the codebase
    Then `lib/ideajar_web/components/budget_chip.ex` does NOT exist
    And `test/ideajar_web/components/budget_chip_test.exs` does NOT exist
    And no caller imports IdeajarWeb.Components.BudgetChip

  Scenario: BudgetBadge (card render) still exists and renders the IT label
    When I render an idea with estimated_cost = 100
    Then the card shows the budget badge "fino a 100€"
    # BudgetBadge is NOT touched by slice 9.

  # ── Hostile inputs ──────────────────────────────────────────────
  Scenario: update_max_budget with index out of [0,7] is no-op
    When server receives update_max_budget %{value: "8"} or "-1"
    Then @max_budget_index unchanged

  Scenario: update_max_budget with non-numeric value is no-op
    When server receives update_max_budget %{value: "abc"}
    Then no-op

  Scenario: update_max_budget with float value is no-op
    When server receives update_max_budget %{value: "3.5"}
    Then no-op

  Scenario: update_form_budget hostile uniform list
    When server receives update_form_budget with hostile payloads (out-of-range, non-numeric, float, missing key, non-binary)
    Then @form_budget_index unchanged
    And the LV process stays alive

  # ── XSS regression ──────────────────────────────────────────────
  Scenario: Slider rendered with HTML-escaped aria-valuetext (defense in depth)
    Given the filter slider value comes from Budget.filter_label/1 (canonical, no user input)
    Then no XSS surface — labels are static IT strings

  # ── Combined filters ────────────────────────────────────────────
  Scenario: Filter budget slider composes with category as AND (regression slice 4)
    Given category mare required + filter budget slider 4 (fino a 100€)
    Then result is ideas with category mare AND estimated_cost ≤ 100 AND non-nil cost

  Scenario: 5-way combined AND across category + duration + budget + distance + text (regression slice 8)
    Given category mare required + duration weekend + budget slider 4 + reference Sirolo + slider 50 km + search "spiaggia"
    Then result is the AND across all 5 axes

  # ── Filter slider form-shape (real browser pin, slice 7b lesson) ─
  Scenario: filter-budget-slider-form is wrapped so phx-change fires in real browsers
    Given the filter slider input is inside `<form id="filter-budget-slider-form" phx-change="update_max_budget">`
    When I dispatch a change event via the form selector
    Then the @max_budget_index assign is updated
    And the LV reloads ideas with the new opt

  # ── Domain-layer pins ───────────────────────────────────────────
  Scenario: Budget.index_to_value/1 maps 0 → nil
    Then Budget.index_to_value(0) == nil

  Scenario: Budget.index_to_value/1 maps 1..7 → canonical integers
    Then Budget.index_to_value(1) == 0
    And Budget.index_to_value(2) == 20
    And Budget.index_to_value(3) == 50
    And Budget.index_to_value(4) == 100
    And Budget.index_to_value(5) == 200
    And Budget.index_to_value(6) == 500
    And Budget.index_to_value(7) == 1000

  Scenario: Budget.index_to_value/1 with out-of-range or non-integer → :error
    Then Budget.index_to_value(-1) == :error
    And Budget.index_to_value(8) == :error
    And Budget.index_to_value("abc") == :error

  Scenario: Budget.filter_label/1 maps to filter-side IT labels
    Then Budget.filter_label(0) == "Disattivo"
    And Budget.filter_label(1) == "Gratis"
    And Budget.filter_label(2) == "fino a 20€"
    And Budget.filter_label(7) == "oltre 1000€"

  Scenario: Budget.form_label/1 maps to form-side IT labels
    Then Budget.form_label(0) == "Non specificato"
    And Budget.form_label(1) == "Gratis"
    And Budget.form_label(2) == "20€"
    And Budget.form_label(7) == "1000+€"
```

## Architecture Specification

### Components

| Componente | Tipo | Responsabilità |
|---|---|---|
| `Ideajar.Ideas.Budget` (esteso) | Modulo dominio | Aggiunti helper `index_to_value/1`, `filter_label/1`, `form_label/1`. `values/0`, `parse/1`, `label/1` esistenti invariati. |
| `Ideajar.Ideas.Filter.apply_max_cost/2` | Helper privato | INVARIATO — la semantica SQL `<= X AND IS NOT NULL` resta. |
| `Ideajar.Ideas.list_ideas/1` | Context fn | INVARIATO — `:max_cost` opt resta `integer | nil`; la LV traduce `@max_budget_index` → integer prima di passarlo. |
| `IdeajarWeb.IdeaLive.Index` (esteso) | LiveView | Rinomina assigns: `@cost_filter` → `@max_budget_index :: 0..7`, `@selected_cost` → `@form_budget_index :: 0..7`. Nuovi handler `update_max_budget`, `update_form_budget`, `remove_budget_filter`. `clear_filters` cascade. `derive_filter_opts/1` mappa index → integer. `maybe_inject_budget` mappa index → integer. |
| Template `index.html.heex` (esteso) | HEEx | Filter sub-block: chip-group → slider con form wrapper. Form fieldset: chip-group → slider. Bottone scoped `Rimuovi filtro budget` (filter only). NO bottone reset form (slider drag-to-0). |
| `IdeajarWeb.Components.BudgetChip` | Componente | **ELIMINATO**. File `.ex` + test `.exs` cancellati. |
| `IdeajarWeb.Components.BudgetBadge` (se esiste) | Componente | INVARIATO — badge card render unchanged. |
| `assets/css/app.css` | CSS | Estende thumb-target rule per `#filter-budget-slider` e `#form-budget-slider`. |

### Index mapping

```elixir
# `Ideajar.Ideas.Budget` (extended slice 9)
@index_to_value %{
  0 => nil,
  1 => 0,
  2 => 20,
  3 => 50,
  4 => 100,
  5 => 200,
  6 => 500,
  7 => 1000
}

@filter_labels %{
  0 => "Disattivo",
  1 => "Gratis",
  2 => "fino a 20€",
  3 => "fino a 50€",
  4 => "fino a 100€",
  5 => "fino a 200€",
  6 => "fino a 500€",
  7 => "oltre 1000€"
}

@form_labels %{
  0 => "Non specificato",
  1 => "Gratis",
  2 => "20€",
  3 => "50€",
  4 => "100€",
  5 => "200€",
  6 => "500€",
  7 => "1000+€"
}
```

### Interfaces

**Domain API:**
```elixir
defmodule Ideajar.Ideas.Budget do
  # ... existing values/0, parse/1, label/1 ...

  @spec index_to_value(integer) :: integer | nil | :error
  def index_to_value(0), do: nil
  def index_to_value(n) when n in 1..7, do: Map.fetch!(@index_to_value, n)
  def index_to_value(_), do: :error

  @spec filter_label(integer) :: String.t()
  def filter_label(n) when n in 0..7, do: Map.fetch!(@filter_labels, n)
  def filter_label(_), do: "Disattivo"  # safe fallback

  @spec form_label(integer) :: String.t()
  def form_label(n) when n in 0..7, do: Map.fetch!(@form_labels, n)
  def form_label(_), do: "Non specificato"
end
```

**LiveView assigns (rinominati):**
- `@max_budget_index :: 0..7` (filter side, default 0) — sostituisce `@cost_filter`
- `@form_budget_index :: 0..7` (form side, default 0) — sostituisce `@selected_cost`

**LiveView events:**
- `update_max_budget` con `%{"value" => string}` o form-shape
  `%{"filter" => %{"budget" => string}}` — slider phx-change. Defensive
  parse to integer 0..7. Multi-shape extractor parallel slice 7b/8.
- `update_form_budget` con `%{"value" => string}` o form-shape
  `%{"idea" => %{"budget" => string}}` — slider phx-change. Defensive
  parse 0..7. Multi-shape extractor.
- `remove_budget_filter` (NEW) — bottone click. Reset
  `@max_budget_index` a 0 (parallel `remove_distance_filter`).
- `clear_filters` (esteso) — reset 6 axes (categoria + durata + budget
  + distanza + ref point + testo) — invariato dal pattern slice 8 ma
  ora tocca `@max_budget_index` invece di `@cost_filter`.

**Filter slider HEEx:**
```heex
<p class="text-xs">Budget</p>
<p class="text-xs text-base-content/70">
  Le idee senza prezzo sono nascoste quando un filtro è attivo.
</p>
<div role="group" aria-label="Filtra per budget" class="space-y-2">
  <form id="filter-budget-slider-form" phx-change="update_max_budget" class="contents">
    <input
      type="range"
      id="filter-budget-slider"
      min="0"
      max="7"
      step="1"
      value={@max_budget_index}
      phx-debounce="200"
      name="value"
      aria-valuemin="0"
      aria-valuemax="7"
      aria-valuenow={@max_budget_index}
      aria-valuetext={Budget.filter_label(@max_budget_index)}
      class="range range-sm w-full"
    />
  </form>
  <p class="text-sm">Budget: {Budget.filter_label(@max_budget_index)}</p>
  <button
    :if={@max_budget_index > 0}
    type="button"
    phx-click="remove_budget_filter"
    class="btn btn-ghost btn-sm min-h-11 min-w-11"
  >
    Rimuovi filtro budget
  </button>
</div>
```

**Form slider HEEx** (dentro la `<.form for={@form}>` esistente):
```heex
<fieldset class="fieldset">
  <legend class="label mb-1">Budget</legend>
  <input
    type="range"
    id="form-budget-slider"
    name="idea[budget]"
    min="0"
    max="7"
    step="1"
    value={@form_budget_index}
    phx-change="update_form_budget"
    phx-debounce="200"
    aria-valuemin="0"
    aria-valuemax="7"
    aria-valuenow={@form_budget_index}
    aria-valuetext={Budget.form_label(@form_budget_index)}
    class="range range-sm w-full"
  />
  <p class="text-sm">Budget: {Budget.form_label(@form_budget_index)}</p>
</fieldset>
```

### Constraints

- **Filter slider HTML5 `<input type="range" min="0" max="7" step="1">`**, no `disabled` attr (always interactive). `phx-debounce="200"`. ARIA full contract.
- **Form slider HTML5 `<input type="range" min="0" max="7" step="1">`**, no `disabled`. `phx-debounce="200"`.
- **Server-side index validation**: `update_max_budget` / `update_form_budget` con index ∉ 0..7 → no-op. Non-numeric / float / non-binary → no-op.
- **NULL-exclude in `apply_max_cost/2`**: invariato (slice 6 BB8). `@max_budget_index = 0` → `:max_cost` opt = `nil` → clausola inattiva → NULL passa. Index 1-7 → integer → clausola attiva → NULL escluso.
- **Form `estimated_cost = nil` quando `@form_budget_index = 0`**: parallel current "no chip selected → nil". `maybe_inject_budget` non setta il param se index = 0.
- **Form wrapping mandatorio (filter)**: `<form id="filter-budget-slider-form" phx-change="update_max_budget">` — lezione slice 7b.
- **Form wrapping (form)**: già dentro `<.form for={@form}>` esistente, no extra wrapper.
- **Hostile inputs uniform list**: 5 cases per handler (`update_max_budget` e `update_form_budget`).
- **`BudgetChip` ELIMINATO**: regression pin via `File.exists?` refute.
- **CSS thumb touch target**: estendi pattern slice 7b al `#filter-budget-slider` e `#form-budget-slider` (≥44×44 px).
- **Save success cascade**: `reset_budget` resetta `@form_budget_index` a 0 (parallel slice 6 reset_budget).
- **`Mostra tutte` extension**: 6 reset (categoria + durata + budget + distanza + ref point + testo) — il body già copre `@max_budget_index` via cascade.

### Dependencies

Nessuna nuova dep Hex. Nessuna migration.

### Out of scope

- Conversione durata (multi-select OR è feature voluta)
- Custom budget value oltre i 7 buckets canonici
- Range slider min-max
- Budget per persona vs totale
- Budget mensile / settimanale
- Highlight budget match nelle card

## Acceptance Criteria

### Domain layer

- [ ] **DM1** — `Budget.index_to_value(0) == nil`.
- [ ] **DM2** — `Budget.index_to_value(1..7)` mappa ai 7 valori canonici (`0, 20, 50, 100, 200, 500, 1000`) nell'ordine atteso.
- [ ] **DM3** — `Budget.index_to_value(-1)` / `8` / `"abc"` → `:error`.
- [ ] **DM4** — `Budget.filter_label/1` ritorna 8 IT strings: `"Disattivo"`, `"Gratis"`, `"fino a 20€"`, ..., `"oltre 1000€"`.
- [ ] **DM5** — `Budget.form_label/1` ritorna 8 IT strings: `"Non specificato"`, `"Gratis"`, `"20€"`, ..., `"1000+€"`.
- [ ] **DM6** — `Filter.apply_max_cost/2` invariato (regression: tutti i test slice 6 passano post-refactor).
- [ ] **DM7** — `Ideas.list_ideas([])` invariato (regression).
- [ ] **DM8** — `Ideas.list_ideas([max_cost: 100])` invariato (regression — la signature di `list_ideas/1` non cambia).

### Functional / behavioral — Filter side

- [ ] **F1** — Mount: render filter sub-block contiene HTML5 slider con `min="0" max="7" value="0"`, full ARIA contract.
- [ ] **F2** — Sub-block ha `role="group" aria-label="Filtra per budget"` (invariato).
- [ ] **F3** — `@max_budget_index` default 0 al mount.
- [ ] **F4** — Slider index 0 → tutte le idee (NULL-cost passa).
- [ ] **F5** — Slider index 1 (gratis) → solo idee con `estimated_cost == 0`, NULL escluse.
- [ ] **F6** — Slider index 4 (100€) → idee con `estimated_cost ≤ 100`, NULL escluse.
- [ ] **F7** — Slider index 7 (oltre 1000€) → tutte le idee con `estimated_cost ≤ 1000` AND non-NULL.
- [ ] **F8** — `update_max_budget` con index 0..7 → assign + reload.
- [ ] **F9** — `update_max_budget` con form-shape `%{"filter" => %{"budget" => "3"}}` → identico a bare-shape.
- [ ] **F10** — `update_max_budget` hostile (out-of-range, non-numeric, float) → no-op.
- [ ] **F11** — `remove_budget_filter` → `@max_budget_index = 0` + reload.
- [ ] **F12** — Bottone `Rimuovi filtro budget` hidden when index 0, visible when > 0.
- [ ] **F13** — `clear_filters` cascade reset `@max_budget_index = 0`.
- [ ] **F14** — Refresh resetta `@max_budget_index` a 0.
- [ ] **F15** — Save success NON resetta `@max_budget_index` (filter survives submit).
- [ ] **F16** — phx-debounce="200" pinned in slider attributes.
- [ ] **F17** — Filter slider in `<form id="filter-budget-slider-form" phx-change="update_max_budget">` (real-browser pin via form selector).

### Functional / behavioral — Form side

- [ ] **FF1** — Mount form: render contiene HTML5 slider 0..7 + caption `Budget: Non specificato`, NO chip group.
- [ ] **FF2** — `@form_budget_index` default 0 al form open.
- [ ] **FF3** — Slider index 0 + valid submit → idea creata con `estimated_cost = nil`.
- [ ] **FF4** — Slider index 4 + valid submit → idea creata con `estimated_cost = 100`.
- [ ] **FF5** — `update_form_budget` con index 0..7 → assign.
- [ ] **FF6** — `update_form_budget` hostile → no-op.
- [ ] **FF7** — Save success cascade reset `@form_budget_index = 0` (parallel `reset_budget`).
- [ ] **FF8** — `aria-valuetext` form usa `Budget.form_label/1` (`"50€"`, NON `"fino a 50€"`).

### Component lifecycle

- [ ] **C1** — `lib/ideajar_web/components/budget_chip.ex` does NOT exist post-refactor.
- [ ] **C2** — `test/ideajar_web/components/budget_chip_test.exs` does NOT exist post-refactor.
- [ ] **C3** — Nessun `import IdeajarWeb.Components.BudgetChip` o `alias IdeajarWeb.Components.BudgetChip` o `<BudgetChip.*` in qualsiasi file.
- [ ] **C4** — `IdeajarWeb.Components.BudgetBadge` (se esiste, slice 6) NON eliminato — render card invariato.

### Accessibility

- [ ] **A1** — Filter slider full ARIA: `aria-valuemin="0"`, `aria-valuemax="7"`, `aria-valuenow`, `aria-valuetext`.
- [ ] **A2** — Form slider full ARIA: stessi attributi.
- [ ] **A3** — Filter sub-block `role="group" aria-label="Filtra per budget"` invariato.
- [ ] **A4** — Form fieldset `<legend>Budget</legend>` invariato.
- [ ] **A5** — Helper text NULL-exclude filter (`"Le idee senza prezzo sono nascoste quando un filtro è attivo."`) invariato.
- [ ] **A6** — Bottone `Rimuovi filtro budget` hit area ≥ 44×44 (`min-h-11 min-w-11`).
- [ ] **A7** — Slider thumb touch target ≥ 44×44 px (CSS).
- [ ] **A8** — Filter row sub-block order Categorie → Durata → Budget → Distanza → Testo invariato (Budget posizione 3).

### Security / robustness

- [ ] **S1** — `update_max_budget` con `%{"value" => "8"}` (out of [0,7]) → no-op.
- [ ] **S2** — `update_max_budget` con `%{"value" => "abc"}` (non-numeric) → no-op.
- [ ] **S3** — `update_max_budget` con `%{"value" => "3.5"}` (float) → no-op.
- [ ] **S4** — `update_form_budget` hostile uniform list (5 inputs) → no-op.
- [ ] **S5** — XSS: `aria-valuetext` from canonical static labels, no user input → no XSS surface.
- [ ] **S6** — Hostile form params (`"idea[budget]" => "999"`) → form param ignorato (slider clamps server-side).

### Operational / data

- [ ] **O1** — Nessuna migration. Schema `estimated_cost :: integer | nil` invariato.
- [ ] **O2** — `Budget.index_to_value/1` testato indipendentemente (8+ tests boundary).
- [ ] **O3** — `Budget.filter_label/1` + `Budget.form_label/1` testati (16+ tests totale).
- [ ] **O4** — Performance: list_ideas con 5 filter attivi + 100 idee fixture < 100 ms (sanity, invariato slice 7b).
- [ ] **O5** — SQL emission pin: `:max_cost` clause invariata (regression slice 6 BB15).

### Validation venue

- [ ] **V1** — Screenshot mobile: filter sub-block budget slider, form fieldset budget slider, empty-filter state con budget filter on.
- [ ] **V1a** — Lighthouse a11y mediana ≥ 95.
- [ ] **V1b** — Keyboard-only walkthrough: Tab al filter budget slider, frecce per cambiare, Tab a `Rimuovi filtro budget`.
- [ ] **V2** — Manual test: drag rapido slider, debounce funziona, no flicker.
- [ ] **V2a** — Manual test form: open form, drag slider, submit, verify `estimated_cost` corretto.

### Documentation

- [ ] **D1** — `docs/conventions.md` UI copy table aggiornata con stringhe slice 9 (~16 strings: 8 filter labels + 8 form labels).
- [ ] **D2** — `CONTEXT.md` Filtri section non cambia (Budget rimane filter #3 con stessa semantica).
- [ ] **D3** — `test/ideajar/docs_test.exs`: nuova `describe "slice-9 UI copy"`.
- [ ] **D4** — `BudgetChip` test removal pinned in `describe "slice-9 component lifecycle"` con assertion che il file non esiste.

### UI copy aggiunta (canonical)

| Elemento | Testo IT |
|---|---|
| Filter aria-valuetext idx 0 | `Disattivo` |
| Filter aria-valuetext idx 1 | `Gratis` |
| Filter aria-valuetext idx 2 | `fino a 20€` |
| Filter aria-valuetext idx 3 | `fino a 50€` |
| Filter aria-valuetext idx 4 | `fino a 100€` |
| Filter aria-valuetext idx 5 | `fino a 200€` |
| Filter aria-valuetext idx 6 | `fino a 500€` |
| Filter aria-valuetext idx 7 | `oltre 1000€` |
| Filter caption sotto slider | `Budget: <valuetext>` |
| Bottone rimuovi filtro budget | `Rimuovi filtro budget` |
| Form aria-valuetext idx 0 | `Non specificato` |
| Form aria-valuetext idx 1 | `Gratis` |
| Form aria-valuetext idx 2 | `20€` |
| Form aria-valuetext idx 3 | `50€` |
| Form aria-valuetext idx 4 | `100€` |
| Form aria-valuetext idx 5 | `200€` |
| Form aria-valuetext idx 6 | `500€` |
| Form aria-valuetext idx 7 | `1000+€` |
| Form caption sotto slider | `Budget: <valuetext>` |

## Consistency Gate

- [x] Intent unambiguo — chip → slider in 2 contexts (filter cumulative + form single-value), index mapping coerente con slice 7b distanza pattern, NULL-exclude policy filter invariata, BudgetChip eliminato
- [x] Ogni behavior ha BDD scenario corrispondente (filter ranges, form values, reset matrix, hostile inputs, form-shape pin, BudgetChip eliminato, BudgetBadge invariato, domain helpers)
- [x] Architecture constrains without over-engineering (no migration, semantica `apply_max_cost` invariata, helpers domain in `Budget` modulo, form wrapping pattern slice 7b applicato)
- [x] Termini consistenti (max_budget_index, form_budget_index, filter_label, form_label, NULL-exclude, drag-to-0)
- [x] No contradictions — form drag-to-0 vs filter explicit "Rimuovi filtro budget" button differenziati esplicitamente; index 0 per form = nil (parallel current "no chip selected") chiaramente documentato

**Verdict: PASS** — ready for `/plan`.
