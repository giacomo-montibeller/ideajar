# Plan: Slice 6 — Budget on ideas + budget filter

**Created**: 2026-04-29
**Branch**: main (trunk-based)
**Status**: approved
**Spec**: `docs/specs/budget-on-ideas.md`

## Build conventions (carried from slice 1-5)

- **Strict TDD** — RED → GREEN → REFACTOR per step.
- **Ogni commit** attraverso la skill `commit-message`.
- Pre-step gate locale: `mix compile --warnings-as-errors`, `mix format --check-formatted` (verifica explicita exit code), `mix credo`, `mix deps.audit`, `mix test --include migration`. Stessi gate in CI.
- Domain in `Ideajar.*`, delivery in `IdeajarWeb.*`.
- UI copy in italiano canonica appesa a `docs/conventions.md` nello step 10 commit (ultimo step, parallelo slice 5).
- Trunk-based su `main`, no feature branches; ogni step lascia il codebase in stato green committable.

## Goal

Introdurre il concetto **fascia di prezzo** sulle idee come campo
opzionale `:integer` (bucket discreto a 7 valori: 0, 20, 50, 100, 200,
500, 1000) e aggiungere un filtro cumulativo "fino a X" 2-state nella
filter row sopra la lista, accanto ai filtri categoria (slice 4) e
durata (slice 5). Form e filter usano gli stessi 7 chip, single-select.
Filtro semantica: `WHERE estimated_cost <= ^value AND IS NOT NULL`
(NULL-exclude uniforme con slice 5 durata).

Slice 6 chiude due refactor trigger di slice 5:
- **R5-1 → `Ideajar.Ideas.Filter` modulo dedicato** (rule of 4 fires con required + optional + durations + max_cost).
- **R5-2 → `IdeajarWeb.Components.ChipBase`** (3° chip family fires con BudgetChip).

Slice 6 introduce il **3° rover RovingTabindex** sulla filter row
budget e aggiunge un nuovo budget badge sulla idea card.

**Decisione UX significativa**: slice 6 **rimuove completamente il
filter-status live-region** introdotto in slice 4 ed esteso in slice 5.
Conseguenze cascade:
- `IdeajarWeb.Pluralization` modulo eliminato (orphan).
- `@last_filter_action_prefix` / `@last_filter_action_suffix` assigns rimossi.
- Action prefix/suffix logic rimossa da `cycle_filter`, `toggle_duration_filter`, `clear_filters`.
- Slice 4 A4/A16 e slice 5 A5/A13/AA9/AA20 → **deprecated**.
- 23 test slice 4/5 che asseriscono live-region content → riscritti per asserire l'assenza.

Fuori scope: `lat/lng/location_name` e mappa (slice 7), filtro distanza
(slice 7), text search (slice 8), sort per costo, modifica
`estimated_cost` su idea esistente, valuta diversa da euro, custom
budget value (utente NON può inserire `175€` — bucket only).

## Decisioni architetturali pre-build

- **BB1 — 7 chip simmetrici tra form e filter**: `Budget.values/0` =
  `[0, 20, 50, 100, 200, 500, 1000]`. Stessa whitelist usata da
  `BudgetChip.form_chip/1` e `BudgetChip.filter_chip/1`. Niente
  `filter_values/0` separato (era nello spec iter 1, eliminato dopo
  decisione utente di simmetria con NULL-exclude). Single source.
- **BB2 — Schema `estimated_cost` come `:integer`**: `add :estimated_cost, :integer, null: true`. SQLite stora INTEGER. Whitelist enforced lato changeset via `validate_inclusion(:estimated_cost, Budget.values())` con custom error `"Budget non valido"`. **PLUS — cast-error rewrite (parallelo AA22 di slice 5)**: il cast `:integer` di Ecto fallisce su input non-numerici (`"abc"`, `"<script>"`) con il default `"is invalid"`. Per uniformare il messaggio a `"Budget non valido"`, aggiungere helper privato `override_estimated_cost_error/1` (parallelo a `override_duration_error/1`):
  ```elixir
  defp override_estimated_cost_error(%Ecto.Changeset{errors: errors} = cs) do
    case Keyword.get(errors, :estimated_cost) do
      {"is invalid", opts} ->
        new_errors = Keyword.put(errors, :estimated_cost, {@cost_invalid, opts})
        %{cs | errors: new_errors}
      _ -> cs
    end
  end
  ```
  Pipeline: `cast(...) |> override_duration_error() |> override_estimated_cost_error() |> validate_inclusion(...) |> ...`. Il `validate_inclusion` cattura "valid-cast-but-out-of-whitelist" (es. `"175"` → `175`); l'override cattura cast failures (`"abc"`, `"<script>"`); insieme coprono tutti i casi RED step 3.c (#4, #5, #6, #7).
- **BB3 — `Ideajar.Ideas.Budget` modulo puro**: `values/0`, `parse/1` (cast string → int + whitelist check, no raise), `label/1` (`0 → "gratis"`, `20-500 → "fino a <n>€"`, `1000 → "oltre 1000€"`). Single source per validation form, filter, badge, hostile-input handler.
- **BB4 — `Ideajar.Ideas.Filter` modulo dedicato (R5-1 extraction)**: rule of 4 fires. `apply_filters/2` privata di `Ideajar.Ideas` (slice 5) viene estratta come `Ideajar.Ideas.Filter.apply/2` public. Helpers `apply_required/2`, `apply_optional/2`, `apply_durations/2` migrano insieme. Slice 6 aggiunge `apply_max_cost/2`. Public function permette unit test diretti senza Repo round-trip.
- **BB5 — `IdeajarWeb.Components.ChipBase` extraction (R5-2)**: 3° chip family fires. `chip_base_class/0` privata duplicata in `CategoryChip` + `DurationChip` viene estratta in `IdeajarWeb.Components.ChipBase` come public function. Tutti i 3 chip family riallineati: `import IdeajarWeb.Components.ChipBase` o call esplicito.
- **BB6 — Form duration state via assigns separato `@selected_cost :: integer | nil`**: parallelo al pattern slice 5 `@selected_duration` (AA5). Reset on mount, open form, close form, save success.
- **BB7 — Filter state come `@cost_filter :: integer | nil`**: single int (non MapSet), perché single-select 2-state. Filtro inactive quando `nil`. Toggle off via clic su chip pressed; swap via clic su chip diverso.
- **BB8 — NULL-exclude uniforme con slice 5 durata**: `WHERE estimated_cost <= ^max AND estimated_cost IS NOT NULL`. Empty/nil opt = clausola inattiva (NULL-pass implicit). Pattern uniforme con slice 5 durata. CONTEXT.md `Decisione su filtri non applicabili` rivista per documentare l'uniformità.
- **BB9 — Live-region filter-status RIMOSSO completamente (cascade)**:
  - Template `index.html.heex`: rimosso `<div role="status" aria-live="polite" id="filter-status">`.
  - LV `index.ex`: rimosso `@last_filter_action_prefix`, `@last_filter_action_suffix`. Handler `cycle_filter`, `toggle_duration_filter`, `clear_filters` cleanati da action prefix/suffix logic.
  - `lib/ideajar_web/pluralization.ex` eliminato (file rimosso).
  - `test/ideajar_web/pluralization_test.exs` eliminato.
  - Slice 4 A4/A16 e slice 5 A5/A13/AA9/AA20 marker deprecated in `docs/conventions.md`.
  - 23 reference live-region in `test/ideajar_web/live/idea_live/index_test.exs` migrate (delete o riscrittura come "no live-region").
