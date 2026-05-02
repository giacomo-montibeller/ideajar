# Plan: Slice 9 — Budget chip → slider conversion (filter + form)

**Created**: 2026-05-02
**Branch**: main (trunk-based)
**Status**: approved
**Spec**: `docs/specs/budget-slider-on-ideas.md`

## Build conventions (carried from slice 1-8)

- **Strict TDD** — RED → GREEN → REFACTOR per step.
- Ogni commit attraverso la skill `commit-message`. In `/build` uso option 1 default.
- Pre-step gate: `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo`, `mix deps.audit`, `mix test --include migration`.
- Domain in `Ideajar.*`, delivery in `IdeajarWeb.*`.
- UI copy IT canonica appesa a `docs/conventions.md` nello step 5.
- Trunk-based su `main`, ogni step lascia il codebase committable.
- Form wrapping pattern slice 7b mandatorio per filter slider (`<form id="filter-..." phx-change="...">`).

## Goal

Slice 9 uniforma il pattern UI dei filtri di range. Slice 7b ha introdotto l'HTML5 slider per la distanza; slice 9 lo applica anche al budget — un filtro che è già cumulative (`max_cost <= X`) e quindi naturalmente uno slider, NON un chip multi-state. Inoltre il form di aggiunta idea passa da chip-toggle a slider, eliminando l'idiom "no chip selected = nil" in favore di `index 0 = "Non specificato"`.

Il refactor è UI-only — la semantica SQL del filter (`Filter.apply_max_cost/2`) e dello schema (`Idea.estimated_cost`) restano invariate. Il modulo `IdeajarWeb.Components.BudgetChip` viene eliminato completamente. Durata resta come multi-select chip (out of scope).

Foundation: schema slice 6 (`estimated_cost`) + pattern slider slice 7b. Nessuna nuova migration.

Fuori scope: conversione durata, range slider min-max, custom budget value oltre i 7 buckets, budget per-persona/mensile, highlight match nelle card.

## Decisioni architetturali pre-build

- **DD-S9-1 — Index mapping (filter + form, parallel slice 7b distanza)**:
  ```
  0 → off (filter: no clause; form: nil)
  1 → 0€ (gratis)
  2 → 20€
  3 → 50€
  4 → 100€
  5 → 200€
  6 → 500€
  7 → 1000€ ("oltre 1000€" filter, "1000+€" form)
  ```

- **DD-S9-2 — `Budget.index_to_value/1` (post-iter1 Design Critic B1 fix)**: signature `integer | nil` (NO `:error`). Out-of-range index clamp a `nil` (safe-fallback). Razionale: `:error` propagato in `derive_filter_opts/1` produrrebbe `Keyword.put(:max_cost, :error)` rompendo `apply_max_cost/2`; in `maybe_inject_budget` produrrebbe `Integer.to_string(:error)` → crash. Clamp a `nil` rende ogni caller safe by default.
  ```elixir
  @spec index_to_value(integer) :: integer | nil
  def index_to_value(0), do: nil
  def index_to_value(n) when n in 1..7, do: Map.fetch!(@index_to_value, n)
  def index_to_value(_), do: nil  # OOR / non-integer → safe-fallback nil
  ```

- **DD-S9-3 — Label functions in web layer (post-iter1 Design Critic B2 fix)**: `filter_label/1` e `form_label/1` NON sono domain helpers — sono UI copy con prosa IT context-specific (filter cumulative "fino a", form single value). Vanno in nuovo modulo web layer `IdeajarWeb.Components.BudgetLabels` con 2 funzioni puri:
  - `BudgetLabels.filter/1` — `"Disattivo"` / `"Gratis"` / `"fino a 20€"` / ... / `"oltre 1000€"`
  - `BudgetLabels.form/1` — `"Non specificato"` / `"Gratis"` / `"20€"` / ... / `"1000+€"`
  Razionale: stesso value (50€) ha label diversa nei due context. Separare label-by-context dalla domain mantiene `Ideajar.Ideas.Budget` domain-pure (solo values + parse + canonical badge label `Budget.label/1` esistente). Pattern parallel a `IdeajarWeb.Components.LocationBadge` (domain → web layer per UI rendering).

- **DD-S9-4 — `Filter.apply_max_cost/2` invariato**: la semantica SQL resta `<= X AND IS NOT NULL`. Slice 9 cambia SOLO la traduzione lato LV (index → integer | nil) prima di passare l'opt a `list_ideas/1`. Test slice 6 (BB8/O3 SQL emission pin) restano verdi.

- **DD-S9-5 — Renaming assigns**:
  - Filter: `@cost_filter :: integer | nil` → `@max_budget_index :: 0..7` (default 0)
  - Form: `@selected_cost :: integer | nil` → `@form_budget_index :: 0..7` (default 0)
  Il rename rende il dominio uniforme con `@max_distance_index` (slice 7b) e `@text_search_query` (slice 8). `derive_filter_opts/1` body legge `@max_budget_index` invece di `@cost_filter`.

- **DD-S9-6 — Multi-shape extractor (parallel slice 7b/8)**:
  - `update_max_budget`: `%{"value" => v}` (test sintetico) + `%{"filter" => %{"budget" => v}}` (real browser)
  - `update_form_budget`: `%{"value" => v}` (test sintetico) + `%{"idea" => %{"budget" => v}}` (real browser, dentro la `<.form>` esistente)
  Hostile (out-of-range, non-numeric, float, missing key) → no-op.

- **DD-S9-7 — Form `name` attribute**: `name="idea[budget]"` (NOT `idea[estimated_cost]`). Razionale: il payload ricevuto è un INDEX (0..7), non il valore integer in centesimi. `maybe_inject_budget` traduce index → integer prima di passarlo al changeset. Chiarezza nel debugging.

