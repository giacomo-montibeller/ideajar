# Plan: Target window on ideas (Quando)

**Created**: 2026-05-06
**Branch**: main
**Status**: implemented (2026-05-06)
**Spec**: `docs/specs/target-window-on-ideas.md`

## Goal

Aggiungere a `Ideajar.Ideas.Idea` una **finestra temporale orientativa** opzionale ("Quando"). Lo schema cresce di 4 colonne (`target_start :: Date`, `target_end :: Date`, `target_granularity :: :day | :month`, `target_weekend_only :: boolean`); un nuovo modulo dominio `Ideajar.Ideas.TargetWindow` centralizza formato/validazione/derivazione; un function component `IdeajarWeb.Components.TargetWindowBadge` rende il badge sulla card; il form `IdeaLive.Index` guadagna una sezione "Quando" con datepicker dual-granularità, flag weekend, preview live, e bottone "Rimuovi quando". Filtro per finestra è esplicitamente fuori scope (next slice).

## Acceptance Criteria

- [ ] **F1** — Tutti gli scenari Gherkin automatabili passano (LiveView + DataCase)
- [ ] **F2** — Round-trip `Repo.insert + Repo.get` preserva i 4 campi (compresi `nil` su tutti e 4 + `weekend_only=false` default)
- [ ] **F3** — `Idea.changeset/2` rifiuta `target_end < target_start` con `"La data di fine deve essere uguale o successiva alla data di inizio"`
- [ ] **F4** — `Idea.changeset/2` rifiuta granularità `:month` con `start.day != 1` o `end != Date.end_of_month(end)` con `errors[:target] == "Periodo non valido"`
- [ ] **F5** — `Idea.changeset/2` coerca silenziosamente `weekend_only=true` a `false` quando `granularity == :day`
- [ ] **F6** — `Idea.changeset/2` rifiuta partial-set con `errors[:target] == "Periodo non valido"`
- [ ] **F7** — `TargetWindow.format/2` produce la stringa attesa per gli 11 casi della tabella di formato
- [ ] **F8** — La card renderizza il badge solo quando `target_start != nil`
- [ ] **F9** — Il form di edit pre-popola correttamente i controlli per ogni granularità
- [ ] **F10** — "Rimuovi quando" azzera tutti e 4 i campi atomicamente
- [ ] **F11** — Idee preesistenti senza target window continuano a renderizzare correttamente
- [ ] **F12** — Ordine badge sulla card: target-window → duration → budget → location
- [ ] **S1** — HEEx auto-escape sul label (regression structural pin)
- [ ] **O1** — Migration `add_target_window_to_ideas` up/down round-trip pulito
- [ ] **O2** — Esistenti righe in `ideas` post-migration: `target_weekend_only=false`, gli altri 3 NULL
- [ ] **D1** — `docs/conventions.md` UI copy table aggiornata (8 etichette + 12 mesi se non già presenti)
- [ ] **D3** — `CONTEXT.md` schema block aggiornato con i 4 nuovi campi

## User-Facing Behavior

> Verbatim dalla `## User-Facing Behavior` di `docs/specs/target-window-on-ideas.md`.

