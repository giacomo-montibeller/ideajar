# Spec: Target window on ideas (Quando)

> Slice TBD del progetto ideajar (vedi `CONTEXT.md`). Estende lo schema `ideas` con una **finestra temporale orientativa** opzionale che dice quando la coppia pensa di svolgere l'attività. Il filtraggio per finestra è esplicitamente **fuori scope** per questa slice (sarà la successiva).

## Intent Description

A ogni idea può essere associata una **finestra temporale orientativa** che dice *quando* la coppia pensa di svolgere l'attività. Il campo è opzionale (la maggior parte delle idee può non averlo).

Due granularità mutuamente esclusive:

- **Giorni** — una data di inizio e una data di fine (anche coincidenti). Es. "mercoledì 6 maggio", "5–7 maggio", "30 maggio – 2 giugno".
- **Mesi** — un intervallo di mesi pieni (start = primo del mese, end = ultimo del mese). Una flag esplicita `solo_weekend` arricchisce la semantica per i mesi. Es. "maggio", "weekend di maggio", "maggio–giugno", "weekend tra maggio e giugno".

La card mostra un'**etichetta descrittiva** derivata dalla struttura. L'anno è mostrato solo quando differisce dall'anno corrente. Idee con finestra nel passato restano visibili e senza marker visivo (decisione esplicita: nessun trattamento dello scaduto in questa slice).

Concettualmente ortogonale a `duration` (slice 5): `duration` = *quanto* dura l'attività; `target window` = *quando* la facciamo. Possono coesistere su una stessa idea.

Fuori scope esplicito: filtraggio per finestra (next slice), ricorrenze ("ogni weekend"), notifiche/promemoria, time-of-day, finestre multiple per idea, sorting per finestra, time-zone (Europe/Rome implicito), display del giorno della settimana sulle date singole.

## User-Facing Behavior

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

## Architecture Specification

### Components

| Componente | Tipo | Responsabilità |
|---|---|---|
| `Ideajar.Ideas.Idea` (esteso) | Schema (`lib/ideajar/ideas/idea.ex`) | 4 nuovi campi: `target_start :: Date`, `target_end :: Date`, `target_granularity :: Ecto.Enum [:day, :month]`, `target_weekend_only :: boolean` (NOT NULL, default false). Gli altri 3 sono nullable in DB. |
| `Ideajar.Ideas.TargetWindow` | Domain module nuovo (`lib/ideajar/ideas/target_window.ex`) | Value-object derivata: `from_idea/1`, `format/2`, `validate_changeset/1`, `month_label/1`. Single source of truth per regole di formato, validazione, e nomi mese italiani. |
| `Ideajar.Ideas.Idea.changeset/2` (esteso) | Changeset | Invoca `TargetWindow.validate_changeset/1` come ultima validazione cross-field. |
| `IdeajarWeb.Components.TargetWindowBadge` | Function component nuovo (`lib/ideajar_web/components/target_window_badge.ex`) | `target_window_badge/1` — render condizionale del badge sulla card; sotto il cofano chiama `TargetWindow.format/2` con `Date.utc_today/0`. Pattern simmetrico a `DurationChip.duration_badge/1`, `BudgetBadge`, `LocationBadge`. |
| `IdeajarWeb.IdeaLive.Index` (esteso) | LiveView | Form section "Quando" con: radio granularità (Giorni/Mesi), 2 input data o 2 input mese, checkbox "Solo nei weekend" (visible iff Mesi), bottone "Rimuovi quando", live preview del label. Nuovo state assign `@target_window`. Nuovi handler `set_target_granularity`, `update_target_window`, `clear_target_window`. Save passa i 4 campi a `create_idea`/`update_idea`. |
| Migration `add_target_window_to_ideas` | DB migration (nuova) | `ADD COLUMN target_start DATE`, `target_end DATE`, `target_granularity TEXT`, `target_weekend_only BOOLEAN NOT NULL DEFAULT FALSE`. Forward = nullable on the 3 date/granularity columns; nessun backfill (default DB sufficient). |

### Domain API — `Ideajar.Ideas.TargetWindow`