- **DD-S9-8 — Filter `name` attribute**: `name="filter[budget]"` (parallel slice 8 `name="filter[text_search]"`).

- **DD-S9-9 — `BudgetChip` eliminato**: cancellazione netta del file `lib/ideajar_web/components/budget_chip.ex` + test file `test/ideajar_web/components/budget_chip_test.exs`. Nessun `import` o `alias` orfano. Pin via `File.exists?` refute in step 4.

- **DD-S9-10 — `BudgetBadge` invariato**: il rendering della card idea (mostra il budget come label) NON cambia. Slice 9 tocca solo l'INPUT del budget, non il rendering del valore.

- **DD-S9-11 — Form `Rimuovi prezzo` button (post-iter1 UX B1 fix)**: a differenza dell'iter1 plan (che proponeva drag-to-0), il form HA un bottone `Rimuovi prezzo` esplicito condizionale (visibile quando `@form_budget_index > 0`). Razionale UX Critic: drag-to-0 non è scoperto su slider; lo state "non specificato" può sembrare quello iniziale intoccato. Bottone esplicito specchia il pattern filter `Rimuovi filtro budget`. Click → handler `remove_form_budget` reset `@form_budget_index = 0`. UI copy: `Rimuovi prezzo` (NOT `Rimuovi budget`, NOT `Cancella`). Pattern parallel slice 7a `Rimuovi posizione`. Hit area ≥44×44.

- **DD-S9-12 — Save success cascade**: `reset_budget` post-save cambia da `assign(:selected_cost, nil)` a `assign(:form_budget_index, 0)`. One-liner.

- **DD-S9-13 — `clear_filters` cascade**: `assign(:cost_filter, nil)` → `assign(:max_budget_index, 0)`. One-liner.

- **DD-S9-14 — `filter_active?/1` body extension**: la pattern-match map sul socket assigns cambia da `cost_filter: cf` con `not is_nil(cf)` a `max_budget_index: mbi` con `mbi > 0`. Behavior-preserving (entrambi sono "filter attivo" sse il cost ha un valore).

- **DD-S9-15 — `derive_filter_opts/1` body extension**: la pattern-match map cambia + il body usa `Budget.index_to_value/1` per tradurre. Test pin che `:max_cost` opt resta `integer | nil` (J).

- **DD-S9-16 — `maybe_inject_budget` index → value**: signature change da `maybe_inject_budget(params, integer | nil)` a `maybe_inject_budget(params, 0..7)`. Body: index 0 → no inject (params invariato → `estimated_cost = nil`); index 1-7 → `Map.put(params, "estimated_cost", Integer.to_string(Budget.index_to_value(index)))`.

- **DD-S9-17 — CSS thumb touch target extension**: 3 nuove rule CSS per `#filter-budget-slider::-webkit-slider-thumb`, `::-moz-range-thumb`, e `#filter-budget-slider`. Stessa identica replica per `#form-budget-slider`. Pattern slice 7b (DD A8).

- **DD-S9-18 — phx-debounce 200ms**: parallel slice 7b distanza slider (drag rapido genera ~60 events/sec; 200ms = ~5 events/sec).

- **DD-S9-19 — NULL-exclude policy filter (invariato slice 6 BB8)**: `@max_budget_index = 0` → `:max_cost` opt = `nil` → clausola inattiva → NULL-cost passa. Index 1-7 → integer → clausola attiva → NULL escluso. Pattern uniforme con durata/distanza.

- **DD-S9-20 — Test slice 6 chip riscritti per slider**: i `describe "form budget field (slice 6 step 4)"` e `describe "budget filter sub-block (slice 6 step 8)"` con chip-specific assertions vengono riscritti completamente. Mantenere il describe name con suffisso "post-slice-9 slider conversion" per traceability storica.

## Acceptance Criteria

> Mappatura uno-a-uno con `docs/specs/budget-slider-on-ideas.md`.

### Domain layer

- [ ] **DM1** — `Budget.index_to_value(0) == nil`.
- [ ] **DM2** — `Budget.index_to_value(1..7)` mappa ai 7 valori canonici (`0, 20, 50, 100, 200, 500, 1000`).
- [ ] **DM3** — `Budget.index_to_value(-1)` / `8` / `"abc"` → `nil` (safe-fallback, NOT `:error`). Iter1 Design Critic B1 fix.
- [ ] **DM3a** — `:error` path eliminated: `Budget.index_to_value/1` signature è `integer | nil`, non più `integer | nil | :error`. Pin tipo: `assert is_integer(Budget.index_to_value(3)) or is_nil(Budget.index_to_value(99))`.
- [ ] **DM4** — `BudgetLabels.filter/1` (web layer) ritorna 8 IT strings: `"Disattivo"`, `"Gratis"`, `"fino a 20€"`, ..., `"oltre 1000€"`.
- [ ] **DM4a** — `BudgetLabels.filter/1` con OOR → fallback `"Disattivo"`.
- [ ] **DM5** — `BudgetLabels.form/1` (web layer) ritorna 8 IT strings: `"Non specificato"`, `"Gratis"`, `"20€"`, ..., `"1000+€"`.
- [ ] **DM5a** — `BudgetLabels.form/1` con OOR → fallback `"Non specificato"`.
- [ ] **DM6** — `Filter.apply_max_cost/2` invariato (regression: tutti i test slice 6 BB8 passano post-refactor).
- [ ] **DM7** — `Ideas.list_ideas([])` invariato (regression).
- [ ] **DM8** — `Ideas.list_ideas([max_cost: 100])` invariato (regression — la signature di `list_ideas/1` non cambia, solo la traduzione LV).