```gherkin
Feature: Plan when an idea will happen — target time window

  Background:
    Given my browser holds a valid signed session cookie
    And today is "2026-05-06"

  # ── Day range ────────────────────────────────────────────────
  Scenario: Single-day target — same year as today, year hidden
    When I create an idea with target window: day range, 2026-05-06 to 2026-05-06
    Then the card shows the badge "6 maggio"

  Scenario: Multi-day same-month range
    When I create an idea with target window: day range, 2026-05-05 to 2026-05-07
    Then the card shows the badge "5-7 maggio"

  Scenario: Multi-day cross-month, same year
    When I create an idea with target window: day range, 2026-05-30 to 2026-06-02
    Then the card shows the badge "30 maggio - 2 giugno"

  Scenario: Day range in a future year shows year
    When I create an idea with target window: day range, 2027-01-15 to 2027-01-15
    Then the card shows the badge "15 gennaio 2027"

  Scenario: Day range crossing the year boundary shows both years
    When I create an idea with target window: day range, 2026-12-30 to 2027-01-02
    Then the card shows the badge "30 dicembre 2026 - 2 gennaio 2027"

  # ── Month range ──────────────────────────────────────────────
  Scenario: Single month, no weekend flag
    When I create an idea with target window: month range, May 2026 to May 2026, weekend_only=false
    Then the card shows the badge "maggio"

  Scenario: Single month with weekend flag
    When I create an idea with target window: month range, May 2026 to May 2026, weekend_only=true
    Then the card shows the badge "weekend di maggio"

  Scenario: Multi-month range
    When I create an idea with target window: month range, May 2026 to June 2026, weekend_only=false
    Then the card shows the badge "maggio-giugno"

  Scenario: Multi-month range with weekend flag
    When I create an idea with target window: month range, May 2026 to June 2026, weekend_only=true
    Then the card shows the badge "weekend tra maggio e giugno"

  Scenario: Future-year single month shows year
    When I create an idea with target window: month range, January 2027 to January 2027
    Then the card shows the badge "gennaio 2027"

  Scenario: Cross-year month range shows both years
    When I create an idea with target window: month range, December 2026 to January 2027
    Then the card shows the badge "dicembre 2026 - gennaio 2027"

  # ── Optional / unset ────────────────────────────────────────
  Scenario: Idea with no target window shows no badge
    Given an idea has no target window
    When I visit "/"
    Then the rendered card has no target-window badge

  Scenario: Form opens with target window unset by default
    When I click "+ Aggiungi idea"
    Then the "Quando" control shows no selection
    And the "Solo nei weekend" checkbox is hidden

  # ── Form preview ─────────────────────────────────────────────
  Scenario: The form previews the descriptive label as the user picks
    Given the add-idea form is expanded with granularity "Mesi"
    When I select May 2026 to June 2026
    And I check "Solo nei weekend"
    Then the form shows the preview "weekend tra maggio e giugno"

  # ── Validation ───────────────────────────────────────────────
  Scenario: end before start is rejected
    When I submit an idea with target window: day range, 2026-05-10 to 2026-05-05
    Then I see "La data di fine deve essere uguale o successiva alla data di inizio"
    And no idea is created

  Scenario: month granularity with start not on day 1 is rejected
    When the changeset receives target_start=2026-05-15, target_end=2026-05-31, granularity="month"
    Then errors[:target] is "Periodo non valido"
    And no idea is created

  Scenario: month granularity with end not on last-of-month is rejected
    When the changeset receives target_start=2026-05-01, target_end=2026-05-20, granularity="month"
    Then errors[:target] is "Periodo non valido"

  Scenario: weekend_only=true on day granularity is silently coerced to false
    When the changeset receives a day range with weekend_only=true
    Then the persisted idea has weekend_only=false
    And no error is raised

  Scenario: partial set is rejected
    When the changeset receives only target_start (no target_end, no granularity)
    Then errors[:target] is "Periodo non valido"

  # ── Edit ─────────────────────────────────────────────────────
  Scenario: Edit form pre-populates the existing target window
    Given an idea has target window: month range, May 2026, weekend_only=true
    When I open the edit form for that idea
    Then the controls show: granularity "Mesi", May 2026 to May 2026, weekend_only=true

  Scenario: "Rimuovi quando" clears all four fields atomically
    Given an idea has any target window set
    When I open the edit form, click "Rimuovi quando", and save
    Then the persisted idea has target_start, target_end, target_granularity all NULL
    And target_weekend_only is false
    And the card shows no target-window badge

  # ── Past dates: no treatment ────────────────────────────────
  Scenario: An idea whose target window is in the past stays visible and unflagged
    Given today is "2026-05-06"
    And an idea has target window: day range, 2026-04-01 to 2026-04-01
    When I visit "/"
    Then the idea is listed as usual
    And its badge reads "1 aprile" (no expired marker)

  # ── Card layout ─────────────────────────────────────────────
  Scenario: Badge order on the card is when → duration → budget → location
    Given an idea has target window, duration, estimated_cost, and location_name all set
    When I visit "/"
    Then the badges appear in this order: target-window, duration, budget, location
```

