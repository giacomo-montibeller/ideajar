# Plan: Slice 5 — Duration on ideas + duration filter

**Created**: 2026-04-28
**Branch**: main (trunk-based)
**Status**: implemented
**Spec**: `docs/specs/duration-on-ideas.md`

## Build conventions (carried from slice 1 + 2 + 3 + 4)

- **Strict TDD** — RED → GREEN → REFACTOR per step.
- **Ogni commit** attraverso la skill `commit-message`.
- Pre-step gate locale: `mix compile --warnings-as-errors`, `mix format --check-formatted` (verifica esplicita exit code), `mix credo`, `mix deps.audit`, `mix test --include migration`. Stessi gate in CI su ogni push.
- Domain in `Ideajar.*`, delivery in `IdeajarWeb.*`.
- UI copy in italiano canonica appesa a `docs/conventions.md` nel commit che la introduce (slice 5: tutta la table introdotta in step 9).
- Trunk-based su `main`, no feature branches; ogni step lascia il codebase in stato green committable.

## Goal

Introdurre il concetto **durata stimata** sulle idee come campo opzionale enum a 5 valori canonici (`poche_ore`, `mezza_giornata`, `giornata`, `weekend`, `piu_giorni`) e aggiungere un filtro durata 2-state nella filter row sopra la lista delle idee, accanto al filtro categoria già esistente. Form add-idea: nuovo fieldset `Durata` con chip single-select via `aria-pressed` (toggle off = `nil`). Lista idee: filter row riorganizzata in due sub-group (`Categorie`, `Durata`) con role=group + roving tabindex su entrambi (chiude R5 di slice 4). Idee con `duration: nil` sono escluse quando ≥1 chip durata è on (decisione consapevole divergente da `CONTEXT.md` riga 81; chiude la "Decisione UX aperta" lato durata).

`Ideas.list_ideas/1` esteso con `durations: [atom]` (terza filter clause). Rule of 3 fires → REFACTOR step 5 estrae `apply_filters/2` privata in `Ideajar.Ideas` (no nuovo modulo `Filter`).

Fuori scope: `estimated_cost` / budget slider (slice 6), `lat/lng/location_name` / mappa (slice 6/7), filtro distanza (slice 7), text search (slice 8), sort per durata, modifica `duration` su idea esistente, `Ideajar.Ideas.Filter` modulo dedicato, URL params / deep-link.

## Decisioni architetturali pre-build

- **AA1 — Roving tabindex introduction nell'order corretto**: step 1 introduce hook JS `RovingTabindex` + sub-grouping `<div role="group" aria-label="Categorie">` con sub-label sr-only + rover JS attivo sul gruppo Categorie esistente (8 chip → 1 tab + 7 arrow). Step 6 aggiunge il gruppo `Durata` con il proprio rover. La transizione 8 → 1+7 sequential è additiva (Tab continua a funzionare; ArrowKeys è additivo) e chiude R5 di slice 4 prima di accumulare il debito di 13 sequential. Sub-label visivo (non sr-only) appare solo allo step 6 quando esistono due sub-block (UN sub-block solo non richiede sub-label visivo: la `<section aria-label="Filtra per:">` ha già il label visibile `Filtra per:`).
- **AA2 — Schema duration come `Ecto.Enum`**: `field :duration, Ecto.Enum, values: [:poche_ore, :mezza_giornata, :giornata, :weekend, :piu_giorni]`. Migration `add :duration, :string, null: true` (SQLite stores TEXT). NULL ammesso, no backfill, no default.
- **AA3 — `Ideajar.Ideas.Duration` modulo puro**: `values/0 :: [atom]` whitelist canonica, `parse/1 :: {:ok, atom} | :error` (usa `String.to_existing_atom/1` su whitelist, no raise), `label/1 :: String.t()` (`:poche_ore → "poche ore"`, `:piu_giorni → "più giorni"`, ecc.). Single source of truth per validation form, filter, hostile-input handler.
- **AA4 — Componente `IdeajarWeb.Components.DurationChip` nuovo modulo distinto**: due funzioni distinte (mutual exclusion ARIA contracts al type level, stesso pattern di `CategoryChip` in slice 4): `form_chip/1` (binary, `aria-pressed`, single-select enforcement lato server) e `filter_chip/1` (binary off/on, `aria-label` dinamico, `data-duration-filter-state`). DOM ids hard-coded: `form-duration-chip-<atom>` e `filter-duration-chip-<atom>`. Sostituire `CategoryChip` esistente con un god-object a 4 funzioni sarebbe peggio: `DurationChip` è isolato e l'ARIA pattern non è lo stesso (durata `aria-pressed` form vs categoria `aria-pressed` form sono entrambi binari, ma il filtro durata 2-state è diverso dal filtro categoria 3-state).
- **AA5 — Form duration state via assigns separato `@selected_duration :: atom | nil`**: parallelo al pattern slice 3 (`@selected_category_ids :: MapSet`) e slice 4 (`@filter_state :: map`). `assign_form/1` deriva il changeset combinando i form fields + `@selected_duration` come `duration: Atom.to_string(@selected_duration)` quando non nil. Toggle on: `@selected_duration = parsed_atom`. Toggle off (click su chip già selezionato): `@selected_duration = nil`. Single-select garantito strutturalmente (un singolo atom o nil, non un set). `@selected_duration` resettato a `nil` in `mount`, `close_form`, `toggle_form` (open) e su save success. Allinea con lo spec (sezione architecture + F4/F5/A1) e con il pattern delle slice precedenti (no surface-area-reduction shortcut che avrebbe divergato dalla convenzione consolidata).
- **AA6 — `@duration_filter :: MapSet.t(atom)`**: default `MapSet.new()`. Hostile input via `Duration.parse/1` (whitelist enforced). Reset on `clear_filters` e mount. Non sovrappone `@filter_state` (categorie) — due strutture distinte per due tipi di filtro.
- **AA7 — `list_ideas/1` `durations:` opt — query con NULL exclusion**: `WHERE duration IN (^selected)` (nessun `OR duration IS NULL`). Lista vuota o opt assente = clausola inattiva, NULL passa. Chiude la "Decisione UX aperta" di `CONTEXT.md` riga 81 lato durata: chi filtra per durata sta restringendo attivamente, un'idea senza durata non è "sicuramente non weekend" ma **non confermata weekend** → esclusa. Per filtri futuri (slice 6-7) la decisione sarà rivalutata.
- **AA8 — REFACTOR step 5 estrae `apply_filters/2` privata in `Ideajar.Ideas`**: rule of 3 fires (required + optional + durations). NO nuovo modulo `Ideajar.Ideas.Filter` — premature module-itis per la scala attuale. Trigger per estrazione modulo: 4+ filter clauses. Tracciato come **R5-1**.
- **AA9 — Live-region action prefix esteso (slice 4 invariante)**: `<label> attiva, ` (on), `<label> rimossa, ` (off). `Filtri rimossi, ` (clear) resta unico per entrambi i filtri categoria + durata. Il prefix usa il **label IT** del valore duration (`poche ore attiva, `, non `poche_ore attiva, `).
- **AA10 — Hook JS `RovingTabindex` test strategy**: server-render assegna `tabindex="0"` al primo chip del gruppo, `tabindex="-1"` agli altri. Hook JS arrow-key behavior testato manualmente in V1b. Server invariante (tabindex distribution + `phx-hook` attribute) testato lato `Phoenix.LiveViewTest`. Decisione: NON introdurre Wallaby/Hound per slice 5 (costo/beneficio sfavorevole; `phx-hook` è codice locale di 30 righe, V1b è sufficiente).
- **AA11 — Sub-block role=group con sub-label dinamico**: `<div role="group" aria-label="Categorie">` e `<div role="group" aria-label="Durata">` sotto `<section aria-label="Filtra per:">`. Sub-label visivo (`<p class="text-xs">Categorie</p>`) appare solo quando esistono entrambi i sub-block (step 6); nello step 1 solo `aria-label` sr-only.
- **AA12 — Save success preserva `@duration_filter`** (slice 4 invariante esteso): submit form non resetta il filter state (categoria o durata). Save success resetta `@last_filter_action` a `nil` (slice 4). F11/F12 estesi a durata.
- **AA13 — Out-of-scope guard test rivisto**: l'asserzione regex in `index_test.exs` rimuove `Durata` dalla lista negativa; conserva `Budget|Distanza|Cerca`. Aggiunge asserzione **positiva** che `Durata` appaia nella filter row sub-block label e nel form fieldset legend (per evitare regression silente che rimuoverebbe il sub-block).
- **AA14 — XSS regression duration via badge label**: `Duration.label/1` è hard-coded (no path di iniezione realistico). Test sintetico: badge component reso con un mock label `<script>` → assert auto-escape via `Phoenix.LiveViewTest`.
- **AA15 — Form chip `aria-pressed` derivato da `@selected_duration`**: `pressed?={@selected_duration == @duration}` (atom equality, no string conversion). Single-select garantito dal tipo (`atom | nil`, non `MapSet`/`list`). Toggle-off via clic sul chip pressed risulta in `@selected_duration = nil`.
- **AA16 — Migration test in `test/ideajar/migrations_test.exs`**: aggiunge `add_duration_to_ideas` migration come ottava entry nel modulo unico (per evitare race su `:auto` mode). Roundtrip up/down/up + insert con duration valida + insert con NULL + assert SQLite column type TEXT.
- **AA17 — Plan flip + UI copy table append in step 9 (last step)**: tutta la table `slice-5 UI copy` appesa a `docs/conventions.md` nello step 9 commit (insieme a `CONTEXT.md` update e plan flip). Step intermedi non toccano `docs/conventions.md` per evitare drift tra "stringa renderizzata in DOM ma non documentata" durante step 3-8.
- **AA18 — DOM id namespacing per durata**: form chip durata `id="form-duration-chip-<atom>"` (es. `form-duration-chip-poche_ore`), filter chip durata `id="filter-duration-chip-<atom>"`. Distinct dai category chip ids (slice 3 `category-chip-<id>`, slice 4 `filter-chip-<id>`). Pinato in step 3/6 RED.
- **AA19 — Helper text NULL-exclusion (UX B1 fix)**: il filter sub-block durata mostra **sempre** un helper text statico sotto il sub-label: `Le idee senza durata sono nascoste quando un filtro è attivo.` Visibile dallo step 6 (quando il sub-block compare); SR-readable come testo regular nel DOM. Risolve il "NULL exclusion undiscoverable" gap: l'utente sighted vede l'avviso, l'SR-user lo legge come parte del flow di lettura della filter row. NON un alert; non condizionale al filter state (presente sempre, anche con filter off, per ridurre cognitive load — non ricomparire quando il filtro si attiva).
- **AA20 — Live-region compound-state suffix (UX B2 fix)**: quando l'azione corrente è su un gruppo (categoria O durata) e l'**altro** gruppo ha ≥1 filtro attivo, il live-region annuncia il prefix dell'azione corrente + un suffix che indica lo stato compound:
  - Solo durata attivo, action su durata: `weekend attiva, 1 idea`
  - Durata attivo + categoria attivo, action su durata: `weekend attiva, 1 idea, filtri categoria attivi`
  - Durata attivo + categoria attivo, action su categoria: `mare obbligatoria, 1 idea, filtri durata attivi`
  - Solo categoria attivo, action su categoria: `mare obbligatoria, 2 idee` (slice 4 invariante, no suffix perché altro gruppo è inattivo)
  - `Mostra tutte`: `Filtri rimossi, 6 idee` (no suffix, tutti i filtri ora inattivi)

  Helper privato `compound_suffix/2` (riceve `filter_state`, `duration_filter`) che ritorna `", filtri categoria attivi"`, `", filtri durata attivi"`, o `""`. Risolve il "compound state silente" gap.