- **BB10 — Step ordering — live-region removal PRIMA del filter UI**: step 7 (live-region removal cascade) viene eseguito dopo step 6 (list_ideas max_cost) e PRIMA di step 8 (BudgetChip filter_chip + sub-block + handler). Razionale: step 8 introduce `toggle_budget_filter` handler — se la live-region fosse ancora presente, step 8 dovrebbe propagare action prefix logic per budget e poi step 7 la rimuoverebbe (waste). Meglio eliminare la live-region in step 7, poi step 8 introduce il budget filter senza live-region per design.
- **BB11 — Refactor steps prima del feature work**: step 1 (ChipBase) e step 2 (Filter) sono refactor puri PRIMA dei feature step (3+). Razionale: ChipBase è prerequisite per BudgetChip (step 4); Filter extraction è prerequisite per il `apply_max_cost/2` di step 6. Refactor first riduce churn nei feature step.
- **BB12 — `chip_base_class/0` deletion da CategoryChip + DurationChip**: dopo l'extraction in step 1, le definizioni private duplicate in `CategoryChip` e `DurationChip` vanno eliminate (sostituite da `ChipBase.chip_base_class()` call). Pinato in step 1 RED come "no `defp chip_base_class` rimane in CategoryChip o DurationChip".
- **BB13 — `Filter` extraction conservativa (3 clausole, no anticipation)**: step 2 estrae le 3 clausole esistenti (required + optional + durations) in `Filter.apply/2`. Step 6 aggiunge `apply_max_cost/2` come 4ª clausola. Refactor minimal in step 2; extension in step 6.
- **BB14 — Aria-label uniforme**: tutti i 7 filter chip on hanno `aria-label "<label> attiva"` dove `<label>` è il chip label canonico (`gratis`, `fino a 20€`, …, `oltre 1000€`). Niente special-case per gratis o oltre 1000€. Off: `aria-label "<label>"`.
- **BB15 — Filter formula SQL pinata via `Ecto.Adapters.SQL.to_sql/2`**: O2 acceptance criterion. SQL emesso da `Filter.apply(query, [max_cost: 100])` deve contenere `~r/"estimated_cost"\s+<=/i` AND `~r/IS\s+NOT\s+NULL/i`. Robust a quoting style change.
- **BB16 — Migration test data preservation roundtrip (BB-DR)**: parallelo a slice 5 step 2 B3 fix. Pre-rollback insert con value valido + value NULL. Down → rows preserved (only column dropped). Up → column reset NULL. Documentato nel test.
- **BB17 — DOM id namespacing budget**: form chip `id="form-budget-chip-<value>"` (es. `form-budget-chip-100`), filter chip `id="filter-budget-chip-<value>"`. Distinct dai chip slice 3/4/5. Pinato in step 4/8 RED.
- **BB18 — Out-of-scope guard pull-forward**: step 8 (BudgetChip filter_chip) introduce `Budget` nel DOM (sub-block label, helper text). Lo step 8 deve aggiornare il guard regex `refute html =~ ~r/Distanza|Cerca/i` (rimuove `Budget`) e aggiungere asserzione positiva `Budget` presente nel sub-block. Pull-forward pattern dallo slice 5 step 6 (era pianificato per step 9, anticipato per evitare test failure transient).
- **BB19 — gettext deferral confermato (slice 4 R6 + slice 5 R5-8)**: slice 6 aggiunge ~14 stringhe canoniche (7 chip + label + sub-label + aria + helper + badge + errore) ma rimuove ~13 stringhe live-region (deprecation). Net ~+1. Trigger residuo (utente non-IT) non scattato.

## Acceptance Criteria

> Mappatura uno-a-uno con `docs/specs/budget-on-ideas.md`.

### Functional / behavioral

- [ ] **F1** — Tutti gli scenari Gherkin automatabili passano (DataCase + LiveViewTest).
- [ ] **F2** — Schema: `Idea.changeset/2` accetta `estimated_cost` come stringa numerica, NULL ammesso, error `"Budget non valido"` per non-int o out-of-whitelist o negative.
- [ ] **F3** — Submit form senza budget chip → idea persistita con `estimated_cost: nil`.
- [ ] **F4** — Submit form con `gratis` → `estimated_cost: 0`.
- [ ] **F5** — Submit form con `oltre 1000€` → `estimated_cost: 1000`.
- [ ] **F6** — Single-select form: cliccando chip diverso, precedente ritorna a `aria-pressed="false"`.
- [ ] **F7** — Toggle off form: cliccando chip pressed, ritorna a `false` e `@selected_cost = nil`.
- [ ] **F8** — `Ideas.list_ideas([])` invariato dalla slice 5 (regression).
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
- [ ] **F20** — New idea outside active budget filter is hidden (cost > max o cost NULL — entrambi nascosti, NULL-exclude uniform).

### Filter row layout

- [ ] **L1** — Filter row contiene 3 sub-block in DOM source order: Categorie → Durata → Budget.
- [ ] **L2** — Filter chip budget count: esattamente 7 (simmetrico al form).
- [ ] **L3** — Form fieldset Budget contiene 7 chip.

### Accessibility

- [ ] **A1** — Form chip ha `aria-pressed="true|false"` corretto, derivato da `@selected_cost`.
- [ ] **A2** — Filter chip ha `aria-label` esattamente `<label>` (off) o `<label> attiva` (on). I label sono i 7 canonici.
- [ ] **A3** — Filter chip ha `data-budget-filter-state` esattamente `off` o `on`.
- [ ] **A4** — Cue visivo non-color (WCAG 1.4.11): off = no icon, on = `<.icon name="hero-check" />`.
- [ ] **A5 (CRITICAL — slice 6 deprecation)** — Live-region filter-status RIMOSSO dal DOM. Verifica regression: `refute html =~ ~r/role="status"/` AND `refute html =~ ~r/aria-live="polite"/` scoped al filter row.
- [ ] **A6** — Roving tabindex budget: ArrowRight/ArrowLeft cycling within group (con wrap), Tab esce, primo chip `tabindex=0` altri `-1`.
- [ ] **A7** — Form chip budget: nessun rover, tab order standard.
- [ ] **A8** — Hit area chip ≥ 44×44 CSS px (via `ChipBase.chip_base_class/0`).
- [ ] **A9** — Sub-group ARIA: `<div role="group" aria-label="Filtra per budget">` con sub-label visivo `Budget`.
- [ ] **A10** — DOM id distinctness: `form-budget-chip-<value>`, `filter-budget-chip-<value>`. Distinct dai chip slice 3/4/5.
- [ ] **A11** — Helper text NULL-exclusion: filter row sub-block budget contiene sempre `Le idee senza prezzo sono nascoste quando un filtro è attivo.`

### Security / robustness

- [ ] **S1** — `toggle_budget_filter` con cost out-of-whitelist (`"175"`, `"-50"`) o non-numeric (`"abc"`, `""`) o non-string (42, [], %{}) → no-op silenzioso.
- [ ] **S2** — `toggle_form_budget` idem (whitelist 7 valori).
- [ ] **S3** — Save con `estimated_cost` manomessa via devtools/curl → changeset error `"Budget non valido"`, idea non persistita.
- [ ] **S4** — `Budget.parse/1` non lancia su input arbitrari.
- [ ] **S5** — XSS regression badge: `Budget.label/1` hard-coded, no path injection. Test sintetico via mock.
- [ ] **S6** — Mutua esclusione type-level dei due ARIA contracts in `BudgetChip`.
- [ ] **S7** — `clear_filters` è idempotente quando tutti i filtri sono già off; no error, no state change. Pinato in step 9 RED #2 (W1 fix iter 2).

### Operational / data

- [ ] **O1** — Migration `AddEstimatedCostToIdeas` reversibile loss-free pre-popolamento. SQLite ALTER TABLE.
- [ ] **O2** — Data preservation across rollback: pre-rollback insert valid + NULL → down preserves rows (only column dropped) → up resets column NULL.
- [ ] **O3** — `Ecto.Adapters.SQL.to_sql/2` su `list_ideas([max_cost: 100])` → SQL contiene `~r/"estimated_cost"\s+<=/i` AND `~r/IS\s+NOT\s+NULL/i`.
- [ ] **O4** — Performance sanity: list_ideas con 4 filter attivi <100ms su 100 idee.
- [ ] **O5** — `Ideajar.Ideas.Filter.apply/2` testato indipendentemente con unit test su ogni clausola.

### Refactor (R5-1, R5-2 satisfaction)

- [ ] **R1** — `Ideajar.Ideas.Filter` modulo esiste, esporta `apply/2`.
- [ ] **R2** — `Ideajar.Ideas.list_ideas/1` delega filter chain a `Filter.apply/2`.
- [ ] **R3** — Tutti i test slice 4/5 list_ideas/1 passano invariati (regression).
- [ ] **R4** — `IdeajarWeb.Components.ChipBase` modulo esiste con `chip_base_class/0` public.
- [ ] **R5** — `CategoryChip`, `DurationChip`, `BudgetChip` riusano `ChipBase.chip_base_class/0`. Nessun `defp chip_base_class` privato rimane.

### Live-region deprecation (slice 6)

- [ ] **D-LR1** — `<div role="status" aria-live="polite" id="filter-status">` assente dal DOM.
- [ ] **D-LR2** — `IdeajarWeb.Pluralization` modulo + relativo test eliminati.
- [ ] **D-LR3** — `@last_filter_action_prefix` e `@last_filter_action_suffix` rimossi.
- [ ] **D-LR4** — Handler `cycle_filter`, `toggle_duration_filter`, `clear_filters` cleanati.
- [ ] **D-LR5** — Test slice 4/5 che asserivano live-region content → riscritti come "no live-region present" o eliminati. Lista esplicita nel step 7.