## Steps

### Step 1: Schema fields + migration (foundation)

**Complexity**: standard
**Traces to**: F2, O1, O2, F11
**RED**:
1. In `test/ideajar/ideas/idea_test.exs` (o nuovo block in `Ideajar.Ideas.IdeaTest`), aggiungere test che asserisce che `Idea.__schema__(:fields)` include `target_start`, `target_end`, `target_granularity`, `target_weekend_only`.
2. In `test/ideajar/migrations_test.exs`, estendere il file-count test a 4 migrations e aggiungere un nuovo describe `"AddTargetWindowToIdeas migration round-trip"` con: down rimuove le 4 colonne, up le ricrea, righe esistenti hanno `target_weekend_only=false` + altri 3 NULL.
3. Smoke insert/select round-trip: `Repo.insert!(%Idea{title: "x", target_start: ~D[2026-05-06], target_end: ~D[2026-05-06], target_granularity: :day, target_weekend_only: false})` recupera tutti e 4 i valori.

**GREEN**:
1. Schema: aggiungere 4 `field`s in `lib/ideajar/ideas/idea.ex`. `target_granularity` come `Ecto.Enum, values: [:day, :month]`. `target_weekend_only` con default `false`.
2. Migration `priv/repo/migrations/<ts>_add_target_window_to_ideas.exs`: 4 ADD COLUMN, no backfill (default DB su `target_weekend_only`).
3. Aggiornare `migrations_test.exs`: nuova version costante, `restore_baseline` invariato (già drop+migrate), nuovo describe round-trip.

**REFACTOR**: estrarre il counts-and-versions in cima a `migrations_test.exs` per leggibilità (se il numero di migrations costanti supera 4-5).

**Files**:
- `lib/ideajar/ideas/idea.ex`
- `priv/repo/migrations/<ts>_add_target_window_to_ideas.exs` (nuovo)
- `test/ideajar/ideas/idea_test.exs`
- `test/ideajar/migrations_test.exs`

**Commit (draft)**: *"Add a structured target-window persistence layer to ideas"*

---

### Step 2: `Ideajar.Ideas.TargetWindow` — `month_label/1` + `format/2` + `from_idea/1`

**Complexity**: standard
**Traces to**: F7, F8 (parziale), F11 (`from_idea` ritorna nil)
**RED**:
1. Creare `test/ideajar/ideas/target_window_test.exs`. Test parametrici (table-driven via `for {input, expected} <- ...`) per `format/2` su tutti gli 11 casi della tabella di formato (vedi spec § Format rules):
   - day, single, same-year → `"6 maggio"`
   - day, range, same-month → `"5-7 maggio"`
   - day, range, cross-month, same-year → `"30 maggio - 2 giugno"`
   - day, single, future-year → `"15 gennaio 2027"`
   - day, range, cross-year → `"30 dicembre 2026 - 2 gennaio 2027"`
   - month, single, same-year, no-weekend → `"maggio"`
   - month, single, same-year, weekend → `"weekend di maggio"`
   - month, range, same-year, no-weekend → `"maggio-giugno"`
   - month, range, same-year, weekend → `"weekend tra maggio e giugno"`
   - month, single, future-year → `"gennaio 2027"`
   - month, range, cross-year → `"dicembre 2026 - gennaio 2027"`
2. Test `month_label/1` per tutti i 12 mesi.
3. Test `from_idea/1`: ritorna `nil` quando tutti i 4 campi sono nil/default; ritorna `%{...}` con i valori giusti quando popolati; raise (defensive) su partial state.

**GREEN**: implementare `lib/ideajar/ideas/target_window.ex` con:
- `@months ~w(gennaio febbraio marzo aprile maggio giugno luglio agosto settembre ottobre novembre dicembre)`
- `month_label(n) when n in 1..12`, lookup via `Enum.at(@months, n - 1)`
- `format(t, today)` → dispatch su `t.granularity` con sub-helper privati `format_day_range/2` e `format_month_range/2`. Year visibility helper centralizzato.
- `from_idea/1` → riconosce all-nil come `nil`; assembla il map; raise su partial.