```elixir
@type granularity :: :day | :month
@type t :: %{
  start: Date.t(),
  end: Date.t(),
  granularity: granularity,
  weekend_only: boolean
}

@spec from_idea(Idea.t()) :: t | nil
# returns nil if no target set; raises if partial state slipped past validation
# (defensive — validate_changeset/1 should make this unreachable)

@spec format(t, today :: Date.t()) :: String.t()
# user-facing Italian label, year-omitted iff start.year == end.year == today.year

@spec validate_changeset(Ecto.Changeset.t()) :: Ecto.Changeset.t()
# enforces:
#   - all-or-nothing on (target_start, target_end, target_granularity)
#   - target_end >= target_start
#   - granularity == :month → start.day == 1 AND end == Date.end_of_month(end)
#   - granularity == :day → coerce target_weekend_only to false
#   - partial state → add_error(:target, "Periodo non valido")

@spec month_label(integer) :: String.t()
# 1 → "gennaio", … 12 → "dicembre" — used by format/2
```

### Format rules (canonical)

**Year visibility**:

- Hide year iff `target_start.year == target_end.year == today.year`
- Same year (different from today): suffix `" <year>"` once at the end of the body
- Cross-year: append year on each endpoint

**Day-range body** (then apply year rule):

| Case | Format |
|---|---|
| `start == end` | `<D> <month>` |
| `start ≠ end, same month` | `<D start>-<D end> <month>` |
| `start ≠ end, cross-month, same year` | `<D start> <month start> - <D end> <month end>` |
| `start ≠ end, cross-year` | `<D start> <month start> <Y start> - <D end> <month end> <Y end>` |

**Month-range body, `weekend_only=false`**:

| Case | Format |
|---|---|
| `start.month == end.month` | `<month>` |
| `start.month ≠ end.month, same year` | `<start month>-<end month>` |
| cross-year | `<start month> <Y start> - <end month> <Y end>` |

**Month-range body, `weekend_only=true`**:

| Case | Format |
|---|---|
| `start.month == end.month` | `weekend di <month>` |
| `start.month ≠ end.month, same year` | `weekend tra <start month> e <end month>` |
| cross-year | `weekend tra <start month> <Y start> e <end month> <Y end>` |

Italian month names lowercase: `gennaio, febbraio, marzo, aprile, maggio, giugno, luglio, agosto, settembre, ottobre, novembre, dicembre`.

### LiveView assigns + events

- `@target_window :: %{granularity: :day | :month | nil, start: Date.t() | nil, end: Date.t() | nil, weekend_only: boolean, preview: String.t() | nil}`
- `"set_target_granularity"` con `%{"granularity" => "day" | "month"}` → switches inputs, resets dates
- `"update_target_window"` con form params → updates state + recomputes preview
- `"clear_target_window"` → resets the assign to empty
- `"save"` extends the existing attrs build to include the 4 fields (atom-keyed for domain callers, string-keyed for form submissions; coherence with slice-3 `category_ids` pattern)

### Card layout

Ordine dei badge nella card: `target-window → duration → budget → location` (cronologico-narrativo). Implementato come ordine sequenziale dei `<Component>.badge` chiamati nel template.

### DB schema

```sql
ALTER TABLE ideas
  ADD COLUMN target_start DATE,
  ADD COLUMN target_end DATE,
  ADD COLUMN target_granularity TEXT,
  ADD COLUMN target_weekend_only BOOLEAN NOT NULL DEFAULT FALSE;
```

### Constraints

- Validation lives at the changeset boundary (slice 7a precedent — no `CHECK` in DB; defense-in-depth opzionale, deferred).
- Default `target_weekend_only = false` a livello DB e schema, così le righe esistenti diventano automaticamente coerenti dopo la migration.
- `Ecto.Enum [:day, :month]` per `target_granularity` — string in DB, atom in Elixir.
- HEEx auto-escape sul label (anche se derivato da campi tipizzati, pin del comportamento via test).

### Out of scope (esplicito)

- Filtraggio per target window (next slice)
- Ricorrenze ("ogni weekend a maggio")
- Notifiche/promemoria
- Time-of-day (orari)
- Finestre multiple per idea
- Trattamento visivo dello scaduto
- Sorting per target window
- Time-zone handling
- Display del giorno della settimana ("mercoledì") sulle date singole

## Acceptance Criteria

### Functional / behavioral

