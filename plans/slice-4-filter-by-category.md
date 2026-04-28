# Plan: Slice 4 — Filter ideas list by category (tri-state chips)

**Created**: 2026-04-28
**Branch**: main (trunk-based)
**Status**: approved
**Spec**: `docs/specs/filter-by-category.md`

## Build conventions (carried from slice 1 + 2 + 3)

- **Strict TDD** — RED → GREEN → REFACTOR per step.
- **Ogni commit** attraverso la skill `commit-message`.
- Pre-step gate locale: `mix compile --warnings-as-errors`, `mix format --check-formatted` (controllare l'exit code, non solo `tail -3`), `mix credo`, `mix deps.audit`, `mix test --include migration`. Stessi gate in CI su ogni push.
- Domain in `Ideajar.*`, delivery in `IdeajarWeb.*`.
- UI copy in italiano canonica appesa a `docs/conventions.md` nel commit che la introduce.

## Goal

Estendere la home LiveView con un filtro tri-state (off/opzionale/obbligatoria) per categoria sopra la lista, riusando il vocabolario delle 8 categorie seedate. Filtro applica `(ogni obbligatoria presente) AND (nessuna opzionale OR ≥1 opzionale presente)`. Live-region annuncia il count + l'ultima azione (per supporto SR sul cambio stato chip). Empty state dedicato + bottone `Mostra tutte` quando il filtro non matcha. Stato in LV session, no URL params, no DB schema change. Form-add e filter sono due UI distinte (form-chip binario, filter-chip tri-state) implementate come due componenti separati per non accumulare contratti ARIA in una sola function component.

Fuori scope: durata/budget/distanza (slice 5-7), text search (slice 8), URL params, operatori NOT, filtri persistenti.

## Decisioni architetturali pre-build (chiuse iter 2)

- **A1 — `list_ideas(opts \\ [])` con guard rigoroso**: signature unica con default arg. `Keyword.keyword?(opts) || raise ArgumentError, "list_ideas/1 expects a keyword list"`. `is_list/1` da solo accetta `[1, 2, 3]` e silently estrae `[]` da `Keyword.get` — il guard arrotola un wrong-result silente in un crash visibile a build/test. Pinned by Step 1 RED.
- **A2 — Ecto subquery con HAVING COUNT** per la clausola required; subquery `IN ^optional_ids` per l'optional. SQL emission verificato con `Ecto.Adapters.SQL.to_sql/2` per garantire che ecto_sqlite3 emetta il `HAVING COUNT(DISTINCT …)` atteso.
- **A3 *(rivista iter 2)* — SPLIT in due componenti**: `IdeajarWeb.Components.CategoryChip.category_chip/1` resta invariato dalla slice 3 (binario, `aria-pressed`, `data-selected`, attr `selected?`). Nuovo `IdeajarWeb.Components.CategoryChip.filter_chip/1` nello stesso modulo file con attr `state :: :off | :optional | :required` (default `:off`), `aria-label` dinamico, `data-filter-state`, niente `aria-pressed`, `phx-click="cycle_filter"`. I due componenti **condividono helper privati** (`hit_area_class/0`, ecc.) ma sono pubblici distinti — niente flag-argument anti-pattern, niente runtime mode-switching. Mutua esclusione **al type level**: il caller form non può passare `state` perché `category_chip/1` non ha quell'attr.
- **A4 — Due ARIA contracts in due componenti distinti**: `category_chip` (slice 3, form) → `aria-pressed="true|false"` + `data-selected`. `filter_chip` (slice 4, filter) → `aria-label` dinamico + `data-filter-state`. La mutua esclusione è strutturale, non documentata.
- **A5 — `@filter_state :: %{integer => :optional | :required}`**: id assenti = off. Reset = `%{}`. Cycle helper privato `cycle_state/2`: `Map.get` → `:optional` se nil, `:required` se `:optional`, `Map.delete` se `:required`.
- **A6 *(rivista iter 2)* — Cycle direction off → optional → required → off**: forward-only. Per arrivare da `required` a `optional` servono 2 click (passa per `off` con un re-flow della lista). UX critic ha flaggato come tradeoff; decisione per slice 4: forward-only è più semplice da capire ("più click = più filtro"). Long-press per reverse-cycle è R3, deferito a slice future se utenti reali si lamentano.
- **A7 — Pluralization helper in delivery layer**: `IdeajarWeb.Pluralization.idee_count/1` (NON `Ideajar.Italian` — un helper di output formatting è una concern di delivery, non di domain; inoltre `Italian` è locale-named e invecchierà se mai introdurremo gettext). Test esauriente sulle boundary 0, 1, 2, 100; `assert_raise FunctionClauseError` su input negativo.
- **A8 *(rivista iter 2)* — DOM id namespacing strutturale**: `filter_chip/1` hard-coda `id={"filter-chip-#{id}"}` nel proprio template; `category_chip/1` (slice 3) hard-coda `id={"category-chip-#{id}"}`. Niente attr `dom_id_prefix` esposto al caller — i prefissi vivono nei due componenti. Pin esplicito: A8.1 dice **literalmente** `filter-chip-{category_id}` per i filter chip.
- **A9 — Empty state distinto** con icona-prefisso visiva: workspace-empty (no idee in DB) mostra `Nessuna idea ancora. Aggiungine una qui sopra.` come slice 2. Filter-empty (≥1 idea, 0 match) mostra `<.icon name="hero-funnel" />` + `Nessuna idea per i filtri attivi.` + bottone `Mostra tutte` inline. Distinzione fatta da `filter_active?(@filter_state)` helper.
- **A10 *(rivista iter 2)* — `Mostra tutte` single-instance**: bottone reso in **al massimo un punto del DOM**. Se filter è attivo e lista ha risultati → bottone sotto la filter chip row. Se filter è attivo e lista è vuota → bottone solo dentro il messaggio empty-filter (sopprimi quello sotto la filter row). Se filter è vuoto → niente bottone. Mutua esclusione binaria per costruzione, pinata da Step 7 RED. Risolve R10/F8/F10 che era ambiguo in iter 1.
- **A11 — Hostile inputs via membership gate**: il `cycle_filter` handler accetta solo id presenti in `@categories` (snapshot caricato al mount). Defense-in-depth contro DevTools tampering. id non-integer/non-castable/non-membership → no-op silenzioso. Documentato: "Categorie eliminate post-mount sono no-op fino al refresh; categorie aggiunte richiedono un refresh per essere visibili nei chip" (caso impossibile in slice 4 dato che le categorie sono read-only seed).
- **A12 — XSS regression**: nomi categoria sono seedati e trusted, ma test esplicito che inserisce categoria sintetica con `<script>` nel name e verifica HEEx auto-escape (positive + negative assertion).
- **A13 — Out-of-scope guard**: nessun render di stringhe come `Durata`, `Budget`, `Distanza`, `Cerca` — pinato in Step 9.
- **A14 *(nuova iter 2)* — Icon shape non count per required**: `:off` no icon, `:optional` `<.icon name="hero-check" />`, `:required` `<.icon name="hero-lock-closed" />`. Shape diverso (check vs lock) è più robusto del count (1× vs 2×) per utenti low-vision (WCAG 1.4.11 più sicuro). Documentato in `@doc` del componente.
- **A15 *(nuova iter 2)* — Discoverability helper text**: subito sopra la riga filter chip, sempre visibile: `Tocca per filtrare: 1× opzionale · 2× obbligatoria · 3× rimuovi`. Risponde al UX blocker "tri-state non scoperto". Cost: una riga di testo permanente, non un popup. SR readability: la stessa stringa è il content visibile, niente sr-only special-case.
- **A16 *(nuova iter 2)* — SR cycle feedback via augmented live-region**: il live-region count include il contesto dell'ultima azione filter quando applicabile. Esempi:
  - State iniziale (no cycle): `5 idee`
  - Dopo cycle "mare" → optional: `mare opzionale, 2 idee`
  - Dopo cycle "sport" → required: `sport obbligatoria, 1 idea`
  - Dopo cycle "mare" → off: `mare rimossa, 1 idea`
  - Dopo `Mostra tutte`: `Filtri rimossi, 5 idee`
  - Refresh / mount: `5 idee` (senza prefix)
  
  Implementazione: assign `@last_filter_action :: nil | String.t()` resettato dal mount e dopo ogni cycle, riempito con la stringa contestuale. Live-region template: `{action_prefix}<.idee_count count={length(@ideas)} />`. Singolo live-region (niente race su due aria-live).
- **A17 *(nuova iter 2)* — Visual row labels per differenziare**: form chip row mantiene legend `Categorie *` (slice 3); filter chip row ha label visibile `Filtra per:` sopra. Differenziazione persistente non-state-dependent: colore di sfondo o sottile separazione visiva via `border-t` + padding. Pinato in Step 7 GREEN.
- **A18 *(nuova iter 2)* — Roving tabindex DEFERRED**: per slice 4 i 8 filter chip restano tutti nel tab order (8 tab consecutivi). Decisione consapevole tracciata come **R5**: se slice 5 (durata) aggiunge altri 5 chip → 13 sequential, allora introduciamo roving tabindex come prima slice 5 task. V1b verifica esplicitamente assenza di focus trap.

## Acceptance Criteria

> Mappatura uno-a-uno con `docs/specs/filter-by-category.md` + sync iter-2 (vedi Step 9).

### Functional / behavioral
- [ ] **F1** — Tutti gli scenari Gherkin automatabili passano (LV via `Phoenix.LiveViewTest`, domain via `DataCase`).
- [ ] **F2** — `Ideas.list_ideas/1` con `required: [...]` ritorna idee con TUTTE le categorie required presenti. Casi: 1, 2, 3+ ids; non-existent id → `[]`.
- [ ] **F3** — `Ideas.list_ideas/1` con `optional: [...]` ritorna idee con ALMENO UNA categoria optional. Lista vuota = no-op (tutte le idee).
- [ ] **F4** — `Ideas.list_ideas/1` con `required + optional` combina con AND (`mare obbligatoria + (sport o cultura)`).
- [ ] **F5** — `Ideas.list_ideas/0` invariato dalla slice 3: regression test `list_ideas() == list_ideas([])`.
- [ ] **F6** — Cycle: 3 click consecutivi sullo stesso chip riportano allo state iniziale. **Rapid cycle pin**: 5 click successivi → state finale `:required` (5 mod 3 = 2 transitions: off→optional→required), `cycle_state/2` deterministica. *(nuovo iter 2)*
- [ ] **F7** — `clear_filters` resetta `@filter_state` a `%{}`. Non tocca `@selected_category_ids` del form. `clear_filters` è idempotente su filter già vuoto.
- [ ] **F8** — Empty result state: filter attivo + 0 match → render `<.icon name="hero-funnel" />` + `Nessuna idea per i filtri attivi.` + bottone `Mostra tutte` inline. Filter chip restano renderizzati.
- [ ] **F9** — Refresh / re-mount → `@filter_state == %{}`. (LV socket reconnect dopo network blip è un'invariante naturale di Phoenix LiveView e non viene esplicitamente testata in slice 4 — vedi R12.)
- [ ] **F10** — Bottone `Mostra tutte` reso in **al massimo un punto del DOM** (vedi A10): sotto filter row se lista non-vuota, dentro empty-message se lista vuota, niente se filter inattivo.
- [ ] **F11** *(nuovo iter 2)* — Filter survives form submission: con filter attivo, submit del form add-idea NON resetta `@filter_state`. La lista re-renderizza applicando il filter alla nuova idea (se non matcha, non compare).
- [ ] **F12** *(nuovo iter 2)* — New idea outside filter is hidden: filter `mare` required + submit idea taggata solo `sport` → idea creata in DB ma NON visibile nella lista. Live-region count invariato.

### Accessibility
- [ ] **A1** — `aria-label` filter chip: `<nome>`, `<nome> opzionale`, `<nome> obbligatoria`.
- [ ] **A2** — `data-filter-state` filter chip: `off`, `optional`, `required`.
- [ ] **A3** *(rivista iter 2)* — Cue visivo non-color via shape (non count): off=no icon, optional=`<.icon name="hero-check" />`, required=`<.icon name="hero-lock-closed" />`.
- [ ] **A4** *(rivista iter 2)* — Live-region augmented: `<div role="status" aria-live="polite" id="filter-status">{action_prefix}{count} {idea|idee}</div>`. Aggiornato a ogni cycle/clear. Singolare/plurale italiano corretti. **Identity stability**: il DOM node è lo stesso (id stabile, nessun key change) attraverso multipli render — pinato da Step 8 RED.
- [ ] **A5** — Hit area filter chip ≥ 44×44 CSS px.
- [ ] **A6** — Tab order automatable: render contiene focusable elements in DOM source order: `+ Aggiungi idea` → form chip (se aperto) → filter chip → `Mostra tutte` (se reso) → first idea card. Test in Step 7 RED via Floki/string matching su sequenza id.
- [ ] **A7** *(nuova iter 2)* — Helper text discoverability: `Tocca per filtrare: 1× opzionale · 2× obbligatoria · 3× rimuovi` reso sopra la filter row sempre.
- [ ] **A8** *(nuova iter 2)* — DOM id distinct: form-chip `id="category-chip-{id}"`; filter-chip `id="filter-chip-{id}"`. Pinato da Step 7 RED.

### Security / robustness
- [ ] **S1** — `cycle_filter` con id non-integer/non-castable/non in `@categories` → no-op silenzioso. **Coverage enumerata**: `"abc"`, `""`, `"-1"`, `"0"`, `"1.5"`, `"99999999"` (valid int format ma non in `@categories`). Scenario Outline.
- [ ] **S2** — XSS regression: filter chip rendered con HEEx auto-escape (categoria sintetica con `<script>` nel name).
- [ ] **S3** — `clear_filters` su filter già vuoto → idempotente.
- [ ] **S4** *(rivista iter 2)* — Mutua esclusione **al type level** dei due ARIA contracts: `category_chip/1` non accetta attr `state`; `filter_chip/1` non accetta attr `selected?`. Compile-time enforcement. Pinato da Step 5 RED.

### Operational / data
- [ ] **O1** — Nessuna nuova migration; nessun cambio di schema.
- [ ] **O2** *(rivista iter 2 — split per evitare conflict spec/plan)* — **SQL emission pin**: `Ecto.Adapters.SQL.to_sql/2` su `list_ideas(required: [a, b])` ritorna SQL contenente `HAVING COUNT(DISTINCT …)` (case-insensitive match).
- [ ] **O3** *(nuovo iter 2)* — Performance sanity: filter applicato a 100 idee fixture risponde in <100ms in test (sanity, non strict CI gate).

### Validation venue
- [ ] **V1** — 4 screenshot mobile (iPhone 13 + Pixel 7 + 360px Pixel 4a): no filter, 1 chip optional, 1 required + 1 optional, empty result state.
- [ ] **V1a** — Lighthouse a11y mediana ≥95 su 3 run con filter mix.
- [ ] **V1b** — Keyboard-only walkthrough esplicito:
  1. Tab da `+ Aggiungi idea` → primo filter chip; verifica focus visibile.
  2. Space cicla; verifica annuncio SR (aria-label nuovo + live-region count).
  3. Tab al chip successivo → cicla → verifica stato.
  4. Tab attraverso tutti i chip; verifica niente focus trap.
  5. Tab arriva a `Mostra tutte` (se reso); Space cicla a tutto-off; live-region annuncia "Filtri rimossi, N idee".
  6. Verifica annuncio SR del helper text "Tocca per filtrare…" almeno una volta in lettura della pagina.

### Documentation
- [ ] **D1** — `docs/conventions.md` UI copy table aggiornata con: `Mostra tutte`, `Nessuna idea per i filtri attivi.`, helper text discoverability `Tocca per filtrare: 1× opzionale · 2× obbligatoria · 3× rimuovi`, aria-label suffix `opzionale`/`obbligatoria`, helper count `1 idea` / `N idee`, prefissi action `<nome> opzionale,`, `<nome> obbligatoria,`, `<nome> rimossa,`, `Filtri rimossi,`.
- [ ] **D2** — `docs/specs/filter-by-category.md` sync iter-2 (vedi Step 9).

### UI copy aggiunta (canonical)

| Elemento | Testo IT |
|---|---|
| Bottone reset filtro | `Mostra tutte` |
| Empty state filter-no-match | `Nessuna idea per i filtri attivi.` |
| Helper text discoverability | `Tocca per filtrare: 1× opzionale · 2× obbligatoria · 3× rimuovi` |
| Label visivo filter row | `Filtra per:` |
| Aria-label chip off | `<nome>` |
| Aria-label chip optional | `<nome> opzionale` |
| Aria-label chip obbligatoria | `<nome> obbligatoria` |
| Live-region prefix optional | `<nome> opzionale, ` |
| Live-region prefix required | `<nome> obbligatoria, ` |
| Live-region prefix off | `<nome> rimossa, ` |
| Live-region prefix clear | `Filtri rimossi, ` |
| Live-region count singolare | `1 idea` |
| Live-region count plurale | `<N> idee` (incluso `0 idee`) |

## Scenario → Step → Test traceability

> *(nuovo iter 2)* — pinato in Pre-PR gate; ogni Gherkin scenario tracciato a uno step + test name. Aggiornato post-build.

| Gherkin Scenario | Step | Test name draft |
|---|---|---|
| Visiting / with no filter shows every idea | 7 | `mount renders all ideas with no filter applied` |
| Clicking a chip cycles off → optional → required → off | 6 | `cycling a filter chip rotates state` |
| One optional chip filters … | 7 | `single optional chip OR filters list` |
| Multiple optional chips form an OR | 7 | `multiple optional chips combine OR` |
| One required chip filters … | 7 | `single required chip AND filters list` |
| Multiple required chips form an AND | 7 | `multiple required chips combine AND` |
| Required AND (≥1 optional) constrains both clauses | 7 | `mixed required+optional applies both clauses` |
| Filter changes update the live-region count | 8 | `live region announces count and last action` |
| Filter matching zero ideas shows the empty-result state | 7 | `empty filter result renders dedicated state` |
| "Mostra tutte" resets the filter state but leaves chips visible | 7 | `Mostra tutte clears filter state, keeps chips` |
| Resetting filters does not touch the add-form chip selection | 7 | `clear_filters does not affect form chips` |
| Cycling a filter chip does not touch the form chip selection | 7 | `cycle_filter does not affect form chips` |
| Refresh resets the filter state | 7 | `LV remount resets filter state` |
| cycle_filter with non-integer id is a no-op | 9 | `hostile inputs scenario outline (8 cases)` |
| cycle_filter with non-existent category id is a no-op | 9 | (idem outline) |
| Ideas.list_ideas/0 still returns every idea unfiltered | 1 | `regression list_ideas() == list_ideas([])` |
| There is no other filter UI in slice 4 | 9 | `out-of-scope guard regex` |
| **Rapid cycle deterministic state** *(new iter 2)* | 6 | `5 rapid clicks land on required` |
| **Filter survives form submit** *(new iter 2)* | 7 | `submitting form preserves filter state` |
| **New idea outside filter is hidden** *(new iter 2)* | 7 | `idea outside active filter is hidden` |
| **DOM id collision regression** *(new iter 2)* | 7 | `form-chip and filter-chip have distinct DOM ids` |
| **Live-region node identity** *(new iter 2)* | 8 | `live region DOM node is stable across cycles` |
| **Tab order DOM source order** *(new iter 2)* | 7 | `focusable elements appear in expected DOM order` |

## User-Facing Behavior

> Sync con `docs/specs/filter-by-category.md` (Step 9 fa l'update finale per iter-2 changes). Test ExUnit citano gli scenari per nome con commento `# Scenario: …`.

(Vedi spec — qui in plan riportiamo i nomi-chiave per traceability.)

## Steps

### Step 1: `Ideas.list_ideas(opts \\ [])` signature + Keyword guard + regression

**Complexity**: standard
**RED** (`test/ideajar/ideas_test.exs` extension):
1. Regression: `Ideas.list_ideas() == Ideas.list_ideas([])` con DB seedato.
2. `list_ideas([])` su DB con N idee → tutte, ordinate `inserted_at DESC, id DESC`, `:categories` preloaded.
3. Function clauses: `Ideas.__info__(:functions)` contiene sia `{:list_ideas, 0}` sia `{:list_ideas, 1}`.
4. **Guard pin**: `assert_raise ArgumentError, ~r/keyword list/, fn -> Ideas.list_ideas([1, 2, 3]) end` (lista non-keyword).
5. `assert_raise ArgumentError, fn -> Ideas.list_ideas("not a list") end` (non-lista).

**GREEN**:
- `def list_ideas(opts \\ [])` con `Keyword.keyword?(opts) || raise ArgumentError, "list_ideas/1 expects a keyword list, got: #{inspect(opts)}"` come prima istruzione.
- Body invariato dalla slice 3 (Step 2-4 layereranno il filter).

**Files**: `lib/ideajar/ideas.ex`, `test/ideajar/ideas_test.exs`.
**Spec mapping**: F5, foundational per F2-F4.

### Step 2: `list_ideas(required: [...])` — AND clause via subquery + HAVING COUNT

**Complexity**: complex
**RED**:
1. Setup fixture spec Background (5 idee con tag specifici).
2. `list_ideas(required: [mare.id])` → `[Sirolo, Bagno]`.
3. `list_ideas(required: [mare.id, sport.id])` → `[Bagno]`.
4. `list_ideas(required: [mare.id, museo.id])` → `[]`.
5. `list_ideas(required: [])` → tutte (no-op).
6. `list_ideas(required: [999_999])` → `[]` (id non esistente, no crash).
7. Duplicati nei required: `list_ideas(required: [mare.id, mare.id])` → stesso di `required: [mare.id]` (Enum.uniq).
8. **SQL emission O2 pin**: `{sql, _params} = Repo.to_sql(:all, query)`; `assert sql =~ ~r/HAVING\s+COUNT\(DISTINCT/i`.

**GREEN**:
```elixir
defp apply_required(query, []), do: query
defp apply_required(query, ids) do
  unique = Enum.uniq(ids)
  count = length(unique)
  subq = from ic in "idea_categories",
    where: ic.category_id in ^unique,
    group_by: ic.idea_id,
    having: count(fragment("DISTINCT ?", ic.category_id)) == ^count,
    select: ic.idea_id
  from i in query, where: i.id in subquery(subq)
end
```

**Files**: `lib/ideajar/ideas.ex`, `test/ideajar/ideas_test.exs`.
**Spec mapping**: F2, O2.

### Step 3: `list_ideas(optional: [...])` — OR clause

**Complexity**: standard
**RED**:
1. `list_ideas(optional: [sport.id])` → `[Stadio, Bagno]`.
2. `list_ideas(optional: [sport.id, cultura.id])` → 4 idee.
3. `list_ideas(optional: [])` → tutte (no-op).
4. `list_ideas(optional: [999_999])` → `[]`.
5. Duplicati: `list_ideas(optional: [sport.id, sport.id])` → uguale a `[sport.id]`.

**GREEN**:
```elixir
defp apply_optional(query, []), do: query
defp apply_optional(query, ids) do
  subq = from ic in "idea_categories",
    where: ic.category_id in ^Enum.uniq(ids),
    select: ic.idea_id
  from i in query, where: i.id in subquery(subq)
end
```

**Files**: `lib/ideajar/ideas.ex`, `test/ideajar/ideas_test.exs`.
**Spec mapping**: F3.

### Step 4: `list_ideas(required: ..., optional: ...)` — clausole combinate

**Complexity**: standard
**RED**:
1. `list_ideas(required: [mare.id], optional: [sport.id, cultura.id])` → `[Bagno]`.
2. `required: [mare.id], optional: []` → identico a solo `required`.
3. `required: [], optional: [sport.id]` → identico a solo `optional`.
4. `required: [mare.id], optional: [museo.id]` → `[]`.

**GREEN**: composizione in `list_ideas/1` body via pipeline `base |> apply_required(req) |> apply_optional(opt)`. Niente nuovo helper.

**Files**: `lib/ideajar/ideas.ex`, `test/ideajar/ideas_test.exs`.
**Spec mapping**: F4.

### Step 5: `IdeajarWeb.Components.CategoryChip.filter_chip/1` (nuovo componente, slice-3 invariato)

**Complexity**: complex (cross-cutting: tocca module file slice-3 ma senza modificare l'API esistente)
**RED** (`test/ideajar_web/components/category_chip_test.exs` nuovo, **solo per `filter_chip/1`** — slice-3 `category_chip/1` resta coperto dai test LV esistenti per evitare duplicate test seam):
1. **Tri-state — `state: :off`** → render contiene `data-filter-state="off"`, `aria-label="<nome>"`, no icona, **niente `aria-pressed`**, `phx-click="cycle_filter"`, `phx-value-id="<id>"`, `id="filter-chip-<id>"`.
2. **`state: :optional`** → `data-filter-state="optional"`, `aria-label="<nome> opzionale"`, `<.icon name="hero-check" />` presente, `<.icon name="hero-lock-closed" />` assente.
3. **`state: :required`** → `data-filter-state="required"`, `aria-label="<nome> obbligatoria"`, `<.icon name="hero-lock-closed" />` presente, `<.icon name="hero-check" />` assente.
4. **Hit area** — class string contiene `min-h-11 min-w-11`.
5. **Type-level mutua esclusione (S4)**: `filter_chip/1` non accetta attr `selected?`. Verificato compile-time: chiamare `<.filter_chip selected?={true} ... />` produce `Phoenix.Component.attr_undefined` warning/error.
6. **Slice-3 backward compat (regression)**: i test LV esistenti per il form chip (slice 3) continuano a passare senza modifica. Pinato da `mix test test/ideajar_web/live/idea_live/index_test.exs` post-merge — non un test nuovo, ma un check fixed.

**GREEN**:
- Estendere `lib/ideajar_web/components/category_chip.ex` con un secondo public function `filter_chip/1`. Helper privati condivisi (`hit_area_class/0`, `chip_button_classes/2` se utile) eliminano duplicazione visiva tra i due componenti.
- `category_chip/1` slice-3 invariato.
- Aggiungere `aria_describedby` attr opzionale anche a `filter_chip/1`.

**REFACTOR**: documentare nel `@moduledoc` la decisione "due componenti, due ARIA contracts" + il rationale (evitare flag-argument). Estrarre `defp shared_button_attrs/1` per condividere classi visive.
**Files**: `lib/ideajar_web/components/category_chip.ex` (extend; slice-3 NON tocco), `test/ideajar_web/components/category_chip_test.exs` (new).
**Spec mapping**: A1, A2, A3, A4, A8, S4.

### Step 6: `cycle_filter` + `clear_filters` handlers + `@filter_state` + cycle_state helper

**Complexity**: complex
**RED** (`test/ideajar_web/live/idea_live/index_test.exs` extension):
1. Mount: `view.assigns.filter_state == %{}`.
2. **Single click cycle** — `render_click(view, "cycle_filter", %{"id" => "#{mare.id}"})` → `filter_state == %{mare.id => :optional}`.
3. **Two clicks** → `filter_state[mare.id] == :required`.
4. **Three clicks** → `mare.id` non in `filter_state` (Map.delete).
5. **Rapid cycle pin (F6)** — 5 click consecutivi → `filter_state[mare.id] == :required` (5 mod 3 = 2 transitions).
6. **`clear_filters` reset** — con stato non vuoto → `filter_state == %{}`.
7. **Idempotency** — `clear_filters` su `%{}` → ancora `%{}`.
8. **Hostile id catchall** — `cycle_filter` con `%{}` (no `id` key), `%{"id" => 123}` (integer non string), id non in `@categories` → no-op.

**GREEN**:
- Mount: `assign(socket, :filter_state, %{}) |> assign(:last_filter_action, nil)`.
- `cycle_state/2` private helper: pattern-match-based.
- `handle_event("cycle_filter", %{"id" => raw}, socket) when is_binary(raw)` con `Integer.parse` + membership check su `@categories`.
- Catchall: `def handle_event("cycle_filter", _params, socket), do: {:noreply, socket}`.
- `handle_event("clear_filters", _, socket)` → reset.

**Files**: `lib/ideajar_web/live/idea_live/index.ex`, `test/ideajar_web/live/idea_live/index_test.exs`.
**Spec mapping**: F6, F7, S1, A11.

### Step 7: List filtered + empty result + Mostra tutte + form/filter isolation + Tab order + chip wiring + helper/label visibility

**Complexity**: complex (multi-state empty, form/filter isolation invariant, DOM id pin, Tab order automation, A7/A17 visible affordances)

> **Step size note**: 16 RED assertions, segmented in two natural commit seams (a) filter wiring + list re-render + chip ids + Tab order + helper/label affordances; (b) form/filter isolation + form draft preservation + new-idea-hidden + workspace-empty distinction. Build può committare al seam interno se utile, ma il plan riconosce Step 7 come unico per cohesion.
**RED**:
1. **Filter applicato** — fixture 5 idee. Cycle `mare` optional → render contiene Sirolo, Bagno. Mixed required+optional come spec scenario.
2. **Filter chip wiring** — render contiene 8 `<button id="filter-chip-N" phx-click="cycle_filter" phx-value-id="N" ... />`.
3. **DOM id collision (A8)** — apri form; assert `Regex.scan(~r/id="(category-chip-\d+|filter-chip-\d+)"/)` produce 16 matches (8 unique `category-chip-X` + 8 unique `filter-chip-X`); nessun id duplicato.
4. **Empty result state (F8)** — workspace 5 idee, filter `passeggiata` required → 0 match. Render contiene icona hero-funnel + `Nessuna idea per i filtri attivi.` + bottone `Mostra tutte` inline. Filter chip restano renderizzati con stato corretto.
5. **`Mostra tutte` single-instance (F10)** — quando filter è attivo + lista non-vuota: bottone presente sotto filter row, NIENTE bottone dentro empty-message. Quando filter attivo + lista vuota: bottone DENTRO empty-message, NIENTE bottone sotto filter row. Quando filter inattivo: ZERO bottoni Mostra tutte. Verificato con `Regex.scan(~r/Mostra tutte/, html) |> length()`.
6. **`Mostra tutte` reset** — click → `filter_state == %{}` + lista mostra tutte.
7. **Form chip non toccato da cycle_filter (F11 partial)** — apri form; toggle form-chip mare; cycle filter-chip mare a optional. Form chip ancora `aria-pressed="true"`/`data-selected="true"`. Filter chip `data-filter-state="optional"`.
8. **Form chip non toccato da clear_filters** — analogamente.
9. **Filter survives form submission (F11)** — apri form, toggle form-chip sport, cycle filter-chip mare optional, submit form con title "Test". Idea creata. Filter `mare optional` ancora attivo. Lista re-renderizzata con filtro applicato.
10. **New idea outside filter is hidden (F12)** — filter `mare` required, submit idea taggata solo `sport`. Idea creata in DB ma NON in lista. Live-region count invariato dal pre-submit.
11. **Form draft preservato durante cycle_filter** — apri form, type title "Sirolo" (via change event), cycle filter-chip → render contiene ancora `value="Sirolo"`.
12. **Tab order automated (A6)** — apri form + filter attivo. Estrai sequenza id dei `<button>`/input focusabili dal HTML rendered (regex). Asserta ordine: `add-idea-button` → `idea-title` → `idea-description` → `idea-url` → 8× `category-chip-N` → 8× `filter-chip-N` → `Mostra tutte` (se reso) → first idea card link.
13. **Workspace empty distinto (A9)** — DB vuoto + filter_state vuoto → empty state slice-2 (`Nessuna idea ancora.`), NON empty-filter state.
14. **A7 helper text reso (nuovo iter 3)** — `assert html =~ "Tocca per filtrare: 1× opzionale · 2× obbligatoria · 3× rimuovi"`. Il helper text appare in DOM source order **prima** del primo `filter-chip-` (regex match position).
15. **A17 filter row label `Filtra per:` reso (nuovo iter 3)** — `assert html =~ "Filtra per:"`. Position in DOM: prima del helper text e prima del primo `filter-chip-`.
16. **A17 form legend `Categorie *` regression (nuovo iter 3)** — apri form: `assert html =~ ~r/Categorie\s*\*/` (form legend conservata da slice 3 con asterisco required); position prima del primo `category-chip-`.

**GREEN**:
- LV: `derive_filter_opts/1` helper:
  ```elixir
  defp derive_filter_opts(filter_state) do
    Enum.reduce(filter_state, [required: [], optional: []], fn
      {id, :required}, acc -> Keyword.update!(acc, :required, &[id | &1])
      {id, :optional}, acc -> Keyword.update!(acc, :optional, &[id | &1])
    end)
  end
  ```
- Sostituire `Ideas.list_ideas()` con `Ideas.list_ideas(derive_filter_opts(@filter_state))` su mount + dopo cycle_filter/clear_filters/save.
- Helper `filter_active?/1`.
- Template:
  - Filter chip row con label `Filtra per:` + helper text discoverability.
  - Bottone `Mostra tutte` con conditional placement secondo A10.
  - Tre branch empty: lista non vuota → render lista; lista vuota AND filter_active? → empty-filter state con bottone inline; lista vuota AND NOT filter_active? → empty-workspace state slice-2.

**Files**: `lib/ideajar_web/live/idea_live/index.ex`, `lib/ideajar_web/live/idea_live/index.html.heex`, `test/ideajar_web/live/idea_live/index_test.exs`.
**Spec mapping**: F2-F4 (LV), F7-F12, A6-A9.

### Step 8: Live-region augmented (count + last action) + `IdeajarWeb.Pluralization`

**Complexity**: standard
**RED**:
1. **Helper unitari** (`test/ideajar_web/pluralization_test.exs` new):
   - `IdeajarWeb.Pluralization.idee_count(0) == "0 idee"`
   - `idee_count(1) == "1 idea"`, `idee_count(2) == "2 idee"`, `idee_count(100) == "100 idee"`
   - `assert_raise FunctionClauseError, fn -> idee_count(-1) end` (pin negative contract).
2. **LV live-region** — render contiene `<div role="status" aria-live="polite" id="filter-status">` con id stabile.
3. **Initial render** — testo `5 idee`.
4. **Cycle adds prefix** — cycle `mare` optional → testo `mare opzionale, 2 idee`.
5. **Cycle to required** — secondo click → `mare obbligatoria, 2 idee`.
6. **Cycle to off** — terzo click → `mare rimossa, 5 idee`.
7. **`Mostra tutte`** — testo `Filtri rimossi, 5 idee`.
8. **Re-mount cancella prefix** — refresh → testo `5 idee` (no prefix).
9. **Transition n=2→1 (singular boundary)** — start con 2 ideas in lista; cycle filter che lascia 1 → testo include `1 idea` (singolare). Pin il boundary.
10. **DOM node identity** — sequenza di 3 cycle, in ogni render html contiene `id="filter-status"` esattamente uno; il position nel DOM è stable (es. matchato dallo stesso outer container).
11. **`@last_filter_action` lifecycle on save (nuovo iter 3)** — cycle `mare` optional → assign `last_filter_action == "mare opzionale, "` + live-region testo `mare opzionale, 2 idee`. **Submit form add-idea** valido → save success → `last_filter_action` viene resettato a `nil`. Live-region testo torna a `N idee` (no prefix). Pin: `@last_filter_action` è una concern del cycle/clear handlers, non un sticky state cross-event.

**GREEN**:
- Nuovo `lib/ideajar_web/pluralization.ex` con `idee_count/1`.
- LV: assign `@last_filter_action :: nil | String.t()`. Mount → `nil`. `cycle_filter` → set al prefix corretto (`"<nome> opzionale, "`, `"<nome> obbligatoria, "`, `"<nome> rimossa, "`). `clear_filters` → set a `"Filtri rimossi, "`. **`save` (success) → reset a `nil`** (RED #11 pin esplicito). Altri handler non-cycle non sono coperti da test in slice 4 (gli unici altri handler oggi sono `toggle_form`/`close_form`/`toggle_category`/`save` di slice 2-3; il loro impatto su `last_filter_action` non è specificato — in pratica oggi non lo toccano perché non lo conoscono). Slice future che aggiungano handler dovranno decidere esplicitamente la lifecycle del prefix.
- Template: `<div role="status" aria-live="polite" id="filter-status">{@last_filter_action}{Pluralization.idee_count(length(@ideas))}</div>` sopra la lista (sotto la filter row). Sempre presente nel DOM.

**Files**: `lib/ideajar_web/pluralization.ex` (new), `test/ideajar_web/pluralization_test.exs` (new), `lib/ideajar_web/live/idea_live/index.ex` (extend), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: A4, A7 (helper text via static template).

### Step 9: Hostile inputs scenario outline + XSS regression + out-of-scope guard + docs sync + spec sync

**Complexity**: standard
**RED**:
1. **S1 hostile inputs scenario outline**:
   ```elixir
   for value <- ["abc", "", "-1", "0", "1.5", "99999999"] do
     test "cycle_filter with #{inspect(value)} is a no-op" do
       # ...
     end
   end
   ```
   Tutti casi → `filter_state` invariato + LV process alive.
2. **S2 XSS regression** — insert categoria sintetica con `name: "<script>alert(1)</script>"` via Repo, mount LV, render contiene `&lt;script&gt;...` E NOT `<script>...`.
3. **A13 out-of-scope guard** — render LV non matcha `~r/Durata|Budget|Distanza|Cerca/i`.
4. **D1 UI copy** — `docs/conventions.md` contiene tutte le 13 nuove stringhe canoniche. Test usa solo literal strings (no placeholder rows con `<nome>`).
5. **D2 spec sync (rivisto iter 3 con inverse-markers + scenario-scoped pins)** — `docs/specs/filter-by-category.md` aggiornato:
   - **Positive markers** (presenza globale): `Filtri rimossi`, `mare opzionale,` (live-region prefix), `Filtra per:` label, `hero-lock-closed` (icon required), `Tocca per filtrare:` discoverability, `submit del form add-idea NON resetta` (F11), `idea creata in DB ma NON in lista` (F12).
   - **Inverse markers globali** (assenza di stringhe stale): `refute spec =~ "double check icon"` (slice 4 usa lock); `refute spec =~ ~r/<\s*50\s*ms/` (perf è O3 <100ms sanity).
   - **Scenario-scoped pins** (per evitare regex over-broad che false-positive su scenari legittimi che usano la stessa string in altro contesto):
     - Estrarre il blocco Gherkin del scenario `Mostra tutte` con `Regex.run(~r/Scenario: "Mostra tutte".*?(?=\nScenario:|\z)/s, spec)` e asserire `assert mostra_block =~ "Filtri rimossi, 5 idee"`. **NB**: l'assertion positiva sul nuovo testo evita di proibire `5 idee` ovunque (legittimo nello scenario initial-render).
     - Analogamente per il scenario `Clicking a chip cycles`: estrarre il blocco e asserire presenza di `lock icon` + `refute cycle_block =~ "double check"` (refute scoped al solo blocco scenario, non globale).
   - **Scenari Gherkin esistenti rewrite obbligatorio**: (a) "Clicking a chip cycles" — Then clauses cambia da "the chip shows a double check icon" a "the chip shows a lock icon". (b) "Filter changes update the live-region count" — Then clauses cambiano per includere i prefix (es. `the live-region announces "Filtri rimossi, 5 idee"`).

**GREEN**:
- Estendere `docs/conventions.md` con tabella slice 4.
- Aggiornare `docs/specs/filter-by-category.md`:
  - **Sostituire** Then clauses dello scenario "Clicking a chip cycles": "double check icon" → "lock icon".
  - **Sostituire** Then clauses dello scenario "Filter changes update the live-region count" per includere i prefix `<nome> opzionale, ` / `<nome> obbligatoria, ` / `Filtri rimossi, `.
  - **Aggiungere** scenari nuovi: rapid cycle deterministic (5 click → required), filter persists across save (F11), new idea outside filter is hidden (F12), DOM id collision (F11/A8), live-region identity stable, hostile input scenario outline esteso a 6 esempi.
  - **Aggiornare** O2 nel block Acceptance Criteria: `<50ms` rimosso, sostituito da O2 (SQL emission pin) + O3 (`<100ms` sanity). Marker `<50ms` deve essere assente.
- Estendere `test/ideajar/docs_test.exs` con assertions positive E negative (refute) come definito in RED #5.

**Files**: `docs/conventions.md`, `docs/specs/filter-by-category.md`, `test/ideajar/docs_test.exs`, `test/ideajar_web/live/idea_live/index_test.exs`.
**Spec mapping**: S1-S3, A13, D1, D2.

## Complexity Classification

| Step | Complessità | Motivazione |
|------|-------------|-------------|
| 1 | standard | Signature change + Keyword guard + regression |
| 2 | **complex** | Subquery HAVING COUNT, SQL emission pin, edge cases |
| 3 | standard | OR clause con subquery semplice |
| 4 | standard | Composizione triviale |
| 5 | **complex** | Nuovo componente filter_chip (slice-3 invariato), helper condivisi |
| 6 | **complex** | cycle_state, hostile guards, rapid-cycle determinism |
| 7 | **complex** | List filter + 3-way empty + Mostra tutte placement + form/filter isolation + Tab order + DOM id collision |
| 8 | standard | Helper module + augmented live-region + boundary tests |
| 9 | standard | Hostile outline + docs/spec sync |

## Pre-PR Quality Gate

- [ ] `mix test --include migration` passa.
- [ ] `mix format --check-formatted` passa **con verifica esplicita dell'exit code** (non solo `tail -3`).
- [ ] `mix credo` passa.
- [ ] `mix deps.audit` passa.
- [ ] `mix compile --warnings-as-errors` passa.
- [ ] `/code-review` su file toccati passa.
- [ ] **F1 traceability**: ogni `Scenario:` Gherkin ha almeno un test (vedi tabella sopra).
- [ ] **V1**: 4 screenshot in `docs/screenshots/slice-4/`.
- [ ] **V1a**: Lighthouse a11y mediana ≥95 — JSON allegati.
- [ ] **V1b**: walkthrough keyboard-only (6 step espliciti).
- [ ] CI verde sul push.

## Risks & Open Questions

- **R1 — Subquery HAVING COUNT su SQLite**: chiuso da O2 SQL emission pin (Step 2 RED #8).
- **R2 — Component split backward compat**: `filter_chip/1` è nuovo, slice-3 `category_chip/1` non viene toccato. Regression del form chip è verificata da test LV esistenti che restano green.
- **R3 *(rivista iter 2)* — Cycle direction forward-only**: 2-click downgrade richiesto da `required` a `optional`. Decisione consapevole. Trigger per riapertura: V1b o utente reale che lamenta.
- **R4 — Rapid cycle live-region spam**: 5 click in 500ms → 5 announce. Decisione consapevole, accept per slice 4. Trigger per debounce: utenti SR reali si lamentano.
- **R5 *(rivista iter 2)* — Roving tabindex deferito**: 8 chip filter sequential nel tab order è acceptable per slice 4. Trigger: slice 5 (durata, +5 chip → 13 sequential) introduce roving tabindex come prima task.
- **R6 *(rivisto iter 3)* — Pluralization gettext deferral**: `IdeajarWeb.Pluralization` è hard-coded IT. **String count trigger raised**: docs/conventions.md aveva 40 stringhe canoniche post-slice-3; slice 4 ne aggiunge ~13 → ~53. Il threshold originale di iter 2 (>30) era già superato a slice 3 e mai applicato. Decisione iter 3: rimuovere il count-based trigger (per una 2-user IT-only app, una tabella di copy in conventions.md è acceptable senza i18n machinery). **Trigger residuo per migrate a gettext**: aggiunta utente non-IT — singolo trigger. Se mai dovesse fare il caso, gettext è una slice dedicata (non un blocker per slice 5+).
- **R7 — `@categories` snapshot vs DB drift**: cycle_filter accetta solo id in `@categories` (snapshot mount). Categorie aggiunte/rimosse mid-session richiedono refresh. Acceptable in slice 4 (categories sono read-only seed).
- **R8 — Test isolation vs migration test**: se Step 7 RED scopre "Database busy" race come slice 3 → impostare `idea_live/index_test.exs` async: false. Stessa decisione di slice 3 ideas_test.
- **R9 — Filter logic accumulation in `Ideas.list_ideas/1`**: slice 5+ aggiungeranno duration/budget/distance filter. Trigger per estrazione `Ideajar.Ideas.Filter` module: 3+ filter clauses (rule of 3). Slice 4 NON estrae preventivamente. Documentato qui per slice 5.
- **R10 *(chiuso iter 2)* — Mostra tutte placement**: chiuso da A10 single-instance rule.
- **R11 *(chiuso iter 2)* — `selected?` legacy attr scar**: chiuso da A3 split (no attr legacy, due componenti puliti).
- **R12 *(nuovo iter 3)* — LV socket reconnect preserva @filter_state**: pattern nativo di Phoenix LiveView (assigns sopravvivono al reconnect transient). NON viene esplicitamente testato in slice 4 — il framework lo garantisce by default. Se future slice introducono volatile state che richiede esplicita opt-out di rehydration, riapriremo il check.
- **R13 *(nuovo iter 3)* — Sunset trigger per A15 helper text**: il helper text persistente "Tocca per filtrare: …" è la remediation per il blocker UX iter 1 (tri-state non discoverabile). Trigger per rimozione: (a) user research conferma che il pattern è imparato dalla coppia, OPPURE (b) slice 5+ aggiunge altre filter rows (durata/budget) e la helper text si moltiplica creando clutter — in quel caso si valuta un singolo banner di onboarding o un tooltip a richiesta.
- **R14 *(nuovo iter 3)* — gettext trigger possibly hot**: slice 4 aggiunge ~13 nuove stringhe canoniche a `docs/conventions.md`. Combined con slice 1-3, il count totale potrebbe superare il threshold R6 (>30 stringhe). Verifica raccomandata pre-build: `grep -c "^|" docs/conventions.md` post-slice-3 → se ≥ 17, slice 4 trigga R6 e gettext diventa pre-requisito di slice 5. Decisione esplicita richiesta in quel caso.

## Plan Review Summary (iter 1)

> Verdetti iter 1: acceptance/design/UX needs-revision (ognuno con blocker), strategic needs-revision (warnings only).
> Iter 2 incorpora tutti i blocker e i warning ad alto leverage.

### Modifiche di iter 2 rispetto a iter 1

**Acceptance fixes:**
- F8/F10 (dual `Mostra tutte`) chiuso da A10 single-instance rule.
- O2 conflict spec/plan chiuso splittando in O2 (SQL emission) + O3 (perf sanity).
- S4 chiuso da A3 component split (mutua esclusione type-level invece di runtime precedence).
- F6 esteso con rapid-cycle pin (5 click → required).
- F9 esteso per distinguere LV reconnect (preserva) vs page reload (resetta).
- F11, F12 nuovi (filter survives submit, new idea outside filter hidden).
- A6 ora ha automated test (DOM source order via regex/Floki).
- A8 nuovo (DOM id distinct pin).
- S1 esteso a 6 hostile inputs in scenario outline.
- Scenario → Step → Test traceability table.

**Design fixes:**
- A3 SPLIT in due componenti distinti (chiude warning su flag-argument anti-pattern, dual-ARIA, `selected?` legacy scar, dom_id_prefix attr leak).
- A1 guard rigoroso `Keyword.keyword?/1` invece di solo `is_list/1`.
- A7 movement: `Ideajar.Italian` → `IdeajarWeb.Pluralization` (delivery layer + function-named).
- R9 documenta intent di estrazione `Ideajar.Ideas.Filter` per slice 5+ (rule of 3).
- A8.1 pin literal `filter-chip-{id}` esplicito in plan.

**UX fixes:**
- BLOCKER discoverability chiuso da A15 (helper text permanente sopra filter row).
- BLOCKER SR cycle silent chiuso da A16 (live-region augmented con last action prefix).
- A14 nuovo: icon shape (`hero-lock-closed`) per required invece di count (1× vs 2× check) per low-vision robustness.
- A17 nuovo: visual row labels (`Filtra per:`) per differenziare form/filter chip.
- A10 single-button (chiude dual `Mostra tutte` redundancy).
- R3 esplicita decisione cycle direction.
- R5 esplicita decisione roving tabindex deferral.

**Strategic fixes:**
- 9 step accettati: l'utente ha confermato tri-state (option A) sopra split MVP. Documentato che la cadenza 9-step richiede attenzione per slice 5+.
- R6 esplicita gettext trigger.
- Strategic warning su component god-object risolto da A3 split.

### Warning iter 1 ancora aperti (tracciati per `/build`)

- **Acceptance W**: nessun warning superstite ad alto leverage.
- **Design W**: nessun warning superstite ad alto leverage.
- **UX W**: cycle direction (R3), live-region spam (R4), Tab order debt (R5) — tutti tracciati come R con trigger esplicito.
- **Strategic W**: 9-step plan size — accettato consapevolmente.

### Net assessment

Plan è **implementation-ready** per il ri-review iter 2. Tutti i blocker chiusi a livello plan. La decisione del component split (A3) è la modifica strutturale più impattante e abbatte 4 warning di design + 1 blocker acceptance senza costo aggiuntivo (un nuovo componente costa ~40 righe; un attr legacy scar costa molto di più nel medio termine).

## Iter 3 fixes — close residual acceptance blockers

Iter 2 → 3: 3 approve + 1 needs-revision (acceptance critic, 3 nuovi blocker minori + 1 ri-emerso al re-review iter 3). Tutti chiusi:

- **Step 7 RED #14-#16 nuovi**: pin esplicito di A7 (helper text rendered + DOM source position) e A17 (label `Filtra per:` + regression `Categorie *` form legend con asterisco strong-pinned).
- **Step 8 RED #11 nuovo**: pin lifecycle `@last_filter_action` su save success → reset a nil (chiude UX warning iter 2). GREEN restretto a save-only per allinearsi al RED.
- **Step 9 RED #5 esteso con scenario-scoped pins** invece di refute globali over-broad: estrarre il blocco Gherkin di ciascun scenario con regex e asserire/refute solo lì. Evita il false-positive sul scenario initial-render che usa legittimamente `5 idee` senza prefix.
- **F9 demoted**: il LV socket reconnect preserve è invariante framework-native non testato (R12 documentato).
- **R13 sunset trigger** per A15 helper text esplicito.
- **R14 gettext trigger reset**: docs/conventions.md ha già 40 stringhe canoniche post-slice-3 (R6 threshold di 30 era già sforato). Iter 3 rimuove il count-based trigger; gettext attivato solo se utente non-IT.

### Reviewer verdicts iter 3 (post-fix inline)

- Acceptance: 1 nuovo blocker su over-broad regex chiuso da scenario-scoped pin; 2 warning chiusi (asterisk pin + GREEN/RED lifecycle alignment).
- Design / UX / Strategic: già approve a iter 2; nessuna modifica iter 3 li riapre.

### Net assessment iter 3

Plan è **implementation-ready** per `/build`. Convergenza raggiunta a iter 3. Le warning superstiti tracciate (step 7 size, glyph SR verbalization, helper text density, info density 360px, store helper sunset trigger, R-line risks) sono tutte refinement implementation-time, non blocker.