**REFACTOR**: se `format_day_range` e `format_month_range` condividono >50% di logica sui casi cross-year/same-year, estrarre `with_year_suffix/3` privato.

**Files**:
- `lib/ideajar/ideas/target_window.ex` (nuovo)
- `test/ideajar/ideas/target_window_test.exs` (nuovo)

**Commit (draft)**: *"Render Italian time-window labels for any granularity-and-year combination"*

---

### Step 3: `TargetWindow.validate_changeset/1` + integrazione in `Idea.changeset/2`

**Complexity**: standard
**Traces to**: F3, F4, F5, F6
**RED**: in `target_window_test.exs` (validation describe) + `idea_test.exs`:
1. Test `end >= start`: cs con `target_end < target_start` → `errors[:target_end] == "La data di fine deve essere uguale o successiva alla data di inizio"`. Pin del messaggio canonico.
2. Test `:month` granularity, start non al day 1 → `errors[:target] == "Periodo non valido"`.
3. Test `:month` granularity, end non al last-of-month → `errors[:target] == "Periodo non valido"`.
4. Test `:day` granularity con `weekend_only=true` → la cs valida è applicata e `weekend_only` viene coerced a `false` (`get_field(cs, :target_weekend_only) == false`).
5. Test partial-set (uno qualsiasi di `target_start | target_end | target_granularity` da solo) → `errors[:target] == "Periodo non valido"`.
6. Test all-nil case → cs valid, no errors aggiunti.
7. Test happy path (day single, day range, month single, month range): cs valid.

**GREEN**:
1. In `lib/ideajar/ideas/target_window.ex`, aggiungere `validate_changeset/1` che applica le 4 regole + coercion.
2. In `lib/ideajar/ideas/idea.ex` `changeset/2`, dopo `cast` e prima del `validate_required` finale, invocare `TargetWindow.validate_changeset/1`. Aggiungere i 4 field a `cast` allowlist.

**REFACTOR**: nessuno necessario.

**Files**:
- `lib/ideajar/ideas/target_window.ex`
- `lib/ideajar/ideas/idea.ex`
- `test/ideajar/ideas/target_window_test.exs`
- `test/ideajar/ideas/idea_test.exs`

**Commit (draft)**: *"Reject inconsistent target windows at the changeset boundary"*

---

### Step 4: `IdeajarWeb.Components.TargetWindowBadge.target_window_badge/1`

**Complexity**: standard
**Traces to**: F8, S1
**RED**: nuovo `test/ideajar_web/components/target_window_badge_test.exs`:
1. Render con day-single → HTML contiene `"6 maggio"` (test parametrico riusa una manciata di casi rappresentativi di `format/2` ma non tutti 11 — quelli sono già coperti da `target_window_test`).
2. Render con `target_start=nil` → ritorna stringa vuota o nessun elemento (no badge).
3. `data-testid="idea-target-window-badge"` presente quando renderizzato.
4. S1 — XSS regression structural pin: il label passa attraverso HEEx auto-escape.

**GREEN**: creare `lib/ideajar_web/components/target_window_badge.ex` con:
- `attr :idea, :any, required: true`
- `attr :today, Date, required: false, default: nil` (test seam; default a `Date.utc_today/0` quando nil)
- Function component che usa `TargetWindow.from_idea/1`; se nil ritorna nothing; altrimenti renderizza `<span data-testid="idea-target-window-badge" class="...badge classes...">{label}</span>`.

**REFACTOR**: allineare le classi Tailwind a `BudgetBadge` / `LocationBadge` / `DurationChip.duration_badge` per coerenza visiva.

**Files**:
- `lib/ideajar_web/components/target_window_badge.ex` (nuovo)
- `test/ideajar_web/components/target_window_badge_test.exs` (nuovo)

**Commit (draft)**: *"Add a card badge that surfaces the planned time window"*