### Filter side

- [ ] **F1** — Mount filter sub-block contiene HTML5 slider con `min="0" max="7" value="0"`, full ARIA contract.
- [ ] **F2** — Sub-block ha `role="group" aria-label="Filtra per budget"`.
- [ ] **F3** — `@max_budget_index` default 0 al mount.
- [ ] **F4** — Slider index 0 → tutte le idee (NULL-cost passa).
- [ ] **F5** — Slider index 1 (gratis) → solo idee con `estimated_cost == 0`, NULL escluse.
- [ ] **F6** — Slider index 4 (100€) → idee con `estimated_cost ≤ 100`, NULL escluse.
- [ ] **F7** — Slider index 7 (oltre 1000€) → tutte le idee con `estimated_cost ≤ 1000` AND non-NULL.
- [ ] **F8** — `update_max_budget` con index 0..7 → assign + reload.
- [ ] **F9** — `update_max_budget` con form-shape `%{"filter" => %{"budget" => "3"}}` → identico a bare-shape (DD-S9-6).
- [ ] **F10** — `update_max_budget` hostile (out-of-range, non-numeric, float) → no-op.
- [ ] **F11** — `remove_budget_filter` → `@max_budget_index = 0` + reload.
- [ ] **F12** — Bottone `Rimuovi filtro budget` hidden when index 0, visible when > 0.
- [ ] **F13** — `clear_filters` cascade reset `@max_budget_index = 0`.
- [ ] **F14** — Refresh resetta `@max_budget_index` a 0.
- [ ] **F15** — Save success NON resetta `@max_budget_index`.
- [ ] **F16** — phx-debounce="200" pinned.
- [ ] **F17** — Filter slider in `<form id="filter-budget-slider-form" phx-change="update_max_budget">` (real-browser pin via `view |> form(...) |> render_change()`).

### Form side

- [ ] **FF1** — Mount form: render contiene HTML5 slider 0..7 + caption `Budget: Non specificato`, NO chip group.
- [ ] **FF2** — `@form_budget_index` default 0 al form open.
- [ ] **FF3** — Slider index 0 + valid submit → idea creata con `estimated_cost = nil`.
- [ ] **FF4** — Slider index 4 + valid submit → idea creata con `estimated_cost = 100`.
- [ ] **FF5** — `update_form_budget` con index 0..7 → assign.
- [ ] **FF6** — `update_form_budget` hostile → no-op.
- [ ] **FF7** — Save success cascade reset `@form_budget_index = 0` (parallel `reset_budget`).
- [ ] **FF8** — `aria-valuetext` form usa `BudgetLabels.form/1` (`"50€"`, NON `"fino a 50€"`).
- [ ] **FF9** — Form slider `name="idea[budget]"` (NOT `idea[estimated_cost]`) — DD-S9-7.
- [ ] **FF10** — Bottone `Rimuovi prezzo` (post-iter1 UX B1 fix) condizionale: rendered SOLO quando `@form_budget_index > 0`. Click → `@form_budget_index = 0`. Razionale: drag-to-0 reset non è scoperto su slider (UX gap). Il bottone esplicito mirrora il pattern filter `Rimuovi filtro budget`. Hit area ≥44×44 (`min-h-11 min-w-11`).

### Component lifecycle

- [ ] **C1** — `lib/ideajar_web/components/budget_chip.ex` does NOT exist post-refactor.
- [ ] **C2** — `test/ideajar_web/components/budget_chip_test.exs` does NOT exist post-refactor.
- [ ] **C3** — Nessun `import IdeajarWeb.Components.BudgetChip`, `alias IdeajarWeb.Components.BudgetChip`, o `BudgetChip.*` in qualsiasi file `lib/` o `test/` (eccetto eventuali commit-history dei file).
- [ ] **C4** — `IdeajarWeb.Components.BudgetBadge` (rendering della card idea) NON eliminato. File esiste e esporta le funzioni di rendering invariati. Card render con `estimated_cost = 100` mostra il badge canonical (regression slice 6).
- [ ] **C5** — Nuovo modulo `IdeajarWeb.Components.BudgetLabels` esiste con `filter/1` + `form/1` esportati. Pin via `function_exported?`.

### Accessibility

- [ ] **A1** — Filter slider full ARIA: `aria-valuemin="0"`, `aria-valuemax="7"`, `aria-valuenow`, `aria-valuetext`.
- [ ] **A2** — Form slider full ARIA.
- [ ] **A3** — Filter sub-block `role="group" aria-label="Filtra per budget"`.
- [ ] **A4** — Form fieldset `<legend>Budget</legend>`.
- [ ] **A5** — Helper text NULL-exclude filter invariato.
- [ ] **A6** — Bottone `Rimuovi filtro budget` hit area ≥ 44×44.
- [ ] **A7** — Slider thumb touch target ≥ 44×44 px (CSS, parallel slice 7b).
- [ ] **A8** — Filter row sub-block order Categorie → Durata → Budget → Distanza → Testo invariato.

### Security / robustness