### Validation venue

- [ ] **V1** — 4 screenshot mobile (iPhone 13 + Pixel 7 + 360px Pixel 4a).
- [ ] **V1a** — Lighthouse a11y mediana ≥95.
- [ ] **V1b** — Keyboard-only walkthrough: 3 rover indipendenti, form chip Tab order, no live-region.

### Documentation

- [ ] **D1** — `docs/conventions.md` UI copy table aggiornata con stringhe slice 6.
- [ ] **D2** — `docs/conventions.md` slice 4/5 marker deprecation per stringhe live-region.
- [ ] **D3** — `CONTEXT.md` `## Decisione su filtri non applicabili` esteso per documentare uniformità NULL-exclude.
- [ ] **D4** — `test/ideajar_web/live/idea_live/index_test.exs` out-of-scope guard regex aggiornato.
- [ ] **D5** — `test/ideajar/docs_test.exs`: nuova `describe "slice-6 UI copy"` + `describe "live-region deprecation"`.

### UI copy aggiunta (canonical)

| Elemento | Testo IT |
|---|---|
| Label fieldset budget (form) | `Budget` |
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
| Aria-label filter chip off | `<label>` |
| Aria-label filter chip on | `<label> attiva` |
| Badge budget su idea card | `<label>` (uguale al chip) |

## Steps

### Step 1: REFACTOR — `IdeajarWeb.Components.ChipBase` extraction (R5-2)

**Complexity**: standard
**Rationale**: prerequisite per BudgetChip (step 4). Refactor puro, no behavior change.

**RED** (`test/ideajar_web/components/chip_base_test.exs` new + regression):
1. `ChipBase.chip_base_class/0` returns `"min-h-11 min-w-11 px-3 py-2 rounded-full border-2 inline-flex items-center gap-1 text-sm"` (verbatim from current private duplicates).
2. **Regression pin**: `lib/ideajar_web/components/category_chip.ex` does NOT contain `defp chip_base_class` (post-refactor invariant).
3. **Regression pin**: `lib/ideajar_web/components/duration_chip.ex` does NOT contain `defp chip_base_class`.
4. **Behavior preservation**: existing CategoryChip + DurationChip render tests continue to pass with identical output.

**GREEN**:
- New `lib/ideajar_web/components/chip_base.ex`:
  ```elixir
  defmodule IdeajarWeb.Components.ChipBase do
    @moduledoc """
    Shared visual base class for the chip family components.

    Slice 6 R5-2 extraction. Previously duplicated as `defp
    chip_base_class/0` in CategoryChip + DurationChip; now single source
    so future chip families (BudgetChip slice 6, distance/budget chips
    slice 7+) reuse uniformly.
    """

    @spec chip_base_class() :: String.t()
    def chip_base_class do
      "min-h-11 min-w-11 px-3 py-2 rounded-full border-2 inline-flex items-center gap-1 text-sm"
    end
  end
  ```
- Update `lib/ideajar_web/components/category_chip.ex`: 
  - `alias IdeajarWeb.Components.ChipBase` near top (Design W2: alias-qualified, NOT import — evita shadowing risk se in futuro un chip module dichiarasse un local `chip_base_class/0`).
  - Sostituisci ogni `chip_base_class()` con `ChipBase.chip_base_class()`.
  - Rimuovi `defp chip_base_class do ... end` lines.
- Update `lib/ideajar_web/components/duration_chip.ex`: idem (alias + qualified call).

**REFACTOR**: verify Credo no issues. Verify no other duplicate of the class string.

**Files**: `lib/ideajar_web/components/chip_base.ex` (new), `lib/ideajar_web/components/category_chip.ex` (cleanup), `lib/ideajar_web/components/duration_chip.ex` (cleanup), `test/ideajar_web/components/chip_base_test.exs` (new).
**Spec mapping**: R4, R5, BB5, BB12.

### Step 2: REFACTOR — `Ideajar.Ideas.Filter` module extraction (R5-1)

**Complexity**: standard
**Rationale**: prerequisite per `apply_max_cost/2` (step 6). Refactor puro, no behavior change.

**RED** (`test/ideajar/ideas/filter_test.exs` new + regression):
1. `Filter.apply/2` exists with signature `(Ecto.Query.t(), keyword()) :: Ecto.Query.t()`.
2. `Filter.apply(query, [])` returns the query unchanged (no-op).
3. **Regression pin**: `lib/ideajar/ideas.ex` does NOT contain `defp apply_filters` (extraction complete).
4. **Behavior preservation**: ALL existing `list_ideas/1` tests (slice 4 + slice 5) pass invariati.
5. **Direct `Filter.apply/2` unit test (test seam)**: `Filter.apply(base_query, required: [id])` produces same SQL/result as the slice-4 inline test.

**GREEN**:
- New `lib/ideajar/ideas/filter.ex`:
  ```elixir
  defmodule Ideajar.Ideas.Filter do
    @moduledoc """
    Pure filter composition for ideas listing.

    Slice 6 R5-1 extraction. Previously `apply_filters/2` private in
    `Ideajar.Ideas`; promoted to public module to allow direct unit test
    and to host the 4th clause (`apply_max_cost/2`) without further
    growth of the context module.
    """

    import Ecto.Query

    @spec apply(Ecto.Query.t(), keyword()) :: Ecto.Query.t()
    def apply(query, opts) when is_list(opts) do
      query
      |> apply_required(Keyword.get(opts, :required, []))
      |> apply_optional(Keyword.get(opts, :optional, []))
      |> apply_durations(Keyword.get(opts, :durations, []))
    end

    # Migrated verbatim from Ideajar.Ideas (slice 4 + 5) — no behavior change.
    defp apply_required(query, []), do: query
    defp apply_required(query, ids), do: ...

    defp apply_optional(query, []), do: query
    defp apply_optional(query, ids), do: ...

    defp apply_durations(query, []), do: query
    defp apply_durations(query, durations), do: ...
  end
  ```
- Update `lib/ideajar/ideas.ex`:
  - Remove `defp apply_filters/2`, `defp apply_required/2`, `defp apply_optional/2`, `defp apply_durations/2`.
  - `list_ideas/1` body becomes:
    ```elixir
    base_query = from i in Idea, order_by: [desc: i.inserted_at, desc: i.id]
    
    base_query
    |> Ideajar.Ideas.Filter.apply(opts)
    |> Repo.all()
    |> Repo.preload(categories: Categories.preload_query())
    ```

**REFACTOR**: alias `Ideajar.Ideas.Filter, as: Filter` per leggibilità. Verify Credo.

**Files**: `lib/ideajar/ideas/filter.ex` (new), `lib/ideajar/ideas.ex` (cleanup), `test/ideajar/ideas/filter_test.exs` (new).
**Spec mapping**: R1, R2, R3, BB4, BB13.

### Step 3: Schema migration + `Budget` module + changeset

**Complexity**: standard
**Rationale**: parallelo a slice 5 step 2 (Duration). Pure backend, well-defined.

**RED**:

a. **`test/ideajar/migrations_test.exs`** extension:
1. Add `@add_estimated_cost_migration Ideajar.Repo.Migrations.AddEstimatedCostToIdeas`, `@add_estimated_cost_version 20_260_429_000_001`, path block, `Code.require_file` guard.
2. Setup: extend `delete_versions/0`, on_exit restoration order extended.
3. New test "add_estimated_cost migration is reversible and adds INTEGER NULLABLE": up → PRAGMA `estimated_cost` row with `type=INTEGER`, `notnull=0`. Down → row absent. Up → row reappears.
4. New test "accepts integer values and NULL on insert": insert with cost=100 and cost=NULL → roundtrip.
5. **BB16 data preservation across rollback**: pre-rollback insert 2 rows (cost=100 + cost=NULL). Down → COUNT==2 + title/description intact. Up → both rows have cost=NULL.

b. **`test/ideajar/ideas/budget_test.exs`** (new):
1. `Budget.values() == [0, 20, 50, 100, 200, 500, 1000]`
2. `Budget.parse(s) == {:ok, int}` for each canonical (7 cases): `"0"` → `{:ok, 0}`, `"20"` → `{:ok, 20}`, etc.
3. `Budget.parse/1` returns `:error` for: `"175"`, `"-50"`, `"abc"`, `""`, `nil`, `42` (integer non-string), `[]`, `%{}`.
4. `Budget.label/1` for each value: `0 → "gratis"`, `20 → "fino a 20€"`, `50 → "fino a 50€"`, `100 → "fino a 100€"`, `200 → "fino a 200€"`, `500 → "fino a 500€"`, `1000 → "oltre 1000€"`.
5. **XSS-via-bucket pin**: `for v <- Budget.values(), do: refute Budget.label(v) =~ ~r/[<>&]/`.