---

### Step 5: Card integration — wire badge + canonical badge order

**Complexity**: standard
**Traces to**: F8, F11, F12
**RED**: in `test/ideajar_web/live/idea_live/index_test.exs`:
1. Test idea con tutti e 4 i target campi set + duration + cost + location: il rendering della card ha `data-testid="idea-target-window-badge"` PRIMA di `data-testid="idea-duration-badge"` PRIMA di `data-testid="idea-budget-badge"` PRIMA del location badge testid (verificare il testid esatto in `LocationBadge`).
2. Test idea con `target_*` tutti nil ma duration set → no badge target-window, duration badge presente (no regression).
3. Test idea senza alcun campo opzionale → nessuno dei 4 badge.

**GREEN**: in `lib/ideajar_web/live/idea_live/index.html.heex`:
1. `import IdeajarWeb.Components.TargetWindowBadge` (o alias) in `index.ex`.
2. Inserire `<TargetWindowBadge.target_window_badge :if={...} idea={idea} />` PRIMA dei badge esistenti (target → duration → budget → location), rispettando l'ordine F12.

**REFACTOR**: nessuno necessario (4 badge in sequenza, niente componente wrapper).

**Files**:
- `lib/ideajar_web/live/idea_live/index.html.heex`
- `lib/ideajar_web/live/idea_live/index.ex` (alias/import)
- `test/ideajar_web/live/idea_live/index_test.exs`

**Commit (draft)**: *"Surface the planned time window first on the idea card"*

---

### Step 6: Form fieldset "Quando" + handlers + live preview

**Complexity**: complex
**Traces to**: tutti gli scenari del create-flow + form preview + remove + save
**RED**: in `index_test.exs` aggiungere un nuovo `describe "form target-window fieldset"`:
1. Form aperto: legend "Quando" presente, helper "Quando pensi di farlo?" presente, radio "Giorni"/"Mesi" presenti senza selezione, checkbox "Solo nei weekend" assente (gated su :month).
2. Pick "Giorni" + 2 date valide → preview presente nella DOM con il label esatto (`format/2`).
3. Pick "Mesi" + 2 mesi + check weekend → preview "weekend tra <m1> e <m2>".
4. Switch granularità (day → month) → state reset (date azzerate, preview vuota).
5. Click "Rimuovi quando" → state azzerato.
6. Submit con day range valido + categoria → idea creata con i 4 campi target set; card mostra il badge.
7. Submit con day range end<start → errore "La data di fine deve essere uguale o successiva alla data di inizio" mostrato sotto il fieldset; idea non creata.
8. Submit con day range valido ma weekend checkbox non visibile → idea creata con `target_weekend_only=false`.
9. F12: con tutti i campi opzionali set, ordine badge nella card corretto (duplicato di Step 5 ma a livello integrazione end-to-end).

**GREEN**:
1. **State**: in `IdeaLive.Index` aggiungere `@target_window` come map analogo allo spec (granularity, start, end, weekend_only, preview).
2. **Handlers** (parallel a quelli esistenti per duration/budget/location):
   - `"set_target_granularity"` con `%{"granularity" => "day" | "month"}` → reset start/end, set granularity, recompute preview.
   - `"update_target_window"` con form params (es. `%{"target_start" => "2026-05-06", ...}`) → parse via `Date.from_iso8601` (giorni) o via `<input type="month">` ISO ("2026-05") espanso a `Date.new!(year, month, 1)`/`Date.end_of_month/1` (mesi); aggiorna state + recompute preview via `TargetWindow.format/2`.
   - `"toggle_target_weekend_only"` → flip flag + recompute preview.
   - `"clear_target_window"` → reset assign a empty.