- [ ] **F1** — Tutti gli scenari Gherkin automatabili passano (LiveView via `Phoenix.LiveViewTest`, domain via `DataCase`)
- [ ] **F2** — `Repo.insert + Repo.get` round-trip preserva i 4 campi (compresi `nil` su tutti e 4 + `weekend_only=false` come default)
- [ ] **F3** — `Idea.changeset/2` rifiuta `target_end < target_start` con il messaggio canonico `"La data di fine deve essere uguale o successiva alla data di inizio"`
- [ ] **F4** — `Idea.changeset/2` rifiuta granularità `:month` con `start.day != 1` o `end != Date.end_of_month(end)` con `errors[:target] == "Periodo non valido"`
- [ ] **F5** — `Idea.changeset/2` coerca silenziosamente `weekend_only=true` a `false` quando `granularity == :day`
- [ ] **F6** — `Idea.changeset/2` rifiuta partial-set (uno solo dei 3 campi date/granularity valorizzato) con `errors[:target] == "Periodo non valido"`
- [ ] **F7** — `TargetWindow.format/2` produce la stringa attesa per ognuno degli 11 casi della tabella di formato (test parametrico)
- [ ] **F8** — La card renderizza `<TargetWindowBadge.target_window_badge/1>` solo quando `target_start != nil`
- [ ] **F9** — Il form di edit pre-popola correttamente i controlli per ogni granularità (day/month, con/senza weekend_only)
- [ ] **F10** — "Rimuovi quando" azzera tutti e 4 i campi atomicamente in una transazione
- [ ] **F11** — Idee preesistenti senza target window continuano a renderizzare correttamente (regression test)
- [ ] **F12** — Ordine dei badge sulla card: target-window precede duration precede budget precede location

### Security

- [ ] **S1** — Il label è auto-escapato da HEEx (regression structural pin con un test che confronta la pipeline su `format/2` output)

### Operational / data

- [ ] **O1** — Migration `add_target_window_to_ideas` up/down round-trip pulito (test in `migrations_test.exs`)
- [ ] **O2** — Esistenti righe in `ideas` post-migration hanno `target_weekend_only=false` (default DB) e gli altri 3 NULL

### UI copy aggiunta (canonical)

| Elemento | Testo IT |
|---|---|
| Legend del fieldset | `Quando` (no asterisco — opzionale) |
| Helper text | `Quando pensi di farlo?` |
| Radio granularità — opzione 1 | `Giorni` |
| Radio granularità — opzione 2 | `Mesi` |
| Checkbox weekend (visible iff Mesi) | `Solo nei weekend` |
| Bottone reset | `Rimuovi quando` |
| Errore data | `La data di fine deve essere uguale o successiva alla data di inizio` |
| Errore validation generica | `Periodo non valido` |
| Mese 1 | `gennaio` |
| Mese 2 | `febbraio` |
| Mese 3 | `marzo` |
| Mese 4 | `aprile` |
| Mese 5 | `maggio` |
| Mese 6 | `giugno` |
| Mese 7 | `luglio` |
| Mese 8 | `agosto` |
| Mese 9 | `settembre` |
| Mese 10 | `ottobre` |
| Mese 11 | `novembre` |
| Mese 12 | `dicembre` |

### Documentation

- [ ] **D1** — `docs/conventions.md` UI copy table aggiornata con le 8 stringhe sopra + le 12 etichette mese (se non già presenti)
- [ ] **D2** — `docs/specs/target-window-on-ideas.md` (questo file)
- [ ] **D3** — `CONTEXT.md` schema block aggiornato con i 4 nuovi campi su `ideas`

### Validation venue

- [ ] **V1** — 4 screenshot mobile (form con granularità Giorni, form con granularità Mesi + weekend flag, card con badge mese, edit form pre-populato)
- [ ] **V1a** — Lighthouse a11y ≥95 con form aperto
- [ ] **V1b** — Keyboard-only walkthrough sul nuovo fieldset:
  1. Tab fino al radio "Giorni" → focus
  2. Arrow Down → "Mesi" selezionato
  3. Tab → primo input mese
  4. Tab → secondo input mese
  5. Tab → checkbox "Solo nei weekend"
  6. Tab → bottone "Rimuovi quando"
  7. Verifica preview testuale annunciata (live region o `aria-describedby`)

## Consistency Gate

- [x] Intent is unambiguous — 2 sviluppatori interpreterebbero ugualmente i 4 casi (day single, day range, month single, month range) + flag weekend
- [x] Every behavior has a corresponding BDD scenario — 23 scenari coprono ogni regola di formato, validazione, edit, optional, past, layout
- [x] Architecture constrains without over-engineering — 4 colonne, 1 modulo dominio, 1 component badge, 0 nuove dipendenze
- [x] Terminology consistent — `target window`, `granularity`, `weekend_only`, "Quando" coerenti tra tutti gli artifact
- [x] No contradictions between artifacts

**Verdetto: PASS** — ready for `/plan`.