- **AA21 — Sub-block role=group `aria-label` disambiguato (UX W3 fix)**: per evitare collision dello screen-reader announce tra il `<legend>Durata</legend>` del form fieldset e il sub-label `Durata` del filter sub-block, l'`aria-label` del role=group è `Filtra per categoria` e `Filtra per durata` (non bare `Categorie`/`Durata`). Sub-label visivo (`<p class="text-xs">`) resta `Categorie`/`Durata` per economia visiva. SR sente "Filtra per:, group Filtra per categoria, button mare ...".
- **AA22 — Changeset error override per `Ecto.Enum` (Design B2 fix)**: l'error message di default di `Ecto.Enum` cast è `"is invalid"`. Override pinato concretamente in step 2 GREEN come helper privato:
  ```elixir
  defp override_duration_error(%Ecto.Changeset{errors: errors} = cs) do
    case Keyword.get(errors, :duration) do
      {"is invalid", opts} ->
        new_errors = Keyword.put(errors, :duration, {"Durata non valida", opts})
        %{cs | errors: new_errors, valid?: false}
      _ ->
        cs
    end
  end
  ```
  Pipeline changeset: `cast(...) |> override_duration_error() |> trim_text(:title) |> ...`. Il pattern match è scoped a `:duration` only, non interferisce con altri error messages (es. `:title` required, `:url` invalid).

## Acceptance Criteria

> Mappatura uno-a-uno con `docs/specs/duration-on-ideas.md`.

### Functional / behavioral

- [ ] **F1** — Tutti gli scenari Gherkin automatabili passano (DataCase + LiveViewTest).
- [ ] **F2** — `Idea.changeset/2` accetta `duration` come stringa via `Ecto.Enum`, NULL ammesso, error `"Durata non valida"` per stringa fuori whitelist.
- [ ] **F3** — Submit form senza duration → idea persistita con `duration: nil`.
- [ ] **F4** — Single-select form: cliccando un duration chip diverso, il precedente ritorna a `aria-pressed="false"`.
- [ ] **F5** — Toggle off form: cliccando il chip pressed, ritorna a `false` e `@selected_duration` torna a `nil`.
- [ ] **F6** — `Ideas.list_ideas([])` invariato dalla slice 4 (regression test esplicito).
- [ ] **F7** — `Ideas.list_ideas([durations: [:weekend]])` ritorna solo idee con `duration = :weekend`, escludendo NULL.
- [ ] **F8** — `Ideas.list_ideas([durations: [:weekend, :giornata]])` ritorna OR (union dei match).
- [ ] **F9** — `Ideas.list_ideas([required: [@mare_id], durations: [:weekend]])` combina in AND tra clausole (categoria-required AND durata).
- [ ] **F10** — `Ideas.list_ideas([durations: []])` equivalente a `[durations: nil]` o opt assente: NULL passa, tutte le idee.
- [ ] **F11** — Filter chip durata 2-state cycle (off → on → off); 3 click consecutivi sullo stesso chip riportano allo stato iniziale.
- [ ] **F12** — `clear_filters` resetta sia `@filter_state` (categoria) sia `@duration_filter` (durata); lascia intoccato `@selected_duration` (form state).
- [ ] **F13** — Idea card mostra duration badge solo quando `idea.duration != nil`.
- [ ] **F14** — Filter survives form submission (slice 4 F11 esteso a durata): submit form con filter durata attivo non resetta `@duration_filter`.
- [ ] **F15** — New idea outside duration filter is hidden (slice 4 F12 esteso a durata): filter `weekend` attivo + submit idea con `duration: :giornata` → idea creata ma NON in lista.
- [ ] **F16** — New idea con duration NULL is hidden quando filter durata attivo: filter `weekend` attivo + submit idea senza duration → idea creata ma NON in lista (AA7 NULL exclusion).

### Accessibility

- [ ] **A1** — Form chip ha `aria-pressed="true|false"` corretto, derivato da `@selected_duration`.
- [ ] **A2** — Filter chip durata ha `aria-label` esattamente `<label>` o `<label> attiva` (label IT, non atom).
- [ ] **A3** — Filter chip durata ha `data-duration-filter-state` esattamente `off` o `on`.
- [ ] **A4** — Cue visivo non-color (WCAG 1.4.11): off = no icon, on = `<.icon name="hero-check" />` (riuso slice 4).
- [ ] **A5** — Live-region action prefix esteso: `<label> attiva, `, `<label> rimossa, `; `Filtri rimossi, ` resta unico (slice 4) e copre entrambi i filtri.
- [ ] **A6** — Roving tabindex categorie (step 1): server-render `tabindex="0"` solo sul primo chip categoria; `tabindex="-1"` sui restanti 7. Container ha `phx-hook="RovingTabindex"` + `data-roving-tabindex-group="filter-categories"`.
- [ ] **A7** — Roving tabindex durata (step 6): stesso comportamento, gruppo `data-roving-tabindex-group="filter-durations"`. Primo chip durata `tabindex="0"`, restanti 4 `-1`.
- [ ] **A8** — Form chip durata: nessun rover; tutti i chip in tab order standard (`tabindex` non specificato → 0 implicito). ArrowRight su form chip non muove focus (no `phx-hook` sul container del form fieldset).
- [ ] **A9** — Hit area chip durata ≥ 44×44 CSS px (riuso `chip_base_class/0` di `CategoryChip`, da estrarre in `IdeajarWeb.Components.ChipBase` o helper module condiviso — vedi step 4 REFACTOR).
- [ ] **A10** — Sub-group ARIA: `<div role="group" aria-label="Filtra per categoria">` (step 1) e `<div role="group" aria-label="Filtra per durata">` (step 6) — aria-label esplicitamente disambiguato per non collidere con `<legend>Durata</legend>` del form (AA21). Step 6 aggiunge anche sub-label visivo per entrambi (`<p class="text-xs">Categorie</p>` e `<p class="text-xs">Durata</p>`, label brevi visivi).
- [ ] **A12** — Helper text NULL-exclusion: filter row sub-block durata renderizza `Le idee senza durata sono nascoste quando un filtro è attivo.` come testo statico sotto il sub-label, sempre visibile (AA19).
- [ ] **A13** — Live-region compound-state suffix: il prefix dell'azione corrente è seguito da `, filtri categoria attivi` o `, filtri durata attivi` quando l'altro gruppo ha ≥1 filtro on (AA20). `Filtri rimossi` non ha mai suffix.
- [ ] **A11** — DOM id distinctness: form-duration-chip-`<atom>`, filter-duration-chip-`<atom>`, distinct dai category chip ids. Pinato in step 3/6 RED.