3. **Template** (`index.html.heex`): nuovo `<fieldset>` con:
   - `<legend>Quando</legend>` (no asterisco)
   - `<p id="idea-target-help" class="...">Quando pensi di farlo?</p>`
   - 2 radio `name="target_granularity"` con valori `"day"` / `"mese"` → attivano `set_target_granularity`
   - Conditional render dei 2 input data (granularità day) o 2 input mese (granularità month)
   - Conditional checkbox "Solo nei weekend" iff `granularity == :month`
   - `<p aria-live="polite" data-testid="target-window-preview">{@target_window.preview}</p>` — preview annunciata
   - `<button phx-click="clear_target_window">Rimuovi quando</button>` (sempre visibile; no-op se nessuna granularità selezionata, mantiene state già empty)
   - Errore mostrato sotto il fieldset (campo `:target_end` o `:target` a seconda della violazione)
4. **Save**: nel handler `save` (e `save_edit`), estrarre i 4 campi da `@target_window` e iniettarli negli attrs prima di `Ideas.create_idea` / `Ideas.update_idea`.

**REFACTOR**: estrarre helper privato `target_window_attrs/1` in `IdeaLive.Index` per la conversione `assign → attrs`. Verificare se la complessità del template richiede l'estrazione di un function component (es. `target_window_field/1`) — probabile.

**Files**:
- `lib/ideajar_web/live/idea_live/index.ex`
- `lib/ideajar_web/live/idea_live/index.html.heex`
- (eventuale) `lib/ideajar_web/components/target_window_field.ex` (nuovo, se REFACTOR lo richiede)
- `test/ideajar_web/live/idea_live/index_test.exs`

**Commit (draft)**: *"Let the user set a planned time window on a new idea"*

---

### Step 7: Edit form pre-fill + atomic remove

**Complexity**: standard
**Traces to**: F9, F10
**RED**: in `index_test.exs` (describe edit):
1. Idea con month-range + weekend_only=true → click edit → form mostra granularità "Mesi" selezionata, mese start/end pre-popolati, checkbox checked.
2. Idea con day-range single → click edit → form mostra "Giorni" + 2 date.
3. Idea con target window → click edit → click "Rimuovi quando" → save → idea aggiornata con tutti e 4 i campi `nil`/false e card non mostra più il badge.
4. Idea con target window → click edit → modifica solo title senza toccare il fieldset Quando → target window preservato (regression: la rehydration non azzera).

**GREEN**: in `IdeaLive.Index` `mount_edit_idea`/`open_edit_form` (a seconda dei nomi nello slice 14):
1. Quando si carica l'idea per edit, popolare `@target_window` da `TargetWindow.from_idea(idea)` (oppure empty se nil), incluso il preview computato.
2. Verificare che il save di edit gestisca correttamente sia il caso "user touched and cleared" sia "user didn't touch" (atom-keyed o string-keyed → `force_overwrite` controllato).

**REFACTOR**: se la rehydration riusa la stessa logica del create (`@target_window` shape è la stessa), niente da estrarre.

**Files**:
- `lib/ideajar_web/live/idea_live/index.ex`
- `test/ideajar_web/live/idea_live/index_test.exs`

**Commit (draft)**: *"Carry the planned time window through the edit-and-save round trip"*

---

### Step 8: Documentation sync

**Complexity**: trivial
**Traces to**: D1, D3
**RED**: in `test/ideajar/docs_test.exs`, nuovi describe:
1. `docs/conventions.md` deve contenere ognuna delle 8 etichette UI canoniche (legend, helper, 2 radio, checkbox, reset button, errore data, errore generica).
2. `docs/conventions.md` deve contenere ognuno dei 12 nomi mese italiani (assert verbatim).
3. `CONTEXT.md` schema block deve menzionare `target_start`, `target_end`, `target_granularity`, `target_weekend_only`.

**GREEN**:
1. `docs/conventions.md` — nuova sezione "Stringhe aggiunte in slice <N> (target window)" con la tabella UI copy + i 12 mesi.
2. `CONTEXT.md` — nel schema block di `ideas`, aggiungere le 4 righe (target_start, target_end, target_granularity, target_weekend_only) parallele a duration/estimated_cost/location_*.

**REFACTOR**: nessuno.

**Files**:
- `docs/conventions.md`
- `CONTEXT.md`
- `test/ideajar/docs_test.exs`