c. **`test/ideajar/ideas_test.exs`** new `describe "estimated_cost field"`:
1. valid changeset with `estimated_cost: "100"` → `changes[:estimated_cost] == 100`
2. valid with `estimated_cost: nil` → not in changes
3. valid with `estimated_cost: ""` → not in changes (cast empty to nil)
4. **invalid out-of-whitelist (validate_inclusion path)**: `estimated_cost: "175"` → cast succeeds to 175 → `validate_inclusion` rejects → `errors[:estimated_cost] == {"Budget non valido", _}`.
5. **invalid out-of-whitelist negative**: `estimated_cost: "-50"` → cast succeeds to -50 → `validate_inclusion` rejects → same error.
6. **invalid cast (override_estimated_cost_error path)**: `estimated_cost: "abc"` → cast fails with `"is invalid"` → override rewrites to `"Budget non valido"` → `errors[:estimated_cost] == {"Budget non valido", _}`.
7. **invalid cast XSS-like**: `estimated_cost: "<script>"` → cast fails → override rewrites → same error.
8. **other field errors invariati**: changeset con `estimated_cost: "abc"` AND `title: ""` → entrambi gli errori presenti, `:title` con la sua canonical error e `:estimated_cost` con `"Budget non valido"` (verifica che l'override non interferisca con altri errori).

**GREEN**:

a. New migration `priv/repo/migrations/20260429000001_add_estimated_cost_to_ideas.exs`:
```elixir
defmodule Ideajar.Repo.Migrations.AddEstimatedCostToIdeas do
  use Ecto.Migration
  def change, do: alter table(:ideas), do: add :estimated_cost, :integer, null: true
end
```

b. New module `lib/ideajar/ideas/budget.ex` with `@values`, `@labels`, `values/0`, `parse/1`, `label/1`. Pattern parallel to slice 5 `Duration` module.

c. Update `lib/ideajar/ideas/idea.ex`:
- Aggiungi `field :estimated_cost, :integer` allo schema.
- Aggiungi `:estimated_cost` a `@castable_fields`.
- Aggiungi `@cost_invalid "Budget non valido"`.
- Aggiungi helper privato `override_estimated_cost_error/1` (vedi BB2).
- Aggiungi `validate_inclusion(:estimated_cost, Budget.values(), message: @cost_invalid)` nel changeset, dopo `cast`.
- Pipeline aggiornata:
  ```elixir
  idea
  |> cast(attrs, @castable_fields)
  |> override_duration_error()
  |> override_estimated_cost_error()  # NEW — cast failure path
  |> validate_inclusion(:estimated_cost, Budget.values(), message: @cost_invalid)  # whitelist path
  |> trim_text(:title)
  |> ...
  ```
- Note: NULL ammesso. `validate_inclusion` skipa silently quando il field è nil. Il duplo path (override + validate_inclusion) copre cast failures (non-numerici) E whitelist violations (numerici fuori bucket).

**REFACTOR**: verify Credo. Verify schema introspection: `Idea.__schema__(:type, :estimated_cost) == :integer`.

**Files**: `priv/repo/migrations/20260429000001_add_estimated_cost_to_ideas.exs` (new), `lib/ideajar/ideas/budget.ex` (new), `lib/ideajar/ideas/idea.ex` (extend), `test/ideajar/migrations_test.exs` (extend), `test/ideajar/ideas/budget_test.exs` (new), `test/ideajar/ideas_test.exs` (extend).
**Spec mapping**: F2, F3, F4, F5, S3, S4, BB2, BB3, BB16, O1, O2.

### Step 4: Form `BudgetChip.form_chip` + fieldset + `toggle_form_budget` + persistence

**Complexity**: standard
**Rationale**: parallelo a slice 5 step 3.

**RED**:

a. **`test/ideajar_web/components/budget_chip_test.exs`** new:
1. `form_chip/1` with `pressed?: false, cost: 100` → `<button id="form-budget-chip-100">`, `aria-pressed="false"`, no icon, `phx-click="toggle_form_budget"`, `phx-value-cost="100"`. Class string contains chip-base classes.
2. With `pressed?: true` → `aria-pressed="true"`, `<.icon name="hero-check" />` present.
3. IT label rendered: `cost: 100` → `fino a 100€`. `cost: 0` → `gratis`. `cost: 1000` → `oltre 1000€`.
4. **S6 type-level**: `form_chip/1` no `state` attr.
5. Hit area: class includes `min-h-11 min-w-11`.

b. **LV test `index_test.exs`** new `describe "form budget field (slice 6 step 4)"`:
1. After form open: render contains `<fieldset>` con `<legend>Budget</legend>` (no asterisk) + 7 form-budget-chip.
2. `view.assigns.selected_cost == nil` post-mount.
3. Click `phx-value-cost="100"` → `view.assigns.selected_cost == 100`. Chip `aria-pressed="true"`.
4. Click `cost=100` again → `selected_cost == nil`. All 7 buttons `aria-pressed="false"`.
5. Click `cost=200` when `100` pressed → `selected_cost == 200`. 100 pressed=false, 200 pressed=true.
6. **Save success with budget**: `@selected_cost == 100` + valid form → idea persisted with `estimated_cost: 100`. `@selected_cost` reset to `nil` post-save.
7. **Save success without budget**: idea persisted with `estimated_cost: nil`.
8. **`close_form` reset**: `@selected_cost` reset on close.
9. **Open form resets**: parallelo a `reset_categories/1`.
10. **Hostile uniform list (S2)**: 8 inputs (5 strings `"175"`, `"-50"`, `"abc"`, `""`, `"<script>"` + 3 non-string `42`, `[]`, `%{}`). Each → `selected_cost` invariato.
11. **Save with hostile cost (S3)**: payload `idea: %{title: "X", category_ids: ..., estimated_cost: "175"}` → re-render with error `"Budget non valido"`.
12. **DOM id distinctness (BB17, A10)**: form open → 5 form-duration-chip + 7 form-budget-chip + 8 form-category-chip + 8 filter-chip + 5 filter-duration-chip = 33 distinct chip ids (post-step 8 saranno 40).
13. **A7 form chip no-rover**: form fieldset budget no `phx-hook="RovingTabindex"`. 7 form-budget-chip no explicit `tabindex`.

**GREEN**:

a. New `lib/ideajar_web/components/budget_chip.ex` with `form_chip/1`. Reuse `IdeajarWeb.Components.ChipBase.chip_base_class/0`.

b. Extend `lib/ideajar_web/live/idea_live/index.ex`:
- `alias Ideajar.Ideas.Budget`, `import IdeajarWeb.Components.BudgetChip`
- Mount: `assign(:selected_cost, nil)`
- `handle_event("toggle_form", ...)` open + `close_form` + save success: extend with `assign(:selected_cost, nil)`
- New handler:
  ```elixir
  def handle_event("toggle_form_budget", %{"cost" => raw}, socket) when is_binary(raw) do
    case Budget.parse(raw) do
      {:ok, val} ->
        new_value = if socket.assigns.selected_cost == val, do: nil, else: val
        {:noreply, assign(socket, :selected_cost, new_value)}
      :error ->
        {:noreply, socket}
    end
  end
  def handle_event("toggle_form_budget", _, socket), do: {:noreply, socket}
  ```
- `save` handler: inject `estimated_cost: Integer.to_string(@selected_cost)` (when not nil) into `attrs_with_categories`.

c. Update `lib/ideajar_web/live/idea_live/index.html.heex`: new fieldset `Budget` after `Durata`:
```heex
<fieldset class="fieldset">
  <legend class="label mb-1">Budget</legend>
  <div class="flex flex-wrap gap-2">
    <.form_chip
      :for={cost <- Ideajar.Ideas.Budget.values()}
      cost={cost}
      pressed?={@selected_cost == cost}
    />
  </div>
</fieldset>
```

**REFACTOR**: Verify Credo. Verify DOM source order Categorie → Durata → Budget → Salva.

**Files**: `lib/ideajar_web/components/budget_chip.ex` (new), `lib/ideajar_web/live/idea_live/index.ex` (extend), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `test/ideajar_web/components/budget_chip_test.exs` (new), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: F2-F7, A1, A7, A10, S2, S3, S6, BB2, BB6, BB17.

### Step 5: Idea card budget badge + XSS regression

**Complexity**: trivial
**Rationale**: rendering condizionale puro.

**RED**:
1. **F17 conditional render — present**: idea with `estimated_cost: 100` → render contiene `<span data-testid="idea-budget-badge">fino a 100€</span>`.
2. **F17 absent**: idea with NULL → no badge for that idea.
3. **Multi-idea**: 2 idee, una con cost, una senza → exactly 1 badge.
4. **F18 each canonical label**: parametric — for each `Budget.values()` value, insert idea with cost, mount, assert IT label appears.
5. **AA14 XSS structural pin**: source-pin in `budget_chip.ex` — `{Budget.label(@cost)}` present, `raw(` absent, `Phoenix.HTML.raw` absent.
6. **Position pin**: badge appears AFTER `<.duration_badge>` in the card DOM (parallel to slice 5 step 4 position pin).

**GREEN**:
- Add `budget_badge/1` to `lib/ideajar_web/components/budget_chip.ex`.
- Update `lib/ideajar_web/live/idea_live/index.html.heex`: inside `<li :for={idea}>`, after `<.duration_badge :if={idea.duration} ... />`, add `<.budget_badge :if={not is_nil(idea.estimated_cost)} cost={idea.estimated_cost} />`.

  **Important — Strategic-fix iter 1**: usare `not is_nil(...)` non `idea.estimated_cost`. Il chip `gratis` salva `cost: 0`, e in Elixir `0` è truthy ma `nil` è falsy — invece in HEEx `:if={0}` rende l'elemento (truthy), `:if={nil}` no. Tuttavia per chiarezza semantica e safety contro futuri cambi del default Boolean coercion, usiamo l'esplicito `not is_nil(...)`. **NB: `0` è truthy in Elixir** (a differenza di JavaScript/Ruby). Ma il check esplicito è più robusto se in futuro il rendering passa attraverso truthy-coercion in qualche template helper.

**REFACTOR**: None.

**Files**: `lib/ideajar_web/components/budget_chip.ex` (extend), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend), `test/ideajar_web/components/budget_chip_test.exs` (extend).
**Spec mapping**: F17, F18, S5.