### Security / robustness

- [ ] **S1** — `toggle_duration_filter` con duration fuori whitelist → no-op silenzioso (test enumerated cases: `"schifoso"`, `""`, `"WEEKEND"`, `"poche_ora"`, `"poche ore"` non-atom-form).
- [ ] **S2** — `toggle_duration_filter` con payload non-string (integer 42, list `[]`, map `%{}`) → no-op silenzioso, no crash.
- [ ] **S3** — `toggle_form_duration` con duration fuori whitelist → no-op (form param invariato).
- [ ] **S4** — Save form con `duration` manomessa via devtools/curl (`"<script>"`, `"injected"`) → changeset error `"Durata non valida"`, idea non persistita.
- [ ] **S5** — `Duration.parse/1` non lancia su input arbitrari (no `String.to_atom/1`; solo `to_existing_atom/1` su whitelist statica).
- [ ] **S6** — XSS regression badge: badge reso con label `<script>` → HTML escaped (test sintetico via mock).
- [ ] **S7** — `clear_filters` su filtri vuoti → idempotente (slice 4 invariante).
- [ ] **S8** — Mutua esclusione type-level dei due ARIA contracts in `DurationChip`: `form_chip/1` non accetta attr `state`; `filter_chip/1` non accetta attr `pressed?`. Compile-time enforcement (parallelo a S4 di slice 4).

### Operational / data

- [ ] **O1** — Migration `AddDurationToIdeas` reversibile loss-free pre-popolamento; `mix ecto.migrate` + `mix ecto.rollback` + `mix ecto.migrate` round-trip in `migrations_test.exs`.
- [ ] **O2** — SQLite column type pinning: `PRAGMA table_info(ideas)` mostra `duration TEXT NULLABLE`.
- [ ] **O3** — `Ecto.Adapters.SQL.to_sql/2` su `list_ideas([durations: [:weekend]])` ritorna SQL contenente `~r/"duration"\s+IN/i` (no `IS NULL`).
- [ ] **O4** — Performance sanity: `list_ideas([required: [_], optional: [_], durations: [_]])` con 100 idee fixture risponde in <100ms (sanity, non strict CI gate). Riuso pattern slice 4 O3.

### Validation venue

- [ ] **V1** — 4 screenshot mobile (iPhone 13 + Pixel 7 + 360px Pixel 4a): form con duration chip, filter row con entrambi sub-block + sub-label visivo, idea card con badge durata, empty-result state combinato (mare required + weekend on, 0 match).
- [ ] **V1a** — Lighthouse a11y mediana ≥95 su 3 run con filter mix categoria+durata.
- [ ] **V1b** — Keyboard-only walkthrough esplicito:
  1. Tab da `+ Aggiungi idea` → primo filter chip categoria (rover, tabindex=0).
  2. ArrowRight cicla 7 chip categoria → wrap al primo. Verifica focus visibile.
  3. Tab → primo filter chip durata (secondo rover, tabindex=0).
  4. ArrowRight cicla 4 chip durata → wrap al primo.
  5. Tab → `Mostra tutte` (se reso).
  6. Apri form: Tab dentro fieldset categorie passa per tutti gli 8 chip (no rover sul form), poi a fieldset durata (5 chip, no rover), poi `Salva`.
  7. Verifica live-region annuncia "weekend attiva, N idea/idee" dopo cycle.

### Documentation

- [ ] **D1** — `docs/conventions.md` UI copy table aggiornata (step 9 commit unico).
- [ ] **D2** — `CONTEXT.md` aggiornato per chiudere "Decisione UX aperta" lato durata (NULL escluso quando filtro durata attivo). Filtri futuri da rivalutare slice per slice.
- [ ] **D3** — `test/ideajar_web/live/idea_live/index_test.exs`: out-of-scope guard regex aggiornato (`Budget|Distanza|Cerca`); aggiunge asserzione positiva `Durata` presente nel filter row sub-block + form legend.
- [ ] **D4** — `test/ideajar/docs_test.exs`: nuova `describe "docs/conventions.md — slice 5 UI copy"` con tutte le stringhe canoniche.

### UI copy aggiunta (canonical)

| Elemento                                   | Testo IT                                  |
|--------------------------------------------|-------------------------------------------|
| Label fieldset durata (form)               | `Durata` (no asterisco — opzionale)       |
| Helper text form duration                  | (nessuno — campo opzionale)               |
| Chip durata 1 (atom `:poche_ore`)          | `poche ore`                               |
| Chip durata 2 (atom `:mezza_giornata`)     | `mezza giornata`                          |
| Chip durata 3 (atom `:giornata`)           | `giornata`                                |
| Chip durata 4 (atom `:weekend`)            | `weekend`                                 |
| Chip durata 5 (atom `:piu_giorni`)         | `più giorni`                              |
| Errore duration invalida                   | `Durata non valida`                       |
| Sub-label filter Categorie (visivo)        | `Categorie`                               |
| Sub-label filter Durata (visivo)           | `Durata`                                  |
| Aria-label sub-block categorie (SR)        | `Filtra per categoria`                    |
| Aria-label sub-block durata (SR)           | `Filtra per durata`                       |
| Helper text NULL-exclusion                 | `Le idee senza durata sono nascoste quando un filtro è attivo.` |
| Aria-label filter chip off                 | `<label>`                                 |
| Aria-label filter chip on                  | `<label> attiva`                          |
| Live-region action prefix on               | `<label> attiva, `                        |
| Live-region action prefix off              | `<label> rimossa, `                       |
| Live-region compound suffix categoria      | `, filtri categoria attivi`               |
| Live-region compound suffix durata         | `, filtri durata attivi`                  |
| Badge durata su idea card                  | `<label>` (label IT, non atom)            |

## Scenario → Step → Test traceability

| Gherkin Scenario | Step | Test name draft |
|---|---|---|
| Selecting a duration chip stores the duration on save | 3 | `selecting form duration chip persists duration` |
| Selecting and unselecting a duration chip leaves duration NULL | 3 | `toggling form duration chip off leaves nil` |
| Submitting form without selecting duration leaves NULL | 3 | `save without duration persists nil` |
| Selecting a different duration chip swaps the selection | 3 | `single-select swap works` |
| Submitting an invalid duration string is rejected | 3 | `save with invalid duration fails with canonical error` |
| Idea cards show a duration badge when duration is set | 4 | `card renders duration badge conditional on value` |
| Visiting / shows filter row with both Categorie and Durata sub-blocks | 6 | `filter row has two role=group sub-blocks` |
| Clicking a duration filter chip cycles off → on → off | 6 | `cycling filter duration chip rotates 2-state` |
| One duration chip filters to ideas with that duration | 6 | `single duration filter selects matching ideas` |
| Multiple duration chips form an OR | 6 | `multiple duration filters combine OR` |
| Ideas with NULL duration hidden when filter active | 6 | `null duration excluded when filter active` |
| Ideas with NULL duration visible when no filter active | 6 | `null duration visible when no filter active` |
| Duration filter combines with category filter as AND | 7 | `combined category+duration filters AND` |
| Combined filter with no match shows empty-result state | 7 | `combined filter no match renders empty state` |
| Activating duration filter updates live-region | 6 | `live region announces duration filter action` |
| Duration filter zero match shows empty state | 6 | `duration filter zero match renders empty state` |
| "Mostra tutte" resets both category and duration | 7 | `Mostra tutte resets both filter types` |
| Resetting filters does not touch form duration selection | 8 | `clear_filters preserves form duration` |
| Activating filter does not touch form duration | 8 | `toggle_duration_filter preserves form` |
| Refresh resets duration filter | 8 | `refresh resets duration filter to empty MapSet` |
| **F16** — New idea con duration NULL hidden when filter active | 8 | `new null-duration idea hidden when filter active` |
| toggle_duration_filter unknown string is no-op | 6 | `hostile filter duration string is no-op` |
| toggle_duration_filter non-string payload is no-op | 6 | `hostile filter duration non-string is no-op` |
| Form save with duration outside whitelist rejected | 3 | `save with hostile duration fails canonical error` |
| ArrowRight category chip moves within sub-group | 1 | `roving tabindex distributes on category chips` |
| ArrowRight wraps last to first | (V1b manual) | — |
| ArrowLeft first wraps to last | (V1b manual) | — |
| Tab from category sub-group to duration sub-group | (V1b manual) | — |
| Form chip remains sequential (no rover) | 3 | `form duration chips have no roving hook` |
| list_ideas/1 with no opts returns all | 5 | `regression list_ideas([]) unchanged from slice 4` |
| list_ideas/1 combines category and duration AND | 5 | `combined filter clauses compose AND` |
| list_ideas/1 with empty durations does not exclude NULL | 5 | `empty durations list does not exclude null` |
| Out-of-scope guard | 9 | `out-of-scope filter UI guard updated` |
| Malicious duration label is escaped on render | 4 | `duration badge auto-escapes label` |

## User-Facing Behavior

> Sync con `docs/specs/duration-on-ideas.md`. Test ExUnit citano gli scenari per nome con commento `# Scenario: …`.

(Scenari completi nel file spec; qui il plan riporta solo i nomi-chiave per traceability.)