**Commit (draft)**: *"Document the new target-window contract in conventions and context"*

---

## Complexity Classification

| Step | Complexity | Why |
|------|-----------|-----|
| 1 | standard | Migration + schema, well-bounded pattern |
| 2 | standard | New pure-logic module, table-driven tests |
| 3 | standard | Cross-field validation in existing changeset pattern |
| 4 | standard | Function component, follows BudgetBadge/LocationBadge pattern |
| 5 | standard | Template wiring + ordering test |
| 6 | **complex** | New form-control patterns: granularity-toggle changing input shape, conditional checkbox, live preview, mese→date span coercion, save-flow integration |
| 7 | standard | Form rehydration in established edit pattern |
| 8 | trivial | Pure documentation sync with assertion test |

## Pre-PR Quality Gate

- [ ] `mix test` — full suite green (target ~1000 test post-step-7)
- [ ] `mix format --check-formatted` clean
- [ ] `mix compile --warnings-as-errors` clean
- [ ] `/code-review` passa (special focus su a11y per step 6, security per S1)
- [ ] `docs/conventions.md` + `CONTEXT.md` aggiornati
- [ ] Verifica visiva manuale: form aperto su mobile viewport, granularità Mesi+weekend, card con badge, edit pre-populato

## Risks & Open Questions