### Step 6: `list_ideas/1 :max_cost` opt + `Filter.apply_max_cost/2` (NULL-exclude)

**Complexity**: complex
**Rationale**: domain layer, NULL-exclude semantica, SQL emission pin.

**RED** (`test/ideajar/ideas/filter_test.exs` extension + `test/ideajar/ideas_test.exs` extension):

Setup: build the 6-idea fixture matching the spec Background.

1. **F8 regression**: `list_ideas([])` returns all 6.
2. **F9 cumulative ≤100**: `list_ideas([max_cost: 100])` returns `Caffè al volo` (0), `Uffizi` (50), `Stadio` (100). Excludes `Sirolo` (200), `Parigi` (1000), `Bagno` (NULL).
3. **F10 gratis only**: `list_ideas([max_cost: 0])` returns only `Caffè al volo` (cost=0).
4. **F11 all priced (1000)**: `list_ideas([max_cost: 1000])` returns 5 ideas (all priced; NULL excluded).
5. **F12 nil = no filter**: `list_ideas([max_cost: nil])` returns all 6 (NULL incluse).
6. **NULL-exclude strict**: setup with ONLY NULL idea → `list_ideas([max_cost: 100])` → `[]`.
7. **F13 combined 3-way AND**: `list_ideas([required: [@viaggio_id], durations: [:weekend], max_cost: 500])` → only `Sirolo`.
8. **Slice 4/5 regression**: `list_ideas([required: [...]])` invariato; `list_ideas([durations: [:weekend]])` invariato.
9. **O3 SQL emission pin**: `Filter.apply(base_query, [max_cost: 100])` SQL contains `~r/"estimated_cost"\s+<=/i` AND `~r/IS\s+NOT\s+NULL/i`. Refute `~r/IS\s+NULL\b/i` (no NULL-pass).
10. **Direct unit test on `Filter.apply_max_cost/2`** (test seam via `apply/2` with only `:max_cost` opt).

**GREEN**:
- Extend `lib/ideajar/ideas/filter.ex`:
  ```elixir
  def apply(query, opts) when is_list(opts) do
    query
    |> apply_required(...)
    |> apply_optional(...)
    |> apply_durations(...)
    |> apply_max_cost(Keyword.get(opts, :max_cost, nil))
  end

  defp apply_max_cost(query, nil), do: query
  defp apply_max_cost(query, max) when is_integer(max) do
    from i in query, where: i.estimated_cost <= ^max and not is_nil(i.estimated_cost)
  end
  ```

**REFACTOR**: verify Credo. Module docstring updated to mention 4 clausole.

**Files**: `lib/ideajar/ideas/filter.ex` (extend), `test/ideajar/ideas/filter_test.exs` (extend), `test/ideajar/ideas_test.exs` (extend).
**Spec mapping**: F8-F13, BB8, BB13, BB15, O3, O4, O5.

### Step 7: CRITICAL — Live-region filter-status removal cascade

**Complexity**: complex
**Rationale**: cross-cutting cleanup destrutturante. Tocca slice 4/5 retroattivamente. Inventario migration esplicita.

**RED**:

a. **New regression tests** in `test/ideajar_web/live/idea_live/index_test.exs`:
1. Mount: `refute html =~ ~r/role="status"/`.
2. Mount: `refute html =~ ~r/aria-live="polite"/` scoped al filter row (use Floki to scope to the section).
3. After cycle_filter: same — no live-region updates.
4. After toggle_duration_filter: same.
5. After clear_filters: same. `refute html =~ "Filtri rimossi"`.

b. **Test migration inventory (Design B2 fix — pinata verbatim nel plan, eseguita pre-build)**:

Grep run at plan-write time (2026-04-29):
```
grep -n "live-region\|filter-status\|last_filter_action\|aria-live\|role=\"status\"\|Pluralization\|Filtri rimossi\|opzionale,\|obbligatoria,\|rimossa,\|attiva,\|filtri categoria attivi\|filtri durata attivi\|idee\b" test/ideajar_web/live/idea_live/index_test.exs
```

**Hit list categorizzata** (n=25 nei test files + 4 nel template):

**`test/ideajar_web/live/idea_live/index_test.exs`** (24 hits in 23 distinct tests):

| Line | Description | Action |
|---|---|---|
| 494, 500 | `the success flash sits in an aria-live polite region (A12)` — flash success live-region, NON filter-status | **KEEP** (slice 2 a11y, unrelated to slice 6 removal) |
| 1252-1262 | `describe "live-region count + last action (slice 4)"` block opener + `initial render includes a polite live-region with id filter-status` | DELETE entire describe block (1252-1354) |
| 1264-1271 | `no filter active: live-region has no action prefix` | DELETE (within block) |
| 1273-1280 | `cycle to optional adds 'opzionale,' prefix` | DELETE |
| 1282-1289 | `cycle to required swaps prefix` | DELETE |
| 1291-1298 | `cycle back to off uses 'rimossa,' prefix` | DELETE |
| 1300-1307 | `Mostra tutte produces 'Filtri rimossi,'` | DELETE |
| 1311-1320 | `compound suffix categoria/durata` (1317) | DELETE |
| 1325-1330 | `live-region DOM identity stability` | DELETE |
| 1332-1352 | `form save success clears last action prefix` (F11/A16 lifecycle) | DELETE |
| 1356 | `extract_filter_status/1` private helper | DELETE (unused after block deletion) |
| 2214-2222 | `live-region: cycle weekend on` | DELETE |
| 2225-2233 | `live-region: cycle weekend off` | DELETE |
| 2236-2247 | `compound suffix categoria attivi` | DELETE |
| 2250-2261 | `compound suffix durata attivi` | DELETE |
| 2264-2272 | `Mostra tutte 'Filtri rimossi, 6 idee' no suffix` | DELETE |
| 2342-2370 | `clear_filters resets all + live-region` (slice 5 step 7) | MIGRATE — strip live-region assertion (line 2370 `assert extract_filter_status...`), keep the rest of the test |
| 2490-2506 | `clear_filters live-region has no compound suffix even when both groups were active` (AA20 regression) | DELETE entire test |
| 2540-2563 | `filter-survives-save behavior` (slice 5 F11 invariante) | MIGRATE — strip live-region assertion (line 2563 comment + asserts), keep the test body for the F11 invariante |
| 2026-2030 | helper text NULL-exclusion durata `Le idee senza durata sono nascoste...` | KEEP (slice 5 a11y, NOT live-region) |