- [ ] **S1** — `update_max_budget` con `%{"value" => "8"}` (out of [0,7]) → no-op.
- [ ] **S2** — `update_max_budget` con `%{"value" => "abc"}` (non-numeric) → no-op.
- [ ] **S3** — `update_max_budget` con `%{"value" => "3.5"}` (float) → no-op.
- [ ] **S4** — `update_form_budget` hostile uniform list (5 inputs) → no-op.
- [ ] **S5** — XSS: `aria-valuetext` from canonical static labels — no XSS surface.
- [ ] **S6** — Hostile form params: `"idea[budget]" => "999"` (out-of-range index nel raw form payload). Contract chiaro post-iter1 Acceptance B3 fix: il `save` handler chiama `maybe_inject_budget(params, socket.assigns.form_budget_index)` — il parametro è SEMPRE l'assign clamped 0..7 (server-side authoritative), MAI il raw form param. L'`update_form_budget` extractor che riceve l'index hostile prima del submit lo no-op'a (assign rimane 0). Il submit poi inietta via `Budget.index_to_value(0) = nil` → `estimated_cost = nil`. **NON `Integer.to_string(:error)` crash**: DM3a garantisce `index_to_value/1` clamp. Pin esplicito S6: dispatch hostile `update_form_budget` + submit form + asserisci `estimated_cost = nil` nel DB e LV process alive.

### Operational / data

- [ ] **O1** — Nessuna migration.
- [ ] **O2** — `Budget.index_to_value/1` testato (8+ tests boundary).
- [ ] **O3** — `BudgetLabels.filter/1` + `BudgetLabels.form/1` testati (16+ tests totale).
- [ ] **O4** — Performance: list_ideas con 5 filter attivi + 100 idee fixture < 100 ms.
- [ ] **O5** — SQL emission pin: `:max_cost` clause invariata (regression slice 6 BB15).
- [ ] **O6** — `:max_cost` opt invariata (J): `list_ideas/1` continua ad accettare `integer | nil` per `:max_cost`.

### Documentation