- **R1 — `<input type="month">` mobile UX**: il picker nativo mobile mostra YYYY-MM. Su iOS Safari è un dropdown. Su Android Chrome è un date picker compatto. Acceptable per la coppia (test su entrambe in V1). Mitigazione: nessuna se va bene; fallback testuale `pattern="\d{4}-(0[1-9]|1[0-2])"` se servisse compatibilità più ampia (deferred).
- **R2 — Live preview a11y**: la preview è dichiarata `aria-live="polite"`. Conferma: gli screen reader devono annunciarla quando cambia? Decisione di design: SÌ (la preview è il feedback principale per l'utente che sta scegliendo). Test V1b verifica.
- **R3 — Form complexity (step 6)**: il template del fieldset cresce significativamente. Se il template oltrepassa ~50 righe, estrarre `target_window_field/1` come function component (REFACTOR del step 6). Soglia decisionale: 50 righe.
- **R4 — Granularità switch resets state**: scelta deliberata (vedi RED step 6). Se l'utente switcha day→month dopo aver inserito date, le date vengono perse. Alternative considerate: mantenere e provare a riadattare (es. day 5 maggio → month maggio). Più magico, meno prevedibile. Choosing reset for clarity.
- **R5 — Weekend coercion silenziosa**: la spec sceglie coercion silenziosa (no error). Pro: il form passa weekend_only=true se la checkbox è in stato `:month`, switchare a `:day` non deve far esplodere il submit. Contro: una richiesta API (futura) con day+weekend_only=true non riceve segnale. Per ora intra-app, OK.
- **R6 — Slice numbering**: questa è una nuova capability di dominio (parità con duration/budget/location/edit). Probabilmente "slice 15". Conferma in `CONTEXT.md` update (step 8) con il numero giusto post-fact.
**Decisioni prese in approval (2026-05-06)**:
- ✅ **D-OQ1** — Default granularità = `null` (form aperto = nessuna granularità selezionata, coerente con scenario "form opens unset by default").
- ✅ **D-OQ2** — Bottone "Rimuovi quando" sempre visibile; no-op quando state già empty. Rimuove il branch condizionale dal template.

## Plan Review Summary

Self-review sostitutiva del dispatch formale dei 4 reviewer (acceptance / design / UX / strategic), date le dimensioni proporzionate del cambio (8 step, 1 complex).

### Acceptance Test Critic

- **F1-F12 + S1 + O1-O2 + D1/D3** sono tutti osservabili e direttamente test-abili. Mappatura step→criterio:
  - Step 1 → F2, O1, O2, F11 (foundation); Step 2 → F7; Step 3 → F3, F4, F5, F6; Step 4 → F8, S1; Step 5 → F12; Step 6 → tutti gli scenari create-flow + form preview; Step 7 → F9, F10; Step 8 → D1, D3.
- 23 scenari Gherkin tutti tracciati. Lo scenario "Past dates: no treatment" è coperto passivamente da format/2 (Step 2) — nessun branch speciale richiesto.
- TDD ordering corretto: foundation prima dell'UI, validation prima del form, badge prima della card, create prima dell'edit.
- **Gap identificato**: F7 dice "11 casi" ma la tabella di formato (spec § Format rules) ha 11 righe distinte. Step 2 le elenca tutte 11. ✓

### Design & Architecture Critic

- **Pattern coerenza**: `Ideajar.Ideas.TargetWindow` riproduce il pattern di `Ideajar.Ideas.Duration` (modulo dominio per value-object). `TargetWindowBadge` riproduce `BudgetBadge` / `LocationBadge`. Niente nuove astrazioni, niente over-engineering.
- **Cross-field validation** vive nel changeset boundary, simmetrico a slice 7a (location_name/lat/lng).
- **Domain split corretto**: `format/2` puro (no I/O), `validate_changeset/1` puro su Ecto.Changeset, `from_idea/1` accessor. Niente coupling con Repo o LiveView.
- **Form fieldset complexity (step 6)**: il rischio R3 (template oltre 50 righe) è già identificato e l'estrazione `target_window_field/1` è prevista come REFACTOR. Nessun blocker.
- **Coupling**: il LiveView tocca `TargetWindow.format/2` per la live preview; il badge component idem. Nessun import circolare.

### UX Critic

- **Card layout F12**: ordine `quando → durata → budget → posizione` rispetta il flusso narrativo cronologico.
- **Form cognitive load**: 4 controlli (radio + 2 date input + checkbox conditional + remove button + preview) — denso ma non eccessivo. Il preview live risolve l'ambiguità "cosa vedrà l'altro" prima del submit.
- **A11y (R2)**: `aria-live="polite"` sulla preview è la scelta giusta per non interrompere ma comunque annunciare.
- **Native pickers (R1)**: scelta corretta; richiede V1 mobile validation in step 6 finale.
- **Granularità switch resets state (R4)**: trade-off prevedibilità vs convenience. Spec sceglie reset (esplicito). Se l'utente si lamenta in V1, riconsiderare in slice successiva.
- **Errore validation venue**: l'errore "La data di fine deve essere uguale o successiva alla data di inizio" è specifico e visibile sotto il fieldset (non popup). "Periodo non valido" è generico ma deliberatamente catch-all per stati corrotti che non dovrebbero mai arrivare via UI corretta.

### Strategic Critic

- **Scope chiuso**: filtraggio escluso esplicitamente (next slice). Nessuna feature creep.
- **Blast radius**: 4 colonne nuove su `ideas`, 1 modulo dominio nuovo, 1 component nuovo, ~80 righe template nuove. Limitato.
- **Reversibilità**: la migration è completamente reversibile (no backfill, defaults sicuri).
- **Vincolo del filtro futuro**: la struttura dati (start/end/granularity/weekend_only) supporta direttamente i filtri della prossima slice senza re-modeling. Investimento giusto upfront.
- **Costo opportunity**: questo lavoro è prerequisito per i filtri temporali; non c'è alternativa più piccola che lasci i filtri possibili.

### Verdetto: PASS

Nessun blocker. 6 open question (R1-R6) e 2 OQ (default granularità + reset button visibility) sono cose decise nello step 6 durante il build, non blocking per l'approvazione del plan.

**Warnings**:
- R3 (template length step 6) → soglia esplicita di 50 righe per estrarre function component
- OQ1/OQ2 (default granularità + reset visibility) → conferma in approval o decidere durante step 6

**Observations**:
- Step 6 è il singolo punto di rischio significativo. Suddividerlo (6a foundation, 6b month branch, 6c preview) è un'opzione se durante il build risulta troppo grosso, ma il piano lo tratta come unità coesa per non frammentare la UX.
- Il numero della slice (R6) è un dettaglio di documentazione (CONTEXT.md), non blocca implementation.