Plus add **3 new RED tests** (per BB9 cleanup invariante):
- `mount: refute html =~ ~r/id="filter-status"/`
- `mount: refute html =~ ~r/role="status"/` scoped al filter row
- `cycle_filter does not produce aria-live updates` (negative test with side effect)

**`lib/ideajar_web/live/idea_live/index.html.heex`** (3 hits to remove):
- Lines 102-109 (live-region div block: `<div role="status" aria-live="polite" id="filter-status">...`)
- The `Pluralization.idee_count(...)` call (line 156 in pre-step state)
- `{@last_filter_action_prefix}` and `{@last_filter_action_suffix}` interpolations

**`lib/ideajar_web/live/idea_live/index.ex`** (4 helper sites + 2 assigns to remove):
- `assign(:last_filter_action_prefix, ...)` at mount (line ~38)
- `assign(:last_filter_action_suffix, ...)` at mount (line ~38)
- `cycle_filter` handler body: rimuovi `category_name_by_id`, `cycle_state` (KEEP, è il core), `action_prefix`, `compound_suffix` calls + assigns; reduce to `assign(:filter_state, ...) |> reload_ideas()`.
- `toggle_duration_filter` handler body: idem, drop `duration_action_prefix` + `compound_suffix` calls.
- `clear_filters` handler body: drop `last_filter_action_*` assigns.
- Helper functions to delete: `category_name_by_id/2` (only used by action_prefix), `action_prefix/3`, `duration_action_prefix/2`, `compound_suffix/3`.

**`lib/ideajar_web/pluralization.ex`**: file DELETE.
**`test/ideajar_web/pluralization_test.exs`**: file DELETE.

**Verification post-cleanup**:
- `mix compile --warnings-as-errors` clean (catches orphan imports).
- `grep -r "Pluralization\|last_filter_action\|compound_suffix\|action_prefix" lib/ test/` → zero hits.
- `mix test --include migration` green.

**Pre-step 7 verification (R6-3 mitigation)**:
- Before RED additions: grep `lib/ideajar_web/live/idea_live/index.ex` AND step 3-6 test additions per assicurarsi che nessuno dei test migrati a step 3-6 dipenda da `extract_filter_status/1` o asserisca live-region content. Expected zero hits in step 3-6 (those steps add tests on schema, form, badge, list_ideas — orthogonal to live-region).