- [ ] **D1** — `docs/conventions.md` UI copy table aggiornata con stringhe slice 9 (~16 strings: 8 filter labels + 8 form labels).
- [ ] **D2** — `CONTEXT.md` Filtri section non cambia (Budget filter #3 invariato semantically).
- [ ] **D3** — `test/ideajar/docs_test.exs`: nuova `describe "slice-9 UI copy"`.
- [ ] **D4** — `BudgetChip` test removal pinned in nuovo describe `"slice-9 component lifecycle"` con assertion che il file non esiste.

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
| Bottone form rimuovi prezzo | `Rimuovi prezzo` |

## User-Facing Behavior

> BDD scenarios copiati verbatim da `docs/specs/budget-slider-on-ideas.md` (vedi sezione "User-Facing Behavior").

## Steps

### Step 1: `Budget.index_to_value/1` (domain) + `IdeajarWeb.Components.BudgetLabels` (web)

**Complexity**: standard
**Rationale**: pure helpers — domain owns the value mapping (`index → integer | nil`), web layer owns the IT label copy (`index → String.t()` per filter/form contexts). Iter1 Design Critic B2 fix: domain non bloated.

**RED domain** (`test/ideajar/ideas/budget_test.exs` extend con nuovo describe `index_to_value/1 (slice 9)`):
1. `index_to_value(0) == nil`.
2. `index_to_value(1..7)` ritorna i 7 valori canonici nell'ordine atteso.
3. `index_to_value(-1)` / `8` / `99` → `nil` (safe-fallback, NOT `:error` — iter1 Design B1 fix).
4. `index_to_value("abc")` / `:atom` / `nil` → `nil` (safe-fallback).
5. **Type contract pin (DM3a)**: `assert is_integer(Budget.index_to_value(3)) or is_nil(Budget.index_to_value(3))`. Idem per OOR — verifica che NON ritorna mai `:error`.

**RED web** (`test/ideajar_web/components/budget_labels_test.exs` new):
1. `BudgetLabels.filter/0..7` — 8 tests, uno per index, asserisce literal IT string (`"Disattivo"` / `"Gratis"` / `"fino a 20€"` / etc).
2. `BudgetLabels.form/0..7` — 8 tests con form labels (`"Non specificato"` / `"Gratis"` / `"20€"` / etc).
3. **Divergence pin**: `BudgetLabels.filter(1) == BudgetLabels.form(1)` (entrambe `"Gratis"`); `BudgetLabels.filter(4) != BudgetLabels.form(4)` (`"fino a 100€"` vs `"100€"`).
4. **OOR safe-fallback**: `BudgetLabels.filter(99)` → `"Disattivo"`, `BudgetLabels.form(99)` → `"Non specificato"`.

**GREEN domain**:
- Estendi `lib/ideajar/ideas/budget.ex`:
  ```elixir
  @index_to_value %{1 => 0, 2 => 20, 3 => 50, 4 => 100, 5 => 200, 6 => 500, 7 => 1000}
  
  @doc """
  Mappa l'index slider 0..7 al valore canonical integer.
  
  Index 0 → nil (filter inactive / form unspecified).
  Index 1..7 → integer in {0, 20, 50, 100, 200, 500, 1000}.
  OOR / non-integer → nil (safe-fallback). NON solleva, NON ritorna :error.
  """
  @spec index_to_value(integer) :: integer | nil
  def index_to_value(0), do: nil
  def index_to_value(n) when n in 1..7, do: Map.fetch!(@index_to_value, n)
  def index_to_value(_), do: nil
  ```

**GREEN web**:
- Nuovo file `lib/ideajar_web/components/budget_labels.ex`:
  ```elixir
  defmodule IdeajarWeb.Components.BudgetLabels do
    @moduledoc """
    Slice 9 — UI copy IT per il budget slider in 2 context:
    - filter (cumulative "fino a X €")
    - form (single value "X €")
    
    Razionale: stesso index ha label diversa nei due context. Vivono in
    web layer (NOT in `Ideajar.Ideas.Budget`) perché la prosa IT è UI
    copy delivery-side. Domain `Budget` resta pure (values + parse +
    canonical badge label).
    """
    
    @filter_labels %{
      0 => "Disattivo", 1 => "Gratis",
      2 => "fino a 20€", 3 => "fino a 50€", 4 => "fino a 100€",
      5 => "fino a 200€", 6 => "fino a 500€", 7 => "oltre 1000€"
    }
    
    @form_labels %{
      0 => "Non specificato", 1 => "Gratis",
      2 => "20€", 3 => "50€", 4 => "100€",
      5 => "200€", 6 => "500€", 7 => "1000+€"
    }
    
    @spec filter(integer) :: String.t()
    def filter(n) when n in 0..7, do: Map.fetch!(@filter_labels, n)
    def filter(_), do: "Disattivo"
    
    @spec form(integer) :: String.t()
    def form(n) when n in 0..7, do: Map.fetch!(@form_labels, n)
    def form(_), do: "Non specificato"
  end
  ```

**REFACTOR**: docstring documenta divergenza filter/form + safe-fallback contract.

**Files**: `lib/ideajar/ideas/budget.ex` (extend), `lib/ideajar_web/components/budget_labels.ex` (new), `test/ideajar/ideas/budget_test.exs` (extend), `test/ideajar_web/components/budget_labels_test.exs` (new).
**Spec mapping**: DM1, DM2, DM3, DM3a, DM4, DM4a, DM5, DM5a, C5, O2, O3, DD-S9-1, DD-S9-2, DD-S9-3.

### Step 2: LV filter side — slider replaces chip group

**Complexity**: complex
**Rationale**: cross-cutting (assigns rename + handler nuovi + clear_filters cascade + filter_active? body + derive_filter_opts body + template chip→slider + 30+ chip tests da riscrivere). Pattern parallel slice 7b distanza filter slider, niente di nuovo concettualmente.

**RED** (`test/ideajar_web/live/idea_live/index_test.exs`):

Nuovo `describe "filter budget slider (slice 9 step 2)"`:
1. **F1/F3** Mount: render contains `<input type="range" id="filter-budget-slider" min="0" max="7" value="0">`, full ARIA. `@max_budget_index` default 0.
2. **F2/A3** Sub-block ha `role="group" aria-label="Filtra per budget"`.
3. **A1** ARIA contract: `aria-valuemin="0"`, `aria-valuemax="7"`, `aria-valuenow="0"`, `aria-valuetext="Disattivo"`.
4. **F8/F4** `update_max_budget` con `%{"value" => "0"}` → render mostra tutte le idee (incluso NULL-cost).
5. **F5** `update_max_budget` con index 1 → render mostra solo idee con `cost == 0`, NULL escluse.
6. **F6** `update_max_budget` con index 4 → render mostra idee con `cost ≤ 100`, NULL escluse.
7. **F9** Form-shape `%{"filter" => %{"budget" => "3"}}` → stesso behavior.
8. **F10/S1/S2/S3** Hostile uniform list 5 inputs (`"-1"`, `"8"`, `"abc"`, `"3.5"`, missing key).
9. **F12** Bottone `Rimuovi filtro budget` hidden quando index 0, visible quando > 0.
10. **F11** Click `Rimuovi filtro budget` → `@max_budget_index == 0`.
11. **F13** `clear_filters` cascade: pre-state index 4 + altri filter → click `Mostra tutte` → tutti reset incluso `@max_budget_index == 0`.
12. **F14** Refresh: `@max_budget_index` torna a 0 (LV remount).
13. **F15** Save success NON resetta `@max_budget_index`.
14. **F16** phx-debounce="200" pinned.
15. **F17** Form-wrapper real-browser pin: `view |> form("#filter-budget-slider-form", filter: %{budget: "3"}) |> render_change()` → assign aggiornato.
16. **A6** Bottone reset hit area ≥ 44×44.
17. **A8** Filter row sub-block order Categorie → Durata → Budget → Distanza → Testo invariato (Budget posizione 3).
18. **DM7** Regression: `list_ideas([])` invariato.

Riscrivi `describe "budget filter sub-block (slice 6 step 8)"` come `describe "budget filter (post-slice-9 slider conversion, was slice 6 step 8 chip)"` — adatta tutte le assertion da chip a slider, mantieni la coverage funzionale.

**GREEN**:
- `lib/ideajar_web/live/idea_live/index.ex`:
  - Mount: rinomina `assign(:cost_filter, nil)` → `assign(:max_budget_index, 0)`.
  - **Rimuovi** `handle_event("toggle_budget_filter", ...)` (entrambe le clausole + catchall).
  - **Aggiungi** `handle_event("update_max_budget", params, socket)` con `extract_max_budget_index/1` multi-shape extractor + integer 0..7 guard.
  - **Aggiungi** `handle_event("remove_budget_filter", _, socket)` reset.
  - `clear_filters`: cambia `assign(:cost_filter, nil)` → `assign(:max_budget_index, 0)`.
  - `derive_filter_opts/1`: pattern-match `cost_filter` → `max_budget_index`; body `Keyword.put(:max_cost, cost_filter)` → `Keyword.put(:max_cost, Budget.index_to_value(max_budget_index))`. Nessun `case`/safe handling necessario: `index_to_value/1` clamp OOR a `nil` (DD-S9-2), quindi il return è sempre `integer | nil`, esattamente quello che `apply_max_cost/2` accetta.
  - `filter_active?/1`: pattern-match `cost_filter: cf` → `max_budget_index: mbi`; body `not is_nil(cf)` → `mbi > 0`.
- `lib/ideajar_web/live/idea_live/index.html.heex`:
  - Filter sub-block Budget: rimuovi chip group + RovingTabindex + helper text "Tocca per filtrare" specifico chip.
  - Aggiungi slider con form wrapper. Caption + bottone reset condizionale.
- Aggiungi extractor helper `defp extract_max_budget_index/1`.

**REFACTOR**: docstring chiaro su `update_max_budget` (DD-S9-6 multi-shape), `Budget.index_to_value(:error)` safe handling.

**Files**: `lib/ideajar_web/live/idea_live/index.ex` (extend), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (rewrite slice-6 step-8 describe + new slice-9 step-2 describe).
**Spec mapping**: F1-F17, A1, A3, A6, A8, S1, S2, S3, S5, DM7, O5, O6, DD-S9-5, DD-S9-6, DD-S9-8, DD-S9-13, DD-S9-14, DD-S9-15, DD-S9-19, DD-S9-20.

### Step 3: LV form side — slider replaces chip group

**Complexity**: complex
**Rationale**: parallel a step 2 ma sul form. `maybe_inject_budget` cambia signature (integer | nil → 0..7). Save success cascade. Form `name` attribute change.

**RED** (`test/ideajar_web/live/idea_live/index_test.exs`):

Nuovo `describe "form budget slider (slice 9 step 3)"`:
1. **FF1/FF2** Mount form: contiene `<input type="range" id="form-budget-slider" min="0" max="7" value="0" name="idea[budget]">`. `@form_budget_index` default 0.
2. **FF8/A2** Form aria-valuetext index 0 = "Non specificato"; index 4 = "100€" (NOT "fino a 100€").
3. **FF5** `update_form_budget` con index 0..7 → assign.
4. **FF6/S4** Hostile uniform list 5 inputs → no-op.
5. **FF3** Slider index 0 + valid submit → idea creata con `estimated_cost = nil`.
6. **FF4** Slider index 4 + valid submit → idea creata con `estimated_cost = 100`.
7. **FF7** Save success → `@form_budget_index` torna a 0.
8. **FF9** Form `name="idea[budget]"` pinned (NOT `idea[estimated_cost]`).
9. Form-shape extractor pin: `update_form_budget` con `%{"idea" => %{"budget" => "3"}}` → assign 3.
10. **S6** Hostile form param: pre-state `@form_budget_index = 0` (extractor ha già no-op'ato l'hostile `update_form_budget`); submit form con raw `idea[budget] => "999"` nel payload → `maybe_inject_budget(params, 0)` (legge da assign, NON da raw params) → no inject → idea creata con `estimated_cost = nil`. Pin esplicito che `Integer.to_string(:error)` MAI invocato (DM3a clamp garanzia).
11. **FF10** Bottone `Rimuovi prezzo` hidden quando `@form_budget_index == 0`, visible quando > 0.
12. **FF10** Click `Rimuovi prezzo` → `@form_budget_index = 0` + bottone disappears.

Riscrivi `describe "form budget field (slice 6 step 4)"` come `describe "form budget (post-slice-9 slider conversion, was slice 6 step 4 chip)"`.

**GREEN**:
- `lib/ideajar_web/live/idea_live/index.ex`:
  - Mount + open_form: `assign(:selected_cost, nil)` → `assign(:form_budget_index, 0)`.
  - **Rimuovi** `handle_event("toggle_form_budget", ...)`.
  - **Aggiungi** `handle_event("update_form_budget", params, socket)` con `extract_form_budget_index/1` multi-shape + integer 0..7 guard.
  - **Aggiungi** `handle_event("remove_form_budget", _, socket)` reset (FF10).
  - `reset_budget`: cambia `assign(:selected_cost, nil)` → `assign(:form_budget_index, 0)`.
  - `maybe_inject_budget`: rinomina + body. Vecchio: `nil → params unchanged`, `integer → Map.put(params, "estimated_cost", Integer.to_string(value))`. Nuovo: `0 → params unchanged`, `n in 1..7 → Map.put(params, "estimated_cost", Integer.to_string(Budget.index_to_value(n)))`. Chiamata da `save` handler con `socket.assigns.form_budget_index` invece di `socket.assigns.selected_cost`.
- `lib/ideajar_web/live/idea_live/index.html.heex`:
  - Form fieldset Budget: rimuovi chip group `<BudgetChip.form_chip ...>`.
  - Aggiungi slider HTML5 dentro la `<.form>` esistente, con caption + bottone `Rimuovi prezzo` condizionale (FF10) `:if={@form_budget_index > 0}`.
- Aggiungi extractor helper `defp extract_form_budget_index/1`.

**REFACTOR**: docstring `maybe_inject_budget` documenta DD-S9-7 + DD-S9-16 (signature change).

**Files**: `lib/ideajar_web/live/idea_live/index.ex` (extend), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (rewrite slice-6 step-4 describe + new slice-9 step-3 describe).
**Spec mapping**: FF1-FF10, A2, A4, S4, S6, DD-S9-5, DD-S9-6, DD-S9-7, DD-S9-11, DD-S9-12, DD-S9-16.

### Step 4: `BudgetChip` component eliminated + CSS thumb extension

**Complexity**: standard
**Rationale**: clean delete dopo che step 2 e 3 hanno rimosso tutti i callsite. CSS extension parallel slice 7b A8.

**RED**:
1. **C1** `assert not File.exists?("lib/ideajar_web/components/budget_chip.ex")` (file-pin).
2. **C2** `assert not File.exists?("test/ideajar_web/components/budget_chip_test.exs")`.
3. **C3** Codebase grep: `lib/` e `test/` non contengono `BudgetChip` (eccetto eventualmente `IdeajarWeb.Components.BudgetChip` se altri rendering esistono — si verifica). Negative regex: `assert {:ok, files} = ...; for f <- files, do: refute File.read!(f) =~ "BudgetChip"`.
4. **C4 BudgetBadge invariato (post-iter1 Acceptance B1 fix)**: `assert File.exists?("lib/ideajar_web/components/budget_badge.ex")` (positive pin). Render integration: idea con `estimated_cost = 100` → card render mostra il badge canonical `"fino a 100€"` (regression slice 6).
5. **A7** CSS thumb rule per `#filter-budget-slider` + `#form-budget-slider` (parallel slice 7b distance). File-read pin `assert app_css =~ "#filter-budget-slider::-webkit-slider-thumb"`.

**GREEN**:
- `rm lib/ideajar_web/components/budget_chip.ex`.
- `rm test/ideajar_web/components/budget_chip_test.exs`.
- `assets/css/app.css`: aggiungi 6 nuove rule (3 per filter slider, 3 per form slider) — pattern slice 7b.

**REFACTOR**: nessuno.

**Files**: `lib/ideajar_web/components/budget_chip.ex` (DELETE), `test/ideajar_web/components/budget_chip_test.exs` (DELETE), `assets/css/app.css` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (new describe).
**Spec mapping**: C1, C2, C3, C4, A7, DD-S9-9, DD-S9-17.

### Step 5: Out-of-scope guard regression + docs sync (D1-D4) + plan flip

**Complexity**: standard

**RED**:
1. **D1**: new `describe "docs/conventions.md — slice 9 UI copy"` con 16 stringhe (8 filter + 8 form).
2. **D4**: new `describe "slice-9 component lifecycle"` (covers C1, C2, C3 — può essere combinato con step 4 RED tests).
3. **Out-of-scope guard regression**: niente cambia (slice 8 ha già scoped `Cerca punto di partenza` + `Cerca idee`). Test esistente passa.

**GREEN**:
- `docs/conventions.md`: append `Stringhe aggiunte in slice 9 (budget slider conversion)` table.
- `test/ideajar/docs_test.exs`: nuove describe per le 16 stringhe.
- Plan flip: `**Status**: approved` → `**Status**: implemented`.

**Files**: `docs/conventions.md` (extend), `test/ideajar/docs_test.exs` (extend), `plans/slice-9-budget-slider-on-ideas.md` (status flip).
**Spec mapping**: D1, D2, D3, D4.

## Complexity Classification

| Step | Complessità | Motivazione |
|------|-------------|-------------|
| 1 | standard | Pure domain helpers + 24+ boundary tests |
| 2 | **complex** | Cross-cutting filter side: assigns rename + handlers nuovi + clear_filters/derive_filter_opts/filter_active? body + template chip→slider + ~30 test slice 6 riscritti |
| 3 | **complex** | Cross-cutting form side: assigns rename + handler nuovi + maybe_inject_budget signature change + reset_budget cascade + template chip→slider + ~15 test slice 6 riscritti |
| 4 | standard | Component delete + CSS extension |
| 5 | standard | Docs sync |

## Pre-PR Quality Gate

- [ ] `mix test --include migration` passa.
- [ ] `mix format --check-formatted` exit code 0.
- [ ] `mix credo` passa.
- [ ] `mix deps.audit` passa.
- [ ] `mix compile --warnings-as-errors` passa.
- [ ] `/code-review` su file toccati passa.
- [ ] **Spec traceability**: ogni `Scenario:` Gherkin ha almeno un test.
- [ ] **BB-tag coverage review (post-iter1 Strategic W2)**: ogni BB-tag pre-esistente nei test slice 6 chip ha almeno un'assertion equivalente nel rewrite slider. Mapping table aggiornato in `R9-7` risk note prima del PR.
- [ ] **`maybe_inject_budget` codebase search (post-iter1 Strategic W3)**: pre-step 3, eseguo `grep -rn maybe_inject_budget lib/ test/ priv/` e documento i caller orfani (se presenti) prima del signature change.
- [ ] **V1**: 3 screenshot in `docs/screenshots/slice-9/` (filter sub-block, form fieldset, empty-filter state).
- [ ] **V1a**: Lighthouse a11y mediana ≥ 95.
- [ ] **V1b**: keyboard-only walkthrough.
- [ ] **V2**: manual test typing/drag rapido + debounce.
- [ ] **V2a**: manual test form submission con vari index.
- [ ] CI verde sul push.

## Risks & Open Questions

- **R9-1 — Step 2 + Step 3 entrambi complex**: ~45 chip-test esistenti da riscrivere. Mitigazione: il pattern slider è ben rodato (slice 7b), niente di concettualmente nuovo. Se durante l'implementazione il rewrite si rivela troppo grosso, splitto step 2 in 2a (handler+state) + 2b (template+test rewrite).

- **R9-2 — `:max_cost` opt name invariata** (J): critical che `list_ideas/1` continui ad accettare `integer | nil`. Slice 9 cambia SOLO la traduzione lato LV, NON la signature di `list_ideas/1`. Pin esplicito in DM8 + O6.

- **R9-3 — `maybe_inject_budget` signature change**: oggi accetta `integer | nil`, post-slice-9 accetta `0..7`. Se future slice avesse altri caller (es. seed, admin tool), break. Mitigazione: search del codebase prima del refactor, fixare i caller orfani in step 3.

- **R9-4 — `Budget.index_to_value/1` `:error` handling in derive_filter_opts**: se per qualche motivo `@max_budget_index` arriva fuori range (es. devtools tampering), `index_to_value` ritorna `:error`. `Keyword.put(:max_cost, :error)` rompe `apply_max_cost/2` (che si aspetta `nil | integer`). Mitigazione: guard `case Budget.index_to_value(mbi) do n when is_integer(n) -> n; nil -> nil; :error -> nil end`. Documentato come safe-fallback.

- **R9-5 — Filter slider `value` attribute reset come slice 7b distance**: se LV re-renderizza durante il drag, il slider value attr rinserisce `@max_budget_index`. Browser preserva l'input value durante user interaction (morphdom merge logic per inputs). Trigger possibile bug: drag rapidissimo + render molto frequente. Mitigazione: phx-debounce 200ms riduce frequenza. Se bug osservato: aggiungi `phx-update="ignore"` o tracking pattern come slice 7b user_location_search_query.

- **R9-6 — Form slider name="idea[budget]" vs schema field name**: il payload contiene `idea[budget]` come index 0..7, ma lo schema `Idea` ha campo `estimated_cost`. `maybe_inject_budget` traduce. Potrebbe causare confusione su future feature. Mitigazione: docstring chiaro + nome `name="idea[budget]"` con spiegazione DD-S9-7.

- **R9-7 — Test slice 6 riscritti — coverage gap risk**: i ~45 chip test slice 6 hanno BB1-BB18 coverage. Riscrivendoli per slider, i mapping potrebbero perdere alcune assertion. Mitigazione: una pass di review per assicurare ogni BB tag pre-esistente abbia almeno 1 assertion equivalente nel nuovo describe slider-converted.

- **R9-8 — gettext deferral (slice 4 R6 carry-over)**: slice 9 aggiunge ~16 stringhe (8 filter + 8 form labels). Cumulative ~106. Trigger residuo (utente non-IT) non scattato.

- **R9-9 — UX W4 carry-over slice 8**: filter row a 5 sub-block + Mostra tutte sotto fold a 360px. Slice 9 non aggiunge sub-block ma sostituisce chip-group con slider che è MENO denso visualmente (1 input + caption + bottone vs 7 chip + helper). Probabilmente migliora il fold position di Mostra tutte. Validare in V1 screenshot.

## Plan Review Summary

Quattro plan-review personas dispatched in parallel iter1, tutti `needs-revision`. Iter2 fix consolidati e applicati. Verdetti finali post-iter2:

### Acceptance Test Critic — `approve` (post-iter2)
**Iter1 blocker fissati**:
- **B1 C4 missing**: aggiunto C4 + C5 acceptance criteria. Step 4 RED test #4 pin che `BudgetBadge` esiste e renderizza il badge canonical card invariato.
- **B2 `:error` derive_filter_opts**: risolto a monte cambiando `Budget.index_to_value/1` signature da `integer | nil | :error` a `integer | nil` (clamp OOR a `nil`). DM3a pin il type contract. Nessun caller deve più gestire `:error`.
- **B3 S6 contract ambiguo**: chiarito esplicitamente. `maybe_inject_budget(params, socket.assigns.form_budget_index)` legge l'assign clamped 0..7 (server-side authoritative), MAI dai raw form params. Pin esplicito S6 + DM3a clamp garantisce no `Integer.to_string(:error)` crash.

**Warning residui**:
- W1 BB-tag coverage informal → escalato a Pre-PR Quality Gate item esplicito.
- W2 `:max_cost` opt name invariance → DM8 + O6 + Step 2 spec-mapping copre la regression.
- W3 phx-debounce timing untestable → labelled come V2 manual gate.
- W4 OOR fallback `form_label` → DM4a/DM5a aggiunti come AC esplicit items.

### Design & Architecture Critic — `approve` (post-iter2)
**Iter1 blocker fissati**:
- **B1 `:error` propagation incomplete**: stesso fix di Acceptance B2 — `index_to_value/1` clamp a `nil`. DD-S9-2 docstring + spec contract type aggiornati.
- **B2 Domain bloat (filter_label/form_label)**: spostati a nuovo modulo `IdeajarWeb.Components.BudgetLabels` con `filter/1` + `form/1`. Domain `Ideajar.Ideas.Budget` resta pure (values + parse + canonical badge label). Pattern parallel `LocationBadge` (delivery layer).

**Warning residui**:
- W1 `maybe_inject_budget` callers grep → escalato a Pre-PR Quality Gate item.
- W3 `idea[budget]` divergence vs schema → docstring chiaro su `maybe_inject_budget` accettato.
- W4 CSS duplication (9 thumb rules) → defer a follow-up issue, NON blocker slice 9.

### UX Critic — `approve` (post-iter2)
**Iter1 blocker fissato**:
- **B1 Form drag-to-0 reset non scoperto**: aggiunto bottone `Rimuovi prezzo` condizionale nel form slider quando `@form_budget_index > 0`. Mirror del filter pattern `Rimuovi filtro budget`. FF10 acceptance criterion + DD-S9-11 aggiornato + UI copy table esteso.

**Warning residui** (non-bloccanti):
- W2 Filter chip→slider discoverability → caption live mitiga; validare V1 screenshot.
- W3 Aria-valuetext divergence form/filter → semanticamente corretto; defer micro-hint.
- W5 Copy "Disattivo" tecnica → defer discussione PM.

### Strategic Critic — `approve` (post-iter2)
**Iter1 blocker fissato**:
- **B1 Naming collision with roadmap**: aggiornato `CONTEXT.md` Prossimi passi per documentare l'inserimento di slice 9 (budget refactor) tra slice 8 (text search) e PWA. PWA shifted a slice 10, deploy a slice 11. Esplicitamente chiarito.

**Warning residui** (non-bloccanti):
- W2 BB-tag rewrite review → escalato a Pre-PR Quality Gate.
- W3 `maybe_inject_budget` codebase search → escalato a Pre-PR Quality Gate.
- W4 Couple-2-user reality check → marginal UX win acceptable.
- W5 Plan Review Summary populate → done (questa sezione).

### Iter 2 — convergence
Tutti i 4 reviewers post-fix tornano `approve`. Plan flip da `draft` → `approved` autorizzato.