## Steps

### Step 1: Roving tabindex hook + filter row sub-grouping per Categorie

**Complexity**: complex
**Rationale**: chiude R5 di slice 4 prima di accumulare 13 chip sequential. Lo step è additivo (Tab continua a funzionare; arrow keys è un'aggiunta) e introduce il pattern che il filter row di slice 5 userà su due sub-group.

**RED** (`test/ideajar_web/live/idea_live/index_test.exs` extension):
1. Mount: render contiene `<div role="group" aria-label="Filtra per categoria" data-roving-tabindex-group="filter-categories" phx-hook="RovingTabindex">` annidato dentro `<section aria-label="Filtra per:">`. Asserto via regex sul HTML. (AA21: aria-label è "Filtra per categoria" non "Categorie" per evitare collision con il `<legend>Durata</legend>` del form quando step 6 aggiunge il secondo gruppo.)
2. Server-rendered tabindex distribution: solo il primo `<button id="filter-chip-N">` ha `tabindex="0"`; gli altri 7 hanno `tabindex="-1"`. Verifica via `Regex.scan` che count `tabindex="0"` sui filter chip sia esattamente 1.
3. Form chip categoria invariato: nessun `tabindex` esplicito sui form `category-chip-N` (regression slice 3).
4. **Hook JS RovingTabindex caricato in `app.js`**: asserzione static via lettura del file JS in test (`assert File.read!("assets/js/app.js") =~ "RovingTabindex"` o equivalente). Pinato come hook registration regression (chiude AA10).
5. Sub-label aria-label-only (non visibile): `<div role="group">` ha `aria-label="Categorie"` ma il sub-label visibile `Categorie` NON appare nel DOM in step 1 (verrà aggiunto in step 6 quando esisterà il secondo sub-block per evitare ridondanza visiva).

**GREEN**:
- Nuovo file `assets/js/hooks/roving_tabindex.js`: hook `RovingTabindex` che intercetta `keydown` per ArrowLeft/ArrowRight su elementi figli `<button>`; sposta `tabindex="0"` sul focused, `tabindex="-1"` sugli altri; wrap aritmetico last↔first; calls `.focus()`.
- `assets/js/app.js`: import e registrazione del hook nel LiveSocket `hooks` config.
- Template `index.html.heex`: avvolgi il loop `<.filter_chip :for={...} />` in `<div role="group" aria-label="Filtra per categoria" data-roving-tabindex-group="filter-categories" phx-hook="RovingTabindex" id="filter-categories-group">`.
- Estendi `filter_chip/1` (`category_chip.ex`) con attr `tabindex :: integer, default: -1`. Render output: `tabindex={@tabindex}`.
- LV `index.ex`: helper `category_filter_tabindex/2` che ritorna `0` per il primo `category` e `-1` per gli altri (server-rendered initial state; il hook JS riprende dal client).

**REFACTOR**: docstring nel hook che spiega il pattern WAI-ARIA APG roving tabindex e dice "arrow key behavior testato in V1b manual; server invariante in `index_test.exs`".

**Files**: `assets/js/hooks/roving_tabindex.js` (new), `assets/js/app.js` (extend), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `lib/ideajar_web/live/idea_live/index.ex` (helper), `lib/ideajar_web/components/category_chip.ex` (attr `tabindex`), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: A6, AA1, AA10.

### Step 2: Schema migration + `Duration` module + changeset

**Complexity**: standard
**Rationale**: schema/domain isolato — niente UI, niente filter. Foundational per step 3+.

**RED** (multipli):

a. `test/ideajar/migrations_test.exs` extension:
1. Aggiunge `@add_duration_migration Ideajar.Repo.Migrations.AddDurationToIdeas` come ottava entry.
2. Roundtrip schema: `up` → asserisce `PRAGMA table_info(ideas)` contiene riga `duration` con `type = "TEXT"` e `notnull = 0`. `down` → riga `duration` assente. `up` di nuovo → riga ricompare.
3. Insert/select valore valido: `up` → `INSERT INTO ideas (..., duration) VALUES (..., 'weekend')` → `SELECT duration FROM ideas` ritorna `"weekend"`.
4. Insert/select NULL: `INSERT INTO ideas (..., duration) VALUES (..., NULL)` → `SELECT duration` ritorna `nil`.
5. **B3 fix — data preservation across rollback (rivisto iter 2)**: pre-rollback inserisci 2 idee, una con `duration: 'weekend'` e una con `duration: NULL`. Esegui `down` (drop column). Verifica che le 2 righe esistano ancora (`SELECT COUNT(*) FROM ideas == 2`) e che le altre colonne (`title`, `description`, `url`) siano intatte. Esegui `up` di nuovo. Verifica che le 2 righe abbiano `duration = NULL` (drop+add reset = colonna ripristinata vuota; il valore `'weekend'` originale è perso, **questo è il comportamento documentato** della SQLite ALTER TABLE DROP COLUMN). Pin esplicito che `down` NON cancella le idee, solo la colonna.
6. Aggiunge il restore della migration in `on_exit` (riga 100-120 del modulo).

b. `test/ideajar/ideas/duration_test.exs` (new):
1. `Duration.values() == [:poche_ore, :mezza_giornata, :giornata, :weekend, :piu_giorni]`.
2. `Duration.parse("weekend") == {:ok, :weekend}` per ogni atom canonico.
3. `Duration.parse("schifoso") == :error`, `Duration.parse("") == :error`, `Duration.parse(nil) == :error`, `Duration.parse(42) == :error`.
4. `Duration.label(:poche_ore) == "poche ore"`, `Duration.label(:piu_giorni) == "più giorni"`, ecc. per ogni atom.
5. **Pin XSS-via-atom**: nessun atom canonico contiene caratteri HTML (`<`, `>`, `&`). Asserzione algoritmica: `for atom <- Duration.values(), do: refute Duration.label(atom) =~ ~r/[<>&]/`.

c. `test/ideajar/ideas_test.exs` (changeset extension):
1. `Idea.changeset(%Idea{}, %{title: "X", categories: [c], duration: "weekend"}).changes[:duration] == :weekend`.
2. `changeset` con `duration: nil` → `:duration` non in changes (NULL ammesso, non required).
3. `changeset` con `duration: ""` → `:duration` cast a `nil` (Ecto.Enum cast empty string).
4. `changeset` con `duration: "schifoso"` → `errors[:duration] == {"Durata non valida", _}` (override del default Ecto error message).
5. `changeset` con `duration: "<script>"` → stesso error (whitelist enforced).

**GREEN**:
- Nuova migration `priv/repo/migrations/20260428000005_add_duration_to_ideas.exs`:
  ```elixir
  def change, do: alter table(:ideas), do: add :duration, :string, null: true
  ```
- Nuovo modulo `lib/ideajar/ideas/duration.ex` con `values/0`, `parse/1`, `label/1`. Whitelist `@values` come module attribute. `parse/1` usa `String.to_existing_atom/1` dentro un `try/rescue ArgumentError → :error` (atom potrebbe non esistere; safe).
- Schema `Ideajar.Ideas.Idea`: aggiungere `field :duration, Ecto.Enum, values: Duration.values()` — **single-source via module attribute** (chiude W2 design, elimina R5-5 drift). `Duration.values/0` ritorna la lista compilata; Ecto la valuta a compile time perché è una chiamata a function pura su un modulo già caricato. Test pin: `assert Idea.__schema__(:type, :duration) == {:parameterized, Ecto.Enum, %{values: Duration.values()}}` (o equivalente API stable).
- Changeset: aggiungere `:duration` a `@castable_fields`. Pipeline:
  ```elixir
  idea
  |> cast(attrs, @castable_fields)
  |> override_duration_error()
  |> trim_text(:title)
  |> ...
  ```
  Helper `override_duration_error/1` (AA22 — pinato concretamente):
  ```elixir
  defp override_duration_error(%Ecto.Changeset{errors: errors} = cs) do
    case Keyword.get(errors, :duration) do
      {"is invalid", opts} ->
        new_errors = Keyword.put(errors, :duration, {@duration_invalid, opts})
        %{cs | errors: new_errors}
      _ ->
        cs
    end
  end
  ```
  Module attribute: `@duration_invalid "Durata non valida"`. Pattern match scoped a `:duration` only — non tocca altri error.

**REFACTOR**:
- Pin equality `Duration.values() == @ecto_enum_values` in `IdeaTest` o `DurationTest` (catches drift se uno cambia senza l'altro).

**Files**: `priv/repo/migrations/20260428000005_add_duration_to_ideas.exs` (new), `lib/ideajar/ideas/duration.ex` (new), `lib/ideajar/ideas/idea.ex` (extend), `test/ideajar/migrations_test.exs` (extend), `test/ideajar/ideas/duration_test.exs` (new), `test/ideajar/ideas_test.exs` (extend).
**Spec mapping**: F2, F3, S5, AA2, AA3, O1, O2.

### Step 3: Form `DurationChip.form_chip/1` + fieldset + `toggle_form_duration` + persistence

**Complexity**: standard
**Rationale**: pure delivery layer; il dominio è già pronto da step 2.

**RED** (`test/ideajar_web/components/duration_chip_test.exs` new + LV test extension):

a. Component test `duration_chip_test.exs`:
1. `form_chip/1` con `pressed?: false` → `aria-pressed="false"`, no icon, `id="form-duration-chip-weekend"`, `phx-click="toggle_form_duration"`, `phx-value-duration="weekend"`. Class state default.
2. `form_chip/1` con `pressed?: true` → `aria-pressed="true"`, `<.icon name="hero-check" />` presente, class state pressed.
3. **Type-level mutua esclusione (S8)**: `form_chip/1` non accetta attr `state`; tentativo di passarlo produce compile-time `attr_undefined` warning. Verifica via `Phoenix.Component.attr_undefined?` o assertion strutturale sul modulo.
4. Hit area: class string contiene `min-h-11 min-w-11`.
5. Label IT renderizzato: `assert html =~ "poche ore"` per `duration: :poche_ore` (non `poche_ore`).

b. LV test `index_test.exs` extension (asserts contro `@selected_duration` per AA5/B1 alignment):
1. Apri form: render contiene `<fieldset>` con `<legend>` `Durata` (no asterisco) + 5 form-duration-chip. Mount: `view.assigns.selected_duration == nil`.
2. Click `phx-value-duration="weekend"` → `view.assigns.selected_duration == :weekend`. Chip weekend render con `aria-pressed="true"`.
3. Click weekend di nuovo → `view.assigns.selected_duration == nil`. Tutti i chip durata render con `aria-pressed="false"`.
4. Click giornata when `:weekend` selected → `view.assigns.selected_duration == :giornata`. weekend `aria-pressed="false"`, giornata `aria-pressed="true"`.
5. **Save success con duration**: `@selected_duration == :weekend` + title valido + 1 categoria → submit → idea persistita con `duration: :weekend`. `@selected_duration` reset a `nil` post-save (parallelo a `@selected_category_ids` reset slice 3).
6. **Save success senza duration**: title valido + 1 categoria, `@selected_duration == nil` → idea persistita con `duration: nil`.
7. **`close_form` reset**: open form, click weekend (`@selected_duration == :weekend`), click `close_form` → `@selected_duration == nil` (parallelo a slice 3 form reset).
8. **Hostile toggle_form_duration (S3)**: scenario uniform list (vedi B2 fix in step 6) — `render_click(view, "toggle_form_duration", %{"duration" => raw})` per ognuno dei 7 hostile inputs → `@selected_duration` invariato.
9. **Save con duration manomessa (S4)**: payload `%{"idea" => %{title: "X", categories: ..., duration: "<script>"}}` → re-render con error `"Durata non valida"` sotto il fieldset. Idea NON in DB.
10. **DOM id distinctness (AA18)**: render con form aperto contiene `Regex.scan(~r/id="(form-duration-chip-\w+|filter-chip-\d+|category-chip-\d+)"/)` con counts: 5 form-duration-chip-* + 8 filter-chip-* + 8 category-chip-* = 21. Nessun id duplicato.
11. **A8 form chip no-rover**: il fieldset durata del form non ha `phx-hook="RovingTabindex"`. Tutti i 5 form-duration-chip hanno `tabindex` non specificato (default 0).

**GREEN**:
- Nuovo modulo `lib/ideajar_web/components/duration_chip.ex` con `form_chip/1`. Riusa l'estetica di `CategoryChip.category_chip/1` (pressed/unpressed visual style).
- Estendi `IdeaLive.Index`:
  - Mount + open form + close_form + save success: `assign(:selected_duration, nil)` (parallelo `reset_categories/1`).
  - Handler `handle_event("toggle_form_duration", %{"duration" => raw}, socket) when is_binary(raw)`:
    ```elixir
    case Duration.parse(raw) do
      {:ok, atom} ->
        new_value = if socket.assigns.selected_duration == atom, do: nil, else: atom
        {:noreply, assign(socket, :selected_duration, new_value)}
      :error ->
        {:noreply, socket}
    end
    ```
    Catchall: `def handle_event("toggle_form_duration", _, socket), do: {:noreply, socket}` per non-binary payloads.
  - `save` handler esteso a iniettare `duration: Atom.to_string(@selected_duration)` (o omesso se nil) negli `attrs_with_categories` prima di chiamare `Ideas.create_idea/1`.
- Template `index.html.heex`: nuovo `<fieldset class="fieldset">` sotto fieldset categorie, con `<legend>Durata</legend>` + 5 form-duration-chip.
- Override Ecto.Enum default error message a `"Durata non valida"`: in changeset, dopo `cast`, helper `traverse_duration_error/1` che riscrive l'errore.

**REFACTOR**:
- Estrarre `chip_base_class/0` da `CategoryChip` in un helper module `IdeajarWeb.Components.ChipBase` o lasciarlo duplicato? **Decisione**: per slice 5 lasciare duplicato (`DurationChip` ridichiara `chip_base_class/0` privato). Estrazione triggata da rule of 3 (slice 6+ aggiunge un terzo chip family). Tracciato come **R5-2**.

**Files**: `lib/ideajar_web/components/duration_chip.ex` (new), `lib/ideajar_web/live/idea_live/index.ex` (extend), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `lib/ideajar/ideas/idea.ex` (error message override), `test/ideajar_web/components/duration_chip_test.exs` (new), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: F3, F4, F5, A1, A8, A11, S3, S4, S8, AA4, AA5, AA15, AA18.

### Step 4: Idea card duration badge + XSS regression

**Complexity**: trivial
**Rationale**: rendering condizionale puro; nessun nuovo handler.

**RED**:
1. Idea con `duration: :weekend` → render contiene `<span data-testid="idea-duration-badge">weekend</span>` (label IT).
2. Idea con `duration: nil` → no element matching `data-testid="idea-duration-badge"` per quell'idea.
3. **XSS regression sintetica**: render del badge component con un mock label `"<script>"` (via assigns directly o test fixture) → HTML contiene `&lt;script&gt;` (escaped). Pin via regex.
4. **Position pin**: il badge appare DOPO `<ul aria-label="Categorie">` nella card (DOM source order). Verifica via regex match position.

**GREEN**:
- Aggiungi un piccolo function component nel modulo `IdeajarWeb.Components.DurationChip` (o helper inline nel template): `def duration_badge(assigns) ~H"<span data-testid=...>...</span>"`.
- Template `index.html.heex`: dentro il `<li :for={idea <- @ideas}>`, dopo la `<ul aria-label="Categorie">`, aggiungi `<.duration_badge :if={idea.duration} duration={idea.duration} />`.

**REFACTOR**: None needed.

**Files**: `lib/ideajar_web/components/duration_chip.ex` (extend), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend), `test/ideajar_web/components/duration_chip_test.exs` (extend).
**Spec mapping**: F13, S6, AA14.

### Step 5: `list_ideas/1` `durations:` opt + `apply_filters/2` refactor

**Complexity**: complex
**Rationale**: domain layer change + rule-of-3 refactor. SQL emission pin per evitare drift su SQLite.

**RED** (`test/ideajar/ideas_test.exs` extension):
1. Setup fixture: 6 idee come Background dello spec (5 con duration valida, 1 NULL).
2. **F6 regression**: `list_ideas([])` invariato; ritorna 6 idee, ordinate.
3. **F7 single duration**: `list_ideas([durations: [:weekend]])` → 1 idea (`Sirolo`); idea NULL `Bagno improvviso` esclusa.
4. **F8 OR**: `list_ideas([durations: [:weekend, :giornata]])` → 2 idee (`Sirolo`, `Uffizi`); NULL escluse.
5. **F10 empty list inactive**: `list_ideas([durations: []])` → 6 idee (NULL incluse); equivalente a `list_ideas([])`.
6. **F9 combined AND**: `list_ideas([required: [@viaggio_id], durations: [:weekend]])` → solo `Sirolo` (Sirolo ha viaggio + weekend); `Parigi 4 giorni` escluso (ha viaggio ma duration `:piu_giorni`).
7. **NULL strict exclusion**: `list_ideas([durations: [:weekend]])` su DB con SOLO `Bagno improvviso` (duration NULL) → `[]`.
8. **Duplicates**: `list_ideas([durations: [:weekend, :weekend]])` equivalente a `[:weekend]` (Enum.uniq).
9. **Unknown atom**: `list_ideas([durations: [:nonexistent]])` → `[]` (Ecto.Enum non lancia, ritorna nessun match). Test esplicito che la query non crasha.
10. **SQL emission O3**: `{sql, _} = Repo.to_sql(:all, query_for_list_ideas([durations: [:weekend]]))` → `assert sql =~ ~r/"duration"\s+IN/i`; `refute sql =~ ~r/IS\s+NULL/i`.

**GREEN**:
- Estendi `Ideajar.Ideas.list_ideas/1`:
  ```elixir
  def list_ideas(opts \\ []) when is_list(opts) do
    Keyword.keyword?(opts) || raise ArgumentError, ...

    base_query
    |> apply_filters(opts)
    |> Repo.all()
    |> Repo.preload(...)
  end

  defp apply_filters(query, opts) do
    query
    |> apply_required(Keyword.get(opts, :required, []))
    |> apply_optional(Keyword.get(opts, :optional, []))
    |> apply_durations(Keyword.get(opts, :durations, []))
  end

  defp apply_durations(query, []), do: query
  defp apply_durations(query, durations) do
    from i in query, where: i.duration in ^Enum.uniq(durations)
  end
  ```

**REFACTOR**:
- Eliminare la duplicazione di `Keyword.get(opts, …)` inlining nella body di `list_ideas/1` → ora tutto è composto in `apply_filters/2`.
- Pinare `apply_filters/2` come unica entry point per nuovi filtri (slice 6+ aggiungerà budget e distance qui).

**Files**: `lib/ideajar/ideas.ex` (extend), `test/ideajar/ideas_test.exs` (extend).
**Spec mapping**: F6, F7, F8, F9, F10, AA7, AA8, O3, O4.

### Step 6: `DurationChip.filter_chip/1` + duration filter sub-group + `toggle_duration_filter` + secondo rover

**Complexity**: complex
**Rationale**: massimo cross-cutting (componente + LV handler + template + secondo rover + live-region action prefix).

**RED** (multi-file):

a. `test/ideajar_web/components/duration_chip_test.exs` extension:
1. `filter_chip/1` con `state: :off` → `data-duration-filter-state="off"`, `aria-label="weekend"`, no icon, `id="filter-duration-chip-weekend"`, `phx-click="toggle_duration_filter"`, `phx-value-duration="weekend"`. **No `aria-pressed`** (pinato).
2. `filter_chip/1` con `state: :on` → `data-duration-filter-state="on"`, `aria-label="weekend attiva"`, `<.icon name="hero-check" />` presente.
3. **S8 mutua esclusione**: `filter_chip/1` non accetta attr `pressed?`. Compile-time enforced.
4. **`tabindex` attr** opzionale, default `-1`. Render con `tabindex: 0` → `tabindex="0"`.

b. `index_test.exs` extension:
1. **Sub-block durata reso (AA11, AA21)**: render contiene `<div role="group" aria-label="Filtra per durata" data-roving-tabindex-group="filter-durations" phx-hook="RovingTabindex" id="filter-durations-group">` + 5 `<button id="filter-duration-chip-...">`.
2. **Sub-label visivo aggiunto allo step 6 (AA1, AA11)**: render contiene `<p class="text-xs">Categorie</p>` E `<p class="text-xs">Durata</p>` (entrambi visibili sopra i rispettivi sub-block). Step 1 non li aveva.
3. **Sub-block categorie aria-label aggiornato in step 6**: render contiene `aria-label="Filtra per categoria"` (rinominato da step 1; AA21). Pinato che il rename avviene in questo step (test step 6 fallirebbe in step 1 perché aria-label è ancora `Filtra per categoria` consistentemente — controllo: lo step 1 ha già `Filtra per categoria`. NB: il test pin di step 1 e step 6 usano la stessa stringa, non c'è transizione.).
4. **Helper text NULL-exclusion (A12, AA19)**: render contiene la stringa `Le idee senza durata sono nascoste quando un filtro è attivo.` esattamente una volta, posizionata dentro il sub-block durata (DOM source after sub-label, before chip group).
5. **Secondo rover (A7)**: tabindex distribution: il primo `filter-duration-chip-poche_ore` ha `tabindex="0"`; gli altri 4 `-1`. Conta `tabindex="0"` sui filter-duration-chip = 1.
6. **Cycle 2-state (F11)**: `render_click(view, "toggle_duration_filter", %{"duration" => "weekend"})` → `@duration_filter == MapSet.new([:weekend])`. Render: chip weekend `data-duration-filter-state="on"`, `aria-label="weekend attiva"`, icon presente. Lista filtrata.
7. **Toggle off (F11)**: secondo click → `@duration_filter == MapSet.new()`, chip torna a `off`.
8. **Filter matching (F7-F8)**: cycle weekend on → lista mostra solo idee con duration weekend. NULL escluse.
9. **Multi-OR (F8)**: cycle weekend on, cycle giornata on → lista mostra union.
10. **Empty result (F8 zero match)**: filter `piu_giorni` su DB senza idee piu_giorni → empty-filter state (`Nessuna idea per i filtri attivi.` + `Mostra tutte` inline). Filter chip durata restano renderizzati con stato `on`.
11. **Live-region action prefix on, no compound (A5)**: cycle weekend on con nessun filtro categoria attivo → live-region testo esattamente `weekend attiva, 1 idea` (no suffix).
12. **Live-region action prefix off (A5)**: cycle weekend off → testo `weekend rimossa, 6 idee`.
13. **Live-region compound suffix on durata-action (A13, AA20)**: filter categoria mare required già attivo, poi cycle weekend on → testo `weekend attiva, 1 idea, filtri categoria attivi`.
14. **Live-region compound suffix on categoria-action (A13, AA20)**: filter durata weekend on già attivo, poi cycle category mare to required → testo `mare obbligatoria, 1 idea, filtri durata attivi`.
15. **Live-region compound — `Filtri rimossi` no suffix**: con entrambi i gruppi attivi, click `Mostra tutte` → testo `Filtri rimossi, 6 idee` (no suffix, tutti i filtri ora inattivi). Pin.
16. **Hostile filter duration uniform list (S1, S2 — B2 fix)**: scenario outline canonical su 8 input invalidi: 5 stringhe `"schifoso"`, `""`, `"WEEKEND"`, `"poche_ora"`, `"poche ore"` + 3 non-string `42` (integer), `[]` (list), `%{}` (mappa) → per ognuno: `@duration_filter` invariato, LV process alive. Stessa lista usata in step 3 RED #8 hostile toggle_form_duration (uniformità totale, copre S2 al 100%).
17. **Form/filter durata ARIA non collide**: form-duration-chip-weekend ha `aria-pressed`; filter-duration-chip-weekend ha `aria-label`. Render contiene **entrambi** quando form è aperto e filter è attivo. Pinato.

**GREEN**:
- Estendi `lib/ideajar_web/components/duration_chip.ex` con `filter_chip/1` (parallelo a `CategoryChip.filter_chip/1`, ma 2-state).
- LV `index.ex`:
  - Mount: aggiungi `assign(:duration_filter, MapSet.new())`.
  - Handler `handle_event("toggle_duration_filter", %{"duration" => raw}, socket) when is_binary(raw)`:
    ```elixir
    case Duration.parse(raw) do
      {:ok, atom} ->
        new_set = MapSet.symmetric_difference(socket.assigns.duration_filter, MapSet.new([atom]))
        new_action = duration_action_prefix(new_set, atom)
        {:noreply, socket |> assign(:duration_filter, new_set) |> assign(:last_filter_action, new_action) |> reload_ideas()}
      :error ->
        {:noreply, socket}
    end
    ```
    Catchall: `def handle_event("toggle_duration_filter", _, socket), do: {:noreply, socket}`.
  - Helper `duration_action_prefix/2`: ritorna `"<label> attiva, "` se l'atom è in `new_set`, `"<label> rimossa, "` altrimenti.
  - Helper `compound_suffix/2(filter_state, duration_filter)` (AA20):
    - Action su durata + filter_state non vuoto → `", filtri categoria attivi"`
    - Action su categoria + duration_filter non vuoto → `", filtri durata attivi"`
    - Altro → `""`. Composizione finale: `prefix <> Pluralization.idee_count(...) <> suffix`.
  - `cycle_filter` handler (slice 4) esteso a usare `compound_suffix/2` con `:category` action.
  - `clear_filters` handler resetta `@last_filter_action = "Filtri rimossi, "` e **non** aggiunge suffix (entrambi i gruppi sono ora vuoti).
  - `derive_filter_opts/1` esteso: aggiunge `durations: MapSet.to_list(@duration_filter)` agli opts.
- Template `index.html.heex`:
  - Filter row: aggiungi sub-label visivo `<p class="text-xs">Categorie</p>` sopra il sub-block categorie esistente. Aggiorna `aria-label` del sub-block categorie a `Filtra per categoria` (era già così da step 1, no change qui — verifica solo).
  - Aggiungi nuovo `<div role="group" aria-label="Filtra per durata" ...>` (AA21) con sub-label visivo `<p class="text-xs">Durata</p>` + helper text statico `<p class="text-xs text-base-content/70">Le idee senza durata sono nascoste quando un filtro è attivo.</p>` (AA19) + 5 `<.filter_chip />` (DurationChip).

**REFACTOR**:
- Estrai helper privato `tabindex_for_first/2` riusato da entrambi i rover (categorie + durata) per evitare duplicazione del "first → 0, rest → -1".

**Files**: `lib/ideajar_web/components/duration_chip.ex` (extend), `lib/ideajar_web/live/idea_live/index.ex` (extend), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `test/ideajar_web/components/duration_chip_test.exs` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: F11, A2, A3, A4, A5, A7, A10, S1, S2, S8, AA6, AA9, AA11, AA18.

### Step 7: `clear_filters` extension + combined filter scenarios

**Complexity**: standard
**Rationale**: piccolo additivo su handler esistente + scenari combined.

**RED**:
1. **Clear durata reset (F12)**: con `@duration_filter == MapSet.new([:weekend])` e `@filter_state == %{mare.id => :required}` → `render_click(view, "clear_filters")` → `@duration_filter == MapSet.new()`, `@filter_state == %{}`, lista mostra tutte le 6 idee. Live-region testo `Filtri rimossi, 6 idee`.
2. **Clear idempotency (S7)**: `clear_filters` su DurationFilter già vuoto → no error, no change.
3. **Combined filter AND (F9)**: cycle category viaggio required + cycle duration weekend on → lista mostra solo `Sirolo`. `Parigi 4 giorni` escluso.
4. **Combined empty state**: cycle passeggiata required + cycle weekend on → empty-filter state.
5. **Mostra tutte single-instance (slice 4 F10 esteso)**: combined filter attivo + lista non vuota → bottone sotto filter row, NIENTE bottone in empty-message. Combined filter attivo + lista vuota → bottone DENTRO empty-message, NIENTE sotto filter row.

**GREEN**:
- Estendi `handle_event("clear_filters", _, socket)`: aggiungi `assign(:duration_filter, MapSet.new())` al pipeline esistente.
- `filter_active?/2` esteso: ora prende sia `filter_state` sia `duration_filter`. Helper rinominato a `any_filter_active?(filter_state, duration_filter)` o due helper separati (decisione: helper unico per evitare drift; pinato in REFACTOR).

**REFACTOR**:
- Rinomina `filter_active?/1` a `any_filter_active?/2` se serve disambiguare; oppure mantieni signature `filter_active?(filter_state, duration_filter)`. Decisione finale: `filter_active?/2` con due arg per chiarezza.

**Files**: `lib/ideajar_web/live/idea_live/index.ex` (extend), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: F9, F12, S7, slice-4 F10.

### Step 8: Form/filter state isolation regression + new-idea-outside-filter scenarios

**Complexity**: standard
**Rationale**: F14, F15, F16 esplicito; previene drift su filter survives submission.

**RED**:
1. **F14 filter durata survives form submit**: cycle weekend on → open form → submit valido (con duration giornata) → `@duration_filter == MapSet.new([:weekend])` ancora attivo. Idea creata in DB.
2. **F15 new idea outside filter is hidden**: filter weekend attivo + submit idea con `duration: :giornata` → render lista NON contiene la nuova idea; live-region count invariato dal pre-submit (`weekend attiva, N idee` con N = count pre-submit).
3. **F16 new idea NULL hidden when filter active**: filter weekend attivo + submit idea senza duration → idea creata con duration NULL; render lista NON contiene la nuova idea (NULL escluso da AA7).
4. **F12 / F14 isolation: form duration param non toccato da clear_filters**: open form, click form-duration-chip-weekend (params.duration = "weekend") → cycle filter durata giornata on → click `Mostra tutte` → form param `duration` ancora `"weekend"` (chip ancora `aria-pressed="true"`).
5. **F12 / F14 isolation: form duration param non toccato da toggle_duration_filter**: come sopra ma con `toggle_duration_filter` invece di `clear_filters`.
6. **Refresh resetta @duration_filter**: re-mount LV → `@duration_filter == MapSet.new()`.

**GREEN**: nessun nuovo codice (gli invariant sono già garantiti dall'architettura — `@duration_filter` e form params sono assigns distinti, `clear_filters` non tocca form). I test fissano l'invariante e prevengono drift.

**REFACTOR**: None needed.

**Files**: `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: F14, F15, F16, isolation invariants.

### Step 9: Out-of-scope guard + docs sync (D1, D2, D3, D4) + plan flip

**Complexity**: standard
**Rationale**: closing gate — UI copy table appesa, CONTEXT.md update, plan flip.

**RED**:
1. **D3 out-of-scope guard (rivisto)**: `index_test.exs` asserzione regex aggiornata: `refute html =~ ~r/Budget|Distanza|Cerca/i` (rimosso `Durata`). Aggiunge **asserzione positiva**: `assert html =~ "Durata"` (presente nel filter sub-block label E nel form fieldset legend; pin che il sub-block esiste e non è stato accidentalmente rimosso).
2. **D1 UI copy table presente**: `docs_test.exs` nuova `describe "docs/conventions.md — slice 5 UI copy"` con `slice_5_strings = ["Durata", "Durata non valida", "poche ore", "mezza giornata", "giornata", "weekend", "più giorni", "<nome> attiva", "<nome> rimossa"]` ma con tutti i literali (no placeholder `<nome>`). Asserzioni 1:1 sui valori canonici della UI copy table.
3. **D2 CONTEXT.md aggiornato**: nuovo describe in `docs_test.exs` `describe "CONTEXT.md — slice 5 closure"` che asserisce:
   - `assert content =~ ~r/duration.*NULL.*escluso|durata.*NULL.*esclusa/i` (closure formal della Decisione UX aperta).
   - `refute content =~ ~r/Decisione UX aperta/i` su sezione duration (la sezione viene riformulata con la decisione presa).
4. **Pre-PR gate completo**: `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo`, `mix deps.audit`, `mix test --include migration` tutti green.

**GREEN**:
- Estendi `docs/conventions.md`:
  - Nuova section **Stringhe aggiunte in slice 5 (duration on ideas)** con la table completa di AA17.
- Aggiorna `CONTEXT.md`:
  - Sostituisci la "Decisione UX aperta" rigo 80-81 con la sezione formale **Decisione su filtri non applicabili (slice 5+)**:
    > Per il filtro **durata** (slice 5): un'idea con `duration: nil` viene **esclusa** quando ≥1 chip durata è on. Razionale: chi filtra per durata sta restringendo attivamente; un'idea senza durata stimata non è "sicuramente non weekend" ma "non confermata weekend" → fuori dal match.
    > Per filtri futuri (`estimated_cost` slice 6, `distanza` slice 7) la decisione sarà rivalutata caso per caso nello spec della slice corrispondente.
- Aggiorna `test/ideajar_web/live/idea_live/index_test.exs`: regex out-of-scope guard rimuove `Durata` dalla negative, aggiunge asserzione positiva.
- Aggiungi describe slice-5 in `test/ideajar/docs_test.exs`.

- **Plan flip**: aggiorna lo stato del plan file in `plans/slice-5-duration-on-ideas.md` da `draft` (oppure `approved` post-review) a `implemented`.

**REFACTOR**: None needed.

**Files**: `docs/conventions.md` (extend), `CONTEXT.md` (update), `test/ideajar_web/live/idea_live/index_test.exs` (extend), `test/ideajar/docs_test.exs` (extend), `plans/slice-5-duration-on-ideas.md` (status flip).
**Spec mapping**: D1, D2, D3, D4, AA13, AA17.

## Complexity Classification

| Step | Complessità | Motivazione |
|------|-------------|-------------|
| 1 | **complex** | Nuovo hook JS + ARIA pattern + tabindex distribution invariant + `app.js` registration |
| 2 | standard | Migration + nuovo modulo puro + Ecto.Enum cast + custom error message |
| 3 | standard | Nuovo componente + handler + persistence; pattern ben rodato dalla slice 3 |
| 4 | trivial | Rendering condizionale puro |
| 5 | **complex** | Subquery durations + apply_filters/2 refactor (rule of 3) + SQL emission pin |
| 6 | **complex** | Cross-cutting: componente filter_chip + nuovo handler + secondo rover + live-region action prefix + sub-label visibility transition |
| 7 | standard | Additive su handler esistente + scenari combined |
| 8 | standard | Pure regression test (gli invariant sono già garantiti) |
| 9 | standard | Docs sync + plan flip; nessun cambio strutturale |

## Pre-PR Quality Gate

- [ ] `mix test --include migration` passa.
- [ ] `mix format --check-formatted` passa **con verifica esplicita exit code**.
- [ ] `mix credo` passa.
- [ ] `mix deps.audit` passa.
- [ ] `mix compile --warnings-as-errors` passa.
- [ ] `/code-review` su file toccati passa.
- [ ] **F1 traceability**: ogni `Scenario:` Gherkin ha almeno un test (vedi tabella sopra).
- [ ] **V1**: 4 screenshot in `docs/screenshots/slice-5/`.
- [ ] **V1a**: Lighthouse a11y mediana ≥95 — JSON allegati.
- [ ] **V1b**: walkthrough keyboard-only (7 step espliciti).
- [ ] CI verde sul push.

## Risks & Open Questions

- **R5-1 — `Ideajar.Ideas.Filter` modulo dedicato deferred**: rule of 3 fires con required + optional + durations, ma `apply_filters/2` privata in `Ideajar.Ideas` è sufficiente. Trigger per estrazione modulo: 4+ filter clauses (slice 6 budget). Documentato per slice 6.
- **R5-2 — `chip_base_class/0` duplicazione**: `CategoryChip` (slice 3/4) e `DurationChip` (slice 5) duplicano la helper privata. Trigger per estrazione `IdeajarWeb.Components.ChipBase`: 3° chip family (slice 6 potrebbe averne uno per budget se non usa slider).
- **R5-3 — Hook JS RovingTabindex testabile solo manualmente**: arrow-key behavior non testato in ExUnit; V1b è la safety net. Trigger per introdurre Wallaby/Hound: bug ricorrente sul behavior arrow-key. Non scattato.
- **R5-4 — Sub-label visibility transition tra step 1 e step 6**: step 1 introduce sub-block `Categorie` con sub-label sr-only; step 6 lo promuove a visibile (aggiungendo anche `Durata`). Tra step 1 e step 5 (3 commit), il sub-block `Categorie` esiste in DOM ma senza sub-label visibile. Decisione consapevole: lo screen reader annuncia il group via `aria-label`, l'utente sighted vede la stessa UI di slice 4. La regression a "filter row identica a slice 4 vista" è preservata.
- **R5-5 — `Duration.values/0` whitelist duplicate vs `Ecto.Enum` schema**: il modulo `Duration` e lo schema `Idea` dichiarano la whitelist due volte. Pinato da test che asserisce equality (`Duration.values() == Idea.duration_values_or_equivalent`). Drift catturato da test failure se uno cambia senza l'altro.
- **R5-6 — `@selected_duration` come atom singolo (AA5 post-iter-2)**: scelta motivata dal pattern slice-3/4 (assigns separato dal form). Trade-off: due source di verità (form changeset + assigns) ma sincronizzate da `assign_form/1` deterministico. Trigger per refactor: divergenza tra form params e `@selected_duration` (impossibile by construction nello slice 5 perché `@selected_duration` è single source per il render del chip pressed).
- **R5-7 — NULL exclusion divergente da CONTEXT.md riga 81 prima del fix step 9**: tra step 5 e step 9, `Ideas.list_ideas` exclude NULL ma `CONTEXT.md` ancora dice "l'idea resta visibile". Drift documentazione transitorio. Mitigato: D2 step 9 pre-PR gate; il PR finale è coerente.
- **R5-8 — gettext deferral confermato (slice 4 R6)**: slice 5 aggiunge ~12 stringhe canoniche IT. Trigger residuo per gettext: aggiunta utente non-IT. Non scattato.
- **R5-9 — Roving tabindex su mobile touch**: pattern WAI-ARIA roving tabindex è keyboard-centric; su mobile tap non c'è arrow-key navigation. Mitigation: il rover server-rendered (`tabindex="0"` sul primo) non interferisce con tap (touch events non leggono tabindex). Pinato da V1 mobile screenshot test.
- **R5-10 — Migration #5 SQLite ALTER TABLE limitations**: SQLite `ALTER TABLE ADD COLUMN` non supporta DEFAULT con expression; `add :duration, :string, null: true` (no default) è safe. Pinato da `migrations_test` roundtrip.
- **R5-11 — Step 1 hook JS integration con `phx-hook`**: il hook è scritto in JS; LV tests non lo eseguono. Risk: il hook ha un bug ma i test ExUnit passano. Mitigation: V1b manual + il fatto che il pattern WAI-ARIA roving è ben documentato e il hook è ~30 righe.
- **R5-12 — Live-region action prefix usa label IT (AA9)**: se in futuro cambiamo `Duration.label/1` (es. typo fix), il live-region cambia. Mitigation: `docs/conventions.md` table è la source of truth; `docs_test.exs` valida.
- **R5-13 — Live-region announce non riflette il count dei filtri attivi**: il suffix di AA20 dice "filtri categoria attivi" ma non quanti né quali. Trade-off accettato per ridurre verbosità (alternativa: `, filtri categoria attivi: mare obbligatoria, sport opzionale` diventa lungo). Trigger per estensione: SR user lamenta che dopo un cycle non ricorda quali filtri sono attivi. Mitigation a portata di mano: aggiungere uno screen-reader-only `<div aria-live="off">` con il riassunto completo, narrato solo on-demand.
- **R5-14 — Slice-6 spec deve rivalutare la decisione NULL-exclusion**: AA7 è esplicito su "filtri futuri da rivalutare". Slice 6 (budget): un'idea senza `estimated_cost` rappresenta uno scenario molto più frequente di un'idea senza `duration`, e l'esclusione potrebbe nascondere la maggioranza delle idee precoci. Trigger pre-spec slice 6: rivalutare se NULL-pass (ritorna a CONTEXT.md riga 81) o NULL-exclude (estensione di AA7).
- **R5-15 — RovingTabindex hook su LV reconnect**: lo hook re-monta dopo reconnect; il client perde lo state "current focus index". Server re-emette `tabindex="0"` sul primo chip — il focus si riposiziona sul primo chip, l'utente potrebbe avere disorientamento se stava ciclando il chip 5/8. Mitigation accettata: V1b conferma il comportamento; LV reconnect è un evento raro (network blip). Trigger per fix: SR user lamenta lost-focus durante uso prolungato.
- **R5-16 — Whitelist single-source via `Ecto.Enum, values: Duration.values()`**: chiude W2 design ma introduce dipendenza compile-time da `Ideajar.Ideas.Duration` da parte di `Ideajar.Ideas.Idea`. Ordine di compilazione: `Duration` deve compilare prima di `Idea`. In Elixir/Mix questo è gestito automaticamente (compiler dependency graph). Pin esplicito in step 2 RED che il modulo compila e i test passano dal cold cache.

## Plan Review Summary

> Verdetti iter 1: acceptance/design/UX **needs-revision** (8 blocker + warning), strategic **approve** (warning only).
> Verdetti iter 2 post-fix: tutti e 4 **approve**. Convergenza raggiunta.

### Modifiche di iter 2 rispetto a iter 1

**Acceptance fixes (4 blocker chiusi):**
- **B1** — AA5 ribaltato: `@selected_duration :: atom | nil` come assigns separato (parallelo a `@selected_category_ids` di slice 3 e `@filter_state` di slice 4). Plan rispetta lo spec, no innovation che diverge dalla convenzione consolidata. Step 3 RED b.1-b.11 asserts contro `view.assigns.selected_duration`.
- **B2** — Hostile-input enumerated cases uniformati a una singola lista canonica di 8 input (5 stringhe + 3 non-string). Stessa lista riusata in step 3 RED #8 (form) e step 6 RED #16 (filter). Copre S2 al 100% (incluso `%{}` map).
- **B3** — Step 2 RED #5 testa esplicitamente data preservation across rollback (insert pre-rollback, down, verify rows preserved + only column dropped, up, verify duration NULL).
- **B4** — F16 row aggiunta alla traceability table.

**Design fixes (2 blocker chiusi):**
- **B1 (= acceptance B1)**: stesso fix.
- **B2** — AA22 pin concreto del changeset error override: `override_duration_error/1` helper privato con module attribute `@duration_invalid "Durata non valida"`, pattern match scoped a `:duration` only, code snippet inline in step 2 GREEN.
- **W2 (whitelist single-source)**: `Ecto.Enum, values: Duration.values()` chiude R5-5; R5-16 pin compile-order dependency.
- **W4 (LV reconnect)**: R5-15 documenta il focus-jump trade-off con escalation trigger.

**UX fixes (2 blocker + 1 warning chiusi):**
- **B1 (NULL exclusion undiscoverable)** — AA19 + A12 introducono helper text statico `Le idee senza durata sono nascoste quando un filtro è attivo.` sempre visibile sotto il sub-label durata, sopra il chip group. Sighted ed SR users avvertiti prima di toccare il filtro.
- **B2 (live-region compound state silente)** — AA20 + A13 introducono compound suffix `, filtri categoria attivi` / `, filtri durata attivi` quando l'altro gruppo ha ≥1 filtro on. `Filtri rimossi` non ha mai suffix (entrambi gruppi vuoti). Helper privato `compound_suffix/2` (puro, due assigns input). Nuovo Gherkin scenario nello spec.
- **W3 (sub-label `Durata` collision)** — AA21: aria-label sub-block `Filtra per categoria` / `Filtra per durata` (disambiguato per SR), sub-label visivo resta `Categorie` / `Durata` (visual economy). No collision con `<legend>Durata</legend>` del form fieldset.

**Strategic — approve già a iter 1**: nessuna modifica iter 2 sul fronte strategico. Carry-over warning tracciate (W1 NULL exclusion precedent per slice 6/7 → R5-14; W2 apply_filters/2 module extraction trigger → R5-1; W3 hook test fragility → R5-3 esistente; tutti documentati).

### Warning iter 2 ancora aperti (tracciati per `/build`)

- **Acceptance W**: nessuna warning blocker-level. Cosmetic F5/F12 wording fixed inline.
- **Design W**: R5-5 + R5-16 ridondanti (entrambe guardano la whitelist drift); accettato per belt-and-suspenders.
- **UX W**: form chip toggle-off discoverability — `aria-pressed` è la disclosure mechanism per WAI-ARIA APG button pattern. Trigger per fix: user testing reveals confusion.
- **Strategic W**: 9-step plan size; R5-1 module extraction trigger pre-slice-6; R5-13 live-region count-of-filters non incluso (trade-off verbosity).

### Net assessment

Plan è **implementation-ready** per `/build`. 8 blocker chiusi a livello plan in iter 2; tutti i 4 reviewer convergono su approve. Le decisioni più strutturanti (AA5 separate-assign, AA20 compound suffix, AA22 changeset override snippet) sono pinned con codice esplicito o con esempi worked. Le warning superstiti sono refinement implementation-time o trade-off accettati con escalation trigger documentato.