**GREEN** (esegue l'inventory pinata in RED.b verbatim):
- Update `lib/ideajar_web/live/idea_live/index.html.heex`: remove live-region `<div role="status" aria-live="polite" id="filter-status">...</div>` block.
- Update `lib/ideajar_web/live/idea_live/index.ex`:
  - Remove `assign(:last_filter_action_prefix, ...)` and `assign(:last_filter_action_suffix, ...)` from mount.
  - `cycle_filter` handler: rimuovi `category_name_by_id`, `action_prefix`, `compound_suffix` calls + assigns. Body: `assign(:filter_state, cycle_state(...)) |> reload_ideas()`.
  - `toggle_duration_filter` handler: rimuovi `duration_action_prefix` + `compound_suffix` calls. Body: `assign(:duration_filter, new_set) |> reload_ideas()`.
  - `clear_filters` handler: drop `last_filter_action_*` assigns. Body in step 7: `assign(:filter_state, %{}) |> assign(:duration_filter, MapSet.new()) |> reload_ideas()`. **NB W5 fix iter 2**: step 7 NON aggiunge `assign(:cost_filter, nil)` qui — quello viene aggiunto in step 9 quando `@cost_filter` viene introdotto come assign (step 8). In step 7 il `clear_filters` resetta solo i 2 filtri esistenti (categoria + durata). Step 8 aggiunge `@cost_filter` al mount; step 9 estende `clear_filters` per resettarlo.
  - Helper functions to delete: `category_name_by_id/2`, `action_prefix/3`, `duration_action_prefix/2`, `compound_suffix/3`.
  - Remove alias/import of `IdeajarWeb.Pluralization`.
- Delete `lib/ideajar_web/pluralization.ex` (file removal).
- Delete `test/ideajar_web/pluralization_test.exs` (file removal).
- Migrate `test/ideajar_web/live/idea_live/index_test.exs` per la inventory list pinata sopra:
  - DELETE entire describe `"live-region count + last action (slice 4)"` (lines 1252-1354 + helper `extract_filter_status/1`).
  - DELETE 5 tests dentro slice-5 step 6 (live-region cycle/compound/Filtri rimossi tests, lines 2214-2272).
  - MIGRATE 2 tests (slice 5 step 7 + step 8 — strip live-region assertions, keep rest).
  - DELETE 1 test (`clear_filters live-region has no compound suffix`, lines 2490-2506).
  - KEEP slice-2 flash success live-region (lines 494, 500) — unrelated.
- Aggiungi 3 new RED → GREEN tests positivi (l'assenza è il behavior atteso): mount `refute id="filter-status"`, `refute role="status"`, post-cycle no aria-live updates.
- **W4 fix iter 2 — MIGRATE test vacuity check**: dopo aver strippato la live-region assertion da ognuno dei 2 test MIGRATE (lines 2342-2370 e 2540-2563), VERIFICARE che il test mantenga almeno un `assert` o `refute` sostantivo (non vuoto). Se la live-region era l'unica assertion del test, il test diventa un no-op verde — riscrivere con asserzione su un altro invariante (e.g., assigns post-clear, lista re-renderizzata, idea persistita) o eliminare il test (con commento di rimozione). Pre-step 7 GREEN: enumerare le assertion superstiti per ognuno dei 2 MIGRATE.

**REFACTOR**: verify no orphan import. Verify `mix compile --warnings-as-errors` clean.

**Files**: `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `lib/ideajar_web/live/idea_live/index.ex` (cleanup), `lib/ideajar_web/pluralization.ex` (DELETE), `test/ideajar_web/pluralization_test.exs` (DELETE), `test/ideajar_web/live/idea_live/index_test.exs` (migrate ~25 tests).
**Spec mapping**: A5, BB9, BB10, D-LR1 to D-LR5.

### Step 8: `BudgetChip.filter_chip` + filter sub-block budget + 3° rover + `toggle_budget_filter`

**Complexity**: complex
**Rationale**: cross-cutting (component + LV handler + template + 3° rover). Più piccolo di slice 5 step 6 perché niente live-region.

**RED**:

a. **`test/ideajar_web/components/budget_chip_test.exs`** new `describe "filter_chip/1"`:
1. `filter_chip/1` `state: :off, cost: 100` → `<button id="filter-budget-chip-100">`, `data-budget-filter-state="off"`, `aria-label="fino a 100€"`, no icon, `phx-click="toggle_budget_filter"`, `phx-value-cost="100"`. **No `aria-pressed`**.
2. `state: :on` → `data-budget-filter-state="on"`, `aria-label="fino a 100€ attiva"`, icon present.
3. **S6 type-level**: `filter_chip/1` no `pressed?` attr.
4. `tabindex` attr default `-1`. With `tabindex: 0` → `tabindex="0"`.
5. IT label rendered for each value (`gratis`, `fino a X€`, `oltre 1000€`).
6. **BB14 aria-label uniformity**: for `cost: 0`, off → `gratis`, on → `gratis attiva`. For `cost: 1000`, off → `oltre 1000€`, on → `oltre 1000€ attiva`.

b. **`index_test.exs`** new `describe "duration filter sub-block (slice 6 step 8)"`:
1. **Sub-block rendered (BB18)**: `<div role="group" aria-label="Filtra per budget" data-roving-tabindex-group="filter-budgets" phx-hook="RovingTabindex" id="filter-budgets-group">` + 7 filter-budget-chip.
2. **Visible sub-label**: `<p class="text-xs">Budget</p>` inside the budget sub-block.
3. **Helper text NULL-exclusion (A11)**: `Le idee senza prezzo sono nascoste quando un filtro è attivo.` exactly once, scoped al budget sub-block.
4. **3° rover (A6)**: only `filter-budget-chip-0` (first) has `tabindex="0"`; other 6 have `-1`.
5. **L2 count**: exactly 7 filter-budget-chip buttons.
6. **L1 sub-block order**: Categorie → Durata → Budget in DOM source order.
7. **F14 cycle 2-state on**: click `cost=100` → `view.assigns.cost_filter == 100`. Render `data-budget-filter-state="on"`, icon present. List filtered.
8. **F14 cycle off**: second click → `cost_filter == nil`, button back to `off`.
9. **F15 swap**: cycle 100 on, cycle 200 → `cost_filter == 200`, 100 off.
10. **F9 filter matching**: cycle 100 → only ideas with `cost <= 100 AND IS NOT NULL` (3 ideas: cost 0/50/100). NULL Bagno exclusa.
11. **F11 all priced (1000)**: cycle 1000 → 5 priced ideas, NULL Bagno excluded.
12. **F10 gratis only**: cycle 0 → only Caffè al volo.
13. **Empty state with budget filter**: filter `gratis` su workspace senza idee gratis → empty-filter state.
14. **Hostile uniform list (S1)**: 8 inputs (`"175"`, `"-50"`, `"abc"`, `""`, `"<script>"`, `42`, `[]`, `%{}`) → `cost_filter` invariato.
15. **BB18 out-of-scope guard pull-forward**:
    - `refute html =~ ~r/Distanza|Cerca/i` (rimuove `Budget` da slice 4/5 negative).
    - `assert html =~ ~r{<p[^>]*class="[^"]*text-xs[^"]*"[^>]*>\s*Budget\s*</p>}` (positive).
16. **Form/filter chip ARIA non collide**: with form open + filter on, render contains both `form-budget-chip-100 ... aria-pressed="..."` AND `filter-budget-chip-100 ... aria-label="..."`.

**GREEN**:
- Extend `lib/ideajar_web/components/budget_chip.ex` with `filter_chip/1` (parallel to slice 5 DurationChip filter_chip).
- LV `index.ex`:
  - Mount: `assign(:cost_filter, nil)`.
  - Handler:
    ```elixir
    def handle_event("toggle_budget_filter", %{"cost" => raw}, socket) when is_binary(raw) do
      case Budget.parse(raw) do
        {:ok, val} ->
          new_value = if socket.assigns.cost_filter == val, do: nil, else: val
          {:noreply, socket |> assign(:cost_filter, new_value) |> reload_ideas()}
        :error ->
          {:noreply, socket}
      end
    end
    def handle_event("toggle_budget_filter", _, socket), do: {:noreply, socket}
    ```
  - `derive_filter_opts/2` extended to `derive_filter_opts/3` (or keyword opts construction): add `max_cost: socket.assigns.cost_filter`.
- Template `index.html.heex`:
  - Add 3rd sub-block with role=group + sub-label + helper text + 7 filter chips + 3rd RovingTabindex hook.
  - Update out-of-scope guard test (BB18).

**REFACTOR**: verify Credo. Verify `tabindex_for_first/2` helper reused (or extract if not yet).

**Files**: `lib/ideajar_web/components/budget_chip.ex` (extend), `lib/ideajar_web/live/idea_live/index.ex` (extend), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `test/ideajar_web/components/budget_chip_test.exs` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: F14, F15, A2, A3, A4, A6, A9, A11, S1, S6, BB7, BB14, BB18.

### Step 9: clear_filters extension + combined 3-way + form/filter isolation

**Complexity**: standard
**Rationale**: parallelo a slice 5 steps 7+8 mergiati.

**RED**:
1. **F16 clear budget reset**: with `@cost_filter == 100`, `@filter_state == %{mare: :required}`, `@duration_filter == MapSet.new([:weekend])` → click `Mostra tutte` → all three reset to defaults. Lista mostra tutte.
2. **S7 idempotency**: clear when all empty → no error.
3. **F13 combined 3-way AND**: filter viaggio required + duration weekend + budget 500 → only `Sirolo`.
4. **Combined 3-way empty state**: combination with no match → empty-filter state.
5. **Mostra tutte single-instance with combined**: parallelo a slice 5 step 7. Filter active + lista non vuota → bottone single. Filter active + lista vuota → bottone in empty-message.
6. **F19 filter survives form submit**: budget filter 200 on + open form + submit valido idea (cost=100) → filter still on, idea visible (cost=100 ≤ 200).
7. **F20 new idea outside filter is hidden**: budget filter 50 on + submit idea with cost=200 → idea NOT in list.
8. **F20 new NULL idea hidden when filter on**: budget filter 50 on + submit idea without budget chip → idea created with cost=NULL but NOT in list (NULL-exclude).
9. **Isolation: Mostra tutte non tocca @selected_cost**: open form, click form chip 100 + cycle filter 200 + click `Mostra tutte` → form chip 100 still aria-pressed=true.
10. **Isolation: toggle_budget_filter non tocca @selected_cost**: idem with single filter toggle.
11. **Refresh resets @cost_filter**: re-mount → `cost_filter == nil`.
12. **Arity change pin (Strategic W2)**: `assert function_exported?(IdeajarWeb.IdeaLive.Index, :filter_active?, 3)` AND `refute function_exported?(IdeajarWeb.IdeaLive.Index, :filter_active?, 2)`. Pinato per evitare drift se uno dei 3 template call sites omette un argomento (compile errors HEEx li catturano comunque, ma il test rende la regression esplicita).

**GREEN**:
- Extend `clear_filters` handler in `lib/ideajar_web/live/idea_live/index.ex`: add `assign(:cost_filter, nil)` to the chain.
- Update `filter_active?/2` → `filter_active?/3`:
  ```elixir
  def filter_active?(filter_state, duration_filter, cost_filter) do
    filter_state != %{} or MapSet.size(duration_filter) > 0 or not is_nil(cost_filter)
  end
  ```
- Update all template `filter_active?` callers in `index.html.heex` (3 places).

**REFACTOR**: None needed. Tests pin existing architecture.

**Files**: `lib/ideajar_web/live/idea_live/index.ex` (extend), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: F13, F16, F19, F20, S7, slice-4 F10, slice-5 invariants.

### Step 10: Docs sync (D1, D2, D3, D4, D5) + plan flip

**Complexity**: standard
**Rationale**: closing gate — UI copy table append, deprecation markers, CONTEXT.md update, plan flip.

**RED**:
1. **D1 UI copy slice 6**: new `describe "docs/conventions.md — slice 6 UI copy"` in `test/ideajar/docs_test.exs` con 14 stringhe canoniche (vedi UI copy aggiunta sopra).
2. **D2 deprecation markers slice 4/5**: new `describe "docs/conventions.md — live-region deprecation markers"` che asserisce presenza di un marker (es. "deprecated slice 6") near le tabelle slice 4 e slice 5 UI copy live-region rows.
3. **D3 CONTEXT.md update**: new `describe "CONTEXT.md — slice 6 NULL-exclude uniform"` che asserisce:
   - `assert content =~ ~r/(NULL|nil).*esclus.*durata.*budget/i` o equivalente che documenta uniformità.
4. **D4 out-of-scope guard already done in step 8**: verify regex aggiornato (rimosso `Budget`, conservati `Distanza|Cerca`).
5. **D5 docs_test.exs**: già parte di D1+D2+D3 sopra.

**GREEN**:
- `docs/conventions.md`:
  - New section `Stringhe aggiunte in slice 6 (budget on ideas)` con tabella verbatim.
  - Marker deprecation accanto a slice 4 + slice 5 live-region tables: `> **DEPRECATED slice 6** — il filter-status live-region è stato rimosso.`
- `CONTEXT.md`:
  - Update `## Decisione su filtri non applicabili`:
    > Per i filtri **durata** (slice 5) e **budget** (slice 6): un'idea con valore NULL viene **esclusa** quando ≥1 chip del rispettivo filtro è on. Pattern uniforme. Razionale: chi filtra sta restringendo attivamente; un'idea senza valore non è "sicuramente non match" ma "non confermata match" → fuori.
    > Per filtri futuri (`distanza` slice 7, `text search` slice 8) la decisione sarà rivalutata caso per caso, ma il default è NULL-exclude.
- Plan flip: `**Status**: approved` → `**Status**: implemented`.

**REFACTOR**: None.

**Files**: `docs/conventions.md` (extend), `CONTEXT.md` (update), `test/ideajar/docs_test.exs` (extend), `plans/slice-6-budget-on-ideas.md` (status flip).
**Spec mapping**: D1, D2, D3, D4, D5.

## Complexity Classification

| Step | Complessità | Motivazione |
|------|-------------|-------------|
| 1 | standard | Refactor puro `ChipBase`, no behavior change |
| 2 | standard | Refactor puro `Filter`, no behavior change |
| 3 | standard | Migration + Budget module + changeset; pattern slice 5 |
| 4 | standard | Form chip + handler + persistence; pattern slice 5 |
| 5 | trivial | Rendering condizionale + structural pin |
| 6 | **complex** | Domain layer NULL-exclude + SQL emission pin |
| 7 | **complex** | Cross-cutting cleanup: live-region removal + ~25 test migration |
| 8 | **complex** | Component + handler + 3° rover + helper text + sub-block |
| 9 | standard | clear_filters extend + regression invariants |
| 10 | standard | Docs sync; nessun cambio strutturale |

## Pre-PR Quality Gate

- [ ] `mix test --include migration` passa.
- [ ] `mix format --check-formatted` passa (verifica explicita exit code).
- [ ] `mix credo` passa.
- [ ] `mix deps.audit` passa.
- [ ] `mix compile --warnings-as-errors` passa.
- [ ] `/code-review` su file toccati passa.
- [ ] **F1 traceability**: ogni `Scenario:` Gherkin ha almeno un test.
- [ ] **V1**: 4 screenshot in `docs/screenshots/slice-6/`.
- [ ] **V1a**: Lighthouse a11y mediana ≥95.
- [ ] **V1b**: keyboard-only walkthrough (3 rover, no live-region).
- [ ] CI verde sul push.

## Risks & Open Questions

- **R6-1 — Filter module saturation post slice 7+**: dopo R5-1 extraction, il modulo `Ideajar.Ideas.Filter` ospita 4 clausole. Slice 7 distance + slice 8 search aggiungeranno fino a 6 totali. Trigger per ulteriore extraction (e.g., separate `DistanceFilter` module): 6+ clausole eterogenee per natura (geospatial vs scalar vs text). Documentato per slice 7+.
- **R6-2 — Live-region removal a11y regression**: SR users perdono l'announcement dei cambi di filtro. Decisione consapevole utente. Trigger per re-introduction: real-user feedback negativo sull'a11y. Mitigation in slice 6: chip aria-label dinamico (off / "X attiva") fornisce feedback contestuale on focus.
- **R6-3 — Test migration in step 7 può rivelare invariants impliciti**: 23 reference live-region in `index_test.exs`; migrazione potrebbe scoprire test che asserivano comportamento NON live-region accidentalmente (e.g., test sull'ordering DOM che usavano la live-region come anchor). Mitigation: review esplicita di ogni test affected, no blanket delete.
- **R6-4 — `Budget.parse/1` accept "0"**: edge case — `String.to_integer("0")` returns `0`; whitelist contains 0; should pass. Test esplicito.
- **R6-5 — CONTEXT.md non-uniformity → uniformity rewrite**: slice 5 step 9 documentò la "non uniformity" lato durata. Slice 6 step 10 riscrive per documentare uniformità. Doc trail: slice 5 closure → slice 6 ri-revisione → coerente con il pattern di slice future.
- **R6-6 — Step 1 + 2 refactor first overhead**: 2 refactor steps senza valore feature visibile. Critique strategic: vale la pena? Trade-off: alternativa è inline refactor in step 4 (BudgetChip) e step 6 (max_cost), che mescola feature + refactor commit-by-commit. Plan sceglie refactor first per pulizia di commit history e per rendere step 4/6 più piccoli.
- **R6-7 — Plan size: 10 step, 3 complex**: parallelo a slice 5 (9 step, 3 complex). Convergenza pattern. Non-trivial slice ma manageable.
- **R6-8 — gettext trigger non scattato**: slice 6 net +1 stringa (rimuove ~13 deprecate, aggiunge ~14 nuove). Cumulative ~55 stringhe canoniche. Trigger residuo (utente non-IT) non scattato.
- **R6-9 — `validate_inclusion` skips silent on nil**: `validate_inclusion(:estimated_cost, [0, 20, ...])` su un changeset con `estimated_cost: nil` non aggiunge error. Comportamento desiderato (NULL valido). Pin in step 3 RED #b.2.
- **R6-10 — Migration 6 SQLite ALTER TABLE**: stessa pattern slice 5 step 2 (SQLite ≥3.35 supporta DROP COLUMN). Pin nel step 3 RED via `PRAGMA table_info`.
- **R6-11 — Step 7 ordering risk**: rimuovere live-region prima di step 8 (filter UI) richiede che step 7 sia preceduto da test che NON dipendano dalla live-region per le invariants di filtering. I test esistenti slice 4/5 di "filter list re-render correctly" devono passare DOPO live-region removal — solo i test sulla live-region content vanno migrati. Mitigation: pre-step 7 categorize tests in 3 buckets (delete / rewrite negative / leave intact).

## Plan Review Summary

> Verdetti iter 1: acceptance **approve** (3 W), design **needs-revision** (2 blocker), UX **approve** (3 W), strategic **approve** (1 required fix).
> Verdetti iter 2 post-fix: tutti e 4 **approve**. Convergenza raggiunta.

### Modifiche di iter 2 rispetto a iter 1

**Design fixes (2 blocker chiusi):**
- **B1 — Cast error parity slice 5**: BB2 esteso con `override_estimated_cost_error/1` helper privato (parallelo a `override_duration_error/1` di slice 5 AA22). Pipeline changeset aggiornata: `cast → override_duration_error → override_estimated_cost_error → validate_inclusion → ...`. Step 3.c RED items 4-7 categorizzati: out-of-whitelist via validate_inclusion path (`"175"`, `"-50"`); cast failure via override path (`"abc"`, `"<script>"`). Item #8 nuovo: verifica non-interference con altri field errors.
- **B2 — Step 7 helper inventory pinata verbatim**: hit list completa con line numbers (24 hits in `index_test.exs` + 4 nei lib files), categorizzata DELETE/MIGRATE/KEEP. Lines 494/500 (slice 2 flash live-region) explicitly KEEP. Step 7 GREEN allineato all'inventory.

**Design warning fix (W2):**
- ChipBase usage: `alias IdeajarWeb.Components.ChipBase` + qualified call `ChipBase.chip_base_class()` (non `import`). Evita shadowing risk se in futuro un chip module aggiunge un local `chip_base_class/0`.

**Strategic fix (1 required):**
- Step 5 GREEN: `:if={idea.estimated_cost}` → `:if={not is_nil(idea.estimated_cost)}`. NB: `0` è truthy in Elixir, ma esplicito is_nil è più robusto + chiaro semanticamente.

**Strategic warning fix (W2):**
- Step 9 RED #12 nuovo: `function_exported?(.., :filter_active?, 3)` AND `refute /2`. Pin esplicito sull'arity change post step 9.

**Acceptance warning iter 2 closures:**
- W1 phantom S7: aggiunto `S7` come AC formale in plan + spec.
- W4 MIGRATE test vacuity: step 7 GREEN aggiunge check post-strip che ogni MIGRATE test mantenga almeno un'asserzione sostantiva. Test no-op verdi sarebbero riscritti o eliminati.
- W5 step 7 `:cost_filter` ambiguity: chiarito esplicitamente che step 7 NON tocca `@cost_filter` (assign introdotto in step 8, esteso in step 9).

### Warning iter 2 ancora aperti (tracciati per `/build`)

- **R6-1 — `Filter` module saturation post slice 7+**: 4 clausole ora, fino a 6 entro slice 8. Trigger pin: heterogeneous nature (geospatial vs scalar vs full-text) + module size > 150 LOC.
- **R6-2 — Live-region removal a11y regression**: SR users perdono announce on filter change. Mitigation: chip `aria-label` dinamico + roving tabindex per context-on-focus. Re-introduction trigger: real-user feedback negativo.
- **R6-3 — Step 7 test migration risk**: 25 test affected. Pre-step grep + categorization mandatory.
- **UX W1 — `oltre 1000€` dual semantica**: form chip stora 1000, filter chip include all priced. Documentato per maintainer in conventions.md.
- **UX W2 — Double NULL-exclude trap a 360px**: 2 helper text simultanei (durata + budget). V1 mobile screenshot validation è il safety net.
- **UX W3 — `Mostra tutte` resets all 3 groups**: invariante slice 4-6 consistent.
- **Strategic O3-O5**: Filter module growth, R lines carry-over, plan size — tutti accettati con escalation trigger documentato.

### Net assessment

Plan è **implementation-ready** per `/build`. 2 blocker design + 1 required strategic fix chiusi a iter 2; 6 warning sistemati o documentati come trade-off accettato. Le decisioni più strutturanti (BB2 dual-path error, BB9 live-region cascade, BB10 step 7 ordering) sono pinned con codice/inventory esplicito.

**Convergenza**: iter 1 → iter 2 single fix round, no iter 3 needed.
