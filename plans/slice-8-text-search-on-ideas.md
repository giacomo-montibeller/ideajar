# Plan: Slice 8 — Text search filter on ideas

**Created**: 2026-05-02
**Branch**: main (trunk-based)
**Status**: approved
**Spec**: `docs/specs/text-search-on-ideas.md`

## Build conventions (carried from slice 1-7b)

- **Strict TDD** — RED → GREEN → REFACTOR per step.
- Ogni commit attraverso la skill `commit-message`. In `/build` uso option 1 default.
- Pre-step gate: `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo`, `mix deps.audit`, `mix test --include migration`.
- Domain in `Ideajar.*`, delivery in `IdeajarWeb.*`.
- UI copy IT canonica appesa a `docs/conventions.md` nello step 5.
- Trunk-based su `main`, ogni step lascia il codebase committable.

## Goal

Slice 8 chiude il set di filtri promesso da CONTEXT.md introducendo la **ricerca testuale**. User digita una query in un input nel filter row (5° sub-block, dopo Distanza). Per query ≥ 3 chars il filtro è attivo: la lista mostra solo idee il cui `title` OR `description` contiene la stringa (case-insensitive). Sotto i 3 chars il filtro è inattivo (NULL-pass implicit, parallel slice 7a/7b min-length pattern). Algoritmo SQLite `LIKE %q%` con escape di wildcards. NO FTS5 (overkill per la scala).

**Eccezione documentata al pattern NULL-exclude**: idee con `description = nil` ma `title` matchante PASSA. Razionale: text filter è "trova le idee che contengono X"; description NULL non contribuisce al match ma non penalizza l'idea (a differenza di durata/budget/distanza). Documentato in `CONTEXT.md`.

Foundation: schema slice 7a (`title`, `description`) + slice 7b form-wrapping pattern. Nessuna nuova migration.

Fuori scope: ricerca fuzzy, ranking, highlight matched terms, search history, URL params, search across `location_name`, FTS5 virtual table, analytics.

## Decisioni architetturali pre-build

- **DD-S8-1 — `Filter.apply_text_search/2` query-layer (NOT post-query)**: `LIKE` è SQL-friendly, vive nel query path con le altre 4 clausole (required/optional/durations/max_cost). Rule-of-3 trigger per estrazione `Filter.QueryClauses` modulo: 6+ clausole query-path. Slice 8 porta il count a 5; OK lasciare nel modulo `Filter` finora.

- **DD-S8-2 — `apply_text_search/2` clause shape**:
  ```elixir
  defp apply_text_search(query, nil), do: query
  defp apply_text_search(query, q) when is_binary(q) and byte_size(q) < 3, do: query
  defp apply_text_search(query, q) when is_binary(q) do
    pattern = "%" <> escape_like(q) <> "%"
    from i in query,
      where:
        fragment("LOWER(?) LIKE LOWER(?) ESCAPE '\\'", i.title, ^pattern) or
          fragment(
            "? IS NOT NULL AND LOWER(?) LIKE LOWER(?) ESCAPE '\\'",
            i.description,
            i.description,
            ^pattern
          )
  end
  defp apply_text_search(query, _), do: query  # hostile non-binary → no-op
  ```
  Note Elixir → SQL byte mapping (Acceptance Critic B1 + Design Critic B1 fix):
  - Elixir source `"\\"` = stringa runtime `\` (1 byte). 
  - Per emettere SQL `ESCAPE '\'` (esattamente 1 byte `\` come escape character — requisito SQLite), il fragment template Elixir deve essere `"ESCAPE '\\'"` (Elixir source 4 chars: `'`, `\`, `\`, `'`).
  - **NON** usare `"ESCAPE '\\\\'"` (Elixir source 6 chars), che produrrebbe SQL `ESCAPE '\\'` (2 byte) e SQLite raise `ESCAPE expression must be a single character`.
  - Pin con `Repo.to_sql/2` nei test step 1 (RED #4 + #11): assert SQL contiene il literal byte sequence `ESCAPE '\'` (cioè `~r/ESCAPE\s+'\\'/` in regex Elixir, tenendo conto che il regex source `\\` matcha 1 byte `\`).

- **DD-S8-3 — `escape_like/1` helper**: escapa `\`, `%`, `_` letterali (in quest'ordine — `\` deve essere primo per non doppio-escape):
  ```elixir
  defp escape_like(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
  ```

- **DD-S8-4 — NULL-description guard**: `description IS NOT NULL AND LOWER(description) LIKE ...` è esplicito per evitare 3-valued logic ambiguity nel WHERE. Title NOT NULL nel schema → no NULL-guard sul title clause.

- **DD-S8-5 — Min query length 3 chars enforced server-side**: `apply_text_search/2` no-op su `byte_size(q) < 3`. Server è authoritative; client può aggiungere UX hint, ma server pin garantisce contratto.

- **DD-S8-6 — Multi-shape extractor uniform (parallel slice 7b filter search bug-fix)**: handler `update_text_search` accetta sia `%{"q" => v}` (test sintetico) sia `%{"filter" => %{"text_search" => v}}` (real browser form-shape). Senza form-shape support, typing in browser non fira la ricerca.

- **DD-S8-7 — `filter_active?` socket-based refactor (Design Critic suggestion slice 7b carry-over)**: cambia signature da `/5` (filter_state, duration_filter, cost_filter, max_distance_index, user_lat) a `/1` (socket_or_assigns). Body pattern-match estrae i campi. Razionale: arity creep — slice 7b ha già forzato la decisione (3 → 5), slice 8 forzerebbe a /6. Refactor a /1 ora chiude il ciclo per le slice future. Test arity-pin aggiornato.

- **DD-S8-8 — `derive_filter_opts/1` socket-based già fatto in slice 7b step 8**: solo extension del body per aggiungere `:text_search`. No arity change.

- **DD-S8-9 — `@text_search_query` LV-session only (parallel slice 7b DD11)**: no localStorage, no DB. Refresh = "" (LV remount). Save success NON resetta (filter survives submit).

- **DD-S8-10 — `@text_search_query` reset matrix**:
  - `update_text_search` con valid binary → assign al typed text
  - `remove_text_search` → ""
  - `clear_filters` (Mostra tutte) → "" (cascade)
  - Refresh → "" (LV remount)
  - Save success → NO reset
  - `select_user_location` / `set_user_location` → NO reset (orthogonal slice 7b)

- **DD-S8-11 — Form wrapper mandatorio (lezione slice 7b step 8 fix)**: `phx-change` su input bare non fira nel browser. Il `<form id="filter-text-search-form" phx-change="update_text_search">` è il container che propaga il change event. Non un `<.form>` Phoenix.Component (no Form struct, no changeset).

- **DD-S8-12 — Oversize input guard (S2)**: server-side `byte_size(q) > 200` → no-op. HTML `maxlength="200"` è UX hint, può essere bypassato via devtools. Server pin.

- **DD-S8-13 — Empty state composition**: `filter_active?/1` deve includere `@text_search_query != ""` perché il 3-way empty state (workspace empty / filter empty / non-empty) si rompe altrimenti. Slice 5 invariant.

- **DD-S8-14 — XSS regression via HEEx auto-escape**: la query è renderizzata SOLO come `value` attribute dell'input. HEEx auto-escape su attribute. Test pin con query maliziosa.

- **DD-S8-15 — 5° sub-block layout dopo Distanza**: source order Categorie → Durata → Budget → Distanza → Testo. NO RovingTabindex (singolo input, focus naturale via Tab).

- **DD-S8-16 — Out-of-scope guard regex update**: slice 7b ha già scoped `Cerca punto di partenza`. Slice 8 introduce `Cerca idee`. Guard regex aggiornata per consentire entrambe come legitimate strings; nessun altro `Cerca*` deve passare.

## Acceptance Criteria

> Mappatura uno-a-uno con `docs/specs/text-search-on-ideas.md`.

### Functional / behavioral

- [ ] **F1** — Tutti gli scenari Gherkin automatabili passano.
- [ ] **F2** — Mount: `@text_search_query == ""`. Sub-block render. Bottone reset hidden.
- [ ] **F3** — `update_text_search` con `%{"q" => "ma"}` (< 3 chars) → SQL no LIKE.
- [ ] **F4** — `update_text_search` con `%{"q" => "mar"}` (≥ 3 chars) → SQL LIKE su title + description.
- [ ] **F5** — `update_text_search` con form-shape `%{"filter" => %{"text_search" => "mar"}}` → comportamento identico (real-browser pin).
- [ ] **F6** — Match case-insensitive su title.
- [ ] **F7** — Match case-insensitive su description.
- [ ] **F8** — Idea con `description = nil` ma title matchante → IN risultato.
- [ ] **F9** — Idea con `description = nil` e title non matchante → OUT risultato.
- [ ] **F10** — `remove_text_search` → `@text_search_query = ""`. Bottone reset hidden.
- [ ] **F11** — `clear_filters` (Mostra tutte) → reset 6 filter types incluso text.
- [ ] **F12** — Refresh resetta `@text_search_query` (LV remount).
- [ ] **F13** — Save success NON resetta `@text_search_query`.
- [ ] **F14** — Filter combined AND con altri 4.
- [ ] **F15** — phx-debounce 300 ms (regression pin via attribute presence).
- [ ] **F16** — LIKE wildcards (`%`, `_`) in query → escaped a literal characters.

### Domain layer

- [ ] **DM1** — `Filter.apply_text_search/2` con `nil` → no-op.
- [ ] **DM2** — `Filter.apply_text_search/2` con < 3 chars → no-op.
- [ ] **DM3** — `Filter.apply_text_search/2` con ≥ 3 chars → SQL contiene literal byte sequence `ESCAPE '\'` (1 byte escape char) sia sul title che sul description clause. Pinato via `Repo.to_sql/2` con regex `~r/LOWER\(.*?\) LIKE LOWER\(.*?\) ESCAPE '\\'/` (regex source `\\` matcha 1 byte `\`). Verifica anche `description IS NOT NULL AND` clause presente.
- [ ] **DM4** — `Filter.apply_text_search/2` non-binary → no-op (defensive).
- [ ] **DM5** — `Ideas.list_ideas([])` invariato (regression).
- [ ] **DM6** — `Ideas.list_ideas([text_search: "mar"])` → solo matchanti.
- [ ] **DM7** — `Ideas.list_ideas` 6-way combined AND.
- [ ] **DM8** — `escape_like/1` escapa `\`, `%`, `_` (3 cases).

### Accessibility

- [ ] **A1** — Sub-block ha `role="group" aria-label="Filtra per testo"`.
- [ ] **A2** — Input ha `placeholder="Cerca idee"`, `autocomplete="off"`, `maxlength="200"`.
- [ ] **A3** — Helper text NULL-exception visibile.
- [ ] **A4** — Filter row sub-block order: Categorie → Durata → Budget → Distanza → Testo.
- [ ] **A5** — Form wrapper `<form id="filter-text-search-form">` per phx-change browser firing.
- [ ] **A6** — Bottone `Rimuovi filtro testo` hit area ≥ 44×44.

### Security / robustness

- [ ] **S1** — `update_text_search` con non-binary → no-op (uniform list 5 inputs).
- [ ] **S2** — `update_text_search` con oversize > 200 chars → no-op (server-side guard).
- [ ] **S3** — `update_text_search` con malformed payload → no-op.
- [ ] **S4** — SQL injection attempt → trattato come literal substring (Ecto parametrization).
- [ ] **S5** — XSS: query maliziosa `<script>` → HEEx auto-escape sul value attribute.
- [ ] **S6** — LIKE wildcards in input non bypassano semantica literal (escape).

### Operational / data

- [ ] **O1** — Nessuna migration.
- [ ] **O2** — `Filter.apply_text_search/2` testato indipendentemente (8+ tests: nil/<3/≥3/case/NULL desc/escape `%`/escape `_`/escape `\`/non-binary).
- [ ] **O3** — Performance: list_ideas 5 filter attivi + 100 idee fixture < 100 ms.
- [ ] **O4** — SQL emission pin per text_search active.

### Validation venue

- [ ] **V1** — Screenshot mobile: sub-block testo vuoto, attivo, empty-filter state.
- [ ] **V1a** — Lighthouse a11y mediana ≥ 95.
- [ ] **V1b** — Keyboard-only walkthrough.
- [ ] **V2** — Manual test live: typing rapido, debounce.

### Documentation

- [ ] **D1** — `docs/conventions.md` UI copy table slice 8 (~5 strings).
- [ ] **D2** — `CONTEXT.md` `## Decisione su filtri non applicabili` esteso per text-search exception.
- [ ] **D3** — `CONTEXT.md` filtri Ricerca testuale marcata implemented (slice 8).
- [ ] **D4** — `test/ideajar/docs_test.exs`: nuova `describe "slice-8 UI copy"`.
- [ ] **D5** — Out-of-scope guard regex update: rimuove `Cerca` standalone, consente `Cerca punto di partenza` + `Cerca idee`.

### UI copy aggiunta (canonical)

| Elemento | Testo IT |
|---|---|
| Sub-label visibile filtro Testo | `Testo` |
| Aria-label sub-block (SR) | `Filtra per testo` |
| Helper text NULL-exception | `La ricerca trova le idee con la parola in titolo o descrizione.` |
| Placeholder text input | `Cerca idee` |
| Bottone rimuovi filtro testo | `Rimuovi filtro testo` |

## User-Facing Behavior

> BDD scenarios copiati verbatim da `docs/specs/text-search-on-ideas.md` (vedi sezione "User-Facing Behavior").

## Steps

### Step 1: `Filter.apply_text_search/2` query-layer clause + `escape_like/1` helper

**Complexity**: standard
**Rationale**: pure SQL query path, foundation per step 2. Test isolati con `to_sql/2` per pin l'emission.

**RED** (`test/ideajar/ideas/filter_test.exs` extend con nuovo describe `apply/2 — :text_search clause (slice 8)`):
1. `Filter.apply(query, text_search: nil)` → SQL invariato (no LIKE).
2. `Filter.apply(query, text_search: "")` → no-op (< 3 chars).
3. `Filter.apply(query, text_search: "ma")` → no-op (< 3 chars).
4. `Filter.apply(query, text_search: "mar")` → SQL pinato via `Repo.to_sql/2`: contiene literal byte sequence `LOWER(...) LIKE LOWER(...) ESCAPE '\'` (escape è 1 byte `\`, NOT 2-byte `\\`). Sia title che description clause emessi. Test regex: `~r/LOWER\(.*?\) LIKE LOWER\(.*?\) ESCAPE '\\'/` — il regex source `\\` matcha 1 byte `\` runtime.
5. `Filter.apply(query, text_search: 123)` → no-op (non-binary, defensive).
6. **Integration query test (DM6)**: seed 4 idee (mix title/description con/senza "mare"), `Filter.apply` + `Repo.all` → solo matching ideas. Case-insensitive (lowercase query, mixed-case data).
7. **NULL description (DM/F8)**: idea con `description: nil` + title containing "picnic" → matched quando `text_search: "picnic"`.
8. **LIKE wildcard escape `%` integration** (Acceptance B4 fix): query `"%"` con seed di idea con title `mare%bagno` (literal `%`) e idea con title `mare` → solo `mare%bagno` matched (il `%` in input è literal, non wildcard).
9. **LIKE wildcard escape `_` integration**: query `"a_b"` con seed idea title `a_b` (literal underscore) e idea title `axb` → solo `a_b` matched.
10. **LIKE wildcard escape `\` integration** (Acceptance B4 fix): query `"\\foo"` (Elixir source, 5 chars runtime: `\`, `f`, `o`, `o`) con seed idea title `\foo` (literal backslash) e idea title `foo` → solo `\foo` matched. Conferma che `\` in input è literal, non escape character SQL.
11. **Description-only match scenario** (Acceptance B2 fix): seed 2 idee — A) title `Concerto rock`, description `Stadio Olimpico, energia pura`; B) title `Sirolo`, description `Mare bellissimo`. Query `"stadio"` → result contiene SOLO A (title NOT matched, description matched). Pin che il filtro ritorna idee anche quando il title clause è false ma description clause è true.
12. **`escape_like/1` direct unit test** (8 cases minimi): empty `""`, no-special `"abc"`, single `%`, single `_`, single `\`, multi-special `"\\%_"`, mixed-case con special `"FoO%bar"`, real-world `"Cerco \"casa di nonna\" 50%"`.

**GREEN**:
- Aggiungi `apply_text_search/2` a `lib/ideajar/ideas/filter.ex` come ultimo step della `apply/2` chain.
- Aggiungi `escape_like/1` privato.
- Update moduledoc per documentare la 5° clausola query-path.

**REFACTOR**: docstring su `apply_text_search/2` documenta DD-S8-2 (NULL-description guard razionale) e DD-S8-3 (escape order).

**Files**: `lib/ideajar/ideas/filter.ex` (extend), `test/ideajar/ideas/filter_test.exs` (extend).
**Spec mapping**: DM1, DM2, DM3, DM4, DM8, F16, S6, O2, DD-S8-1, DD-S8-2, DD-S8-3, DD-S8-4, DD-S8-5.

### Step 2: `Ideas.list_ideas/1` extension con `:text_search`

**Complexity**: standard
**Rationale**: pipeline glue. Aggiunge il nuovo opt al `Filter.apply/2` chain.

**RED** (`test/ideajar/ideas_test.exs` extend con nuovo describe `list_ideas/1 with :text_search opt (slice 8 step 2)`):
1. `list_ideas([])` invariato (regression DM5).
2. `list_ideas(text_search: nil)` invariato.
3. `list_ideas(text_search: "ma")` (< 3 chars) → tutte le idee.
4. `list_ideas(text_search: "mar")` con seed 4 idee (Sirolo desc "mare", Uffizi, Picnic NULL desc, MARE in tempesta) → solo Sirolo + MARE in tempesta.
5. **NULL-description (F8)**: idea con `description: nil`, title `Picnic improvviso` → seed + `text_search: "picnic"` → matched.
6. **6-way combined AND (DM7)**: required + durations + max_cost + max_distance_km + ref_lat/lng + text_search → AND su tutte le clausole.
7. **SQL emission pin (O4)**: `build_query(text_search: "mar")` SQL contiene LIKE clauses; `build_query(text_search: nil)` SQL non contiene LIKE.
8. **Order preservato**: inserted_at DESC, id DESC dopo text_search filter.

**GREEN**:
- Update `lib/ideajar/ideas.ex` `list_ideas/1` doc per documentare `:text_search`.
- `Filter.apply/2` already chains everything via Keyword.get; no list_ideas/1 code change beyond doc.

**REFACTOR**: extend moduledoc.

**Files**: `lib/ideajar/ideas.ex` (extend doc), `test/ideajar/ideas_test.exs` (extend).
**Spec mapping**: DM5, DM6, DM7, F8, F9, F14, O4, DD-S8-1.

### Step 3: LV handlers `update_text_search` + `remove_text_search` + `@text_search_query` assign + `clear_filters` extension

**Complexity**: standard
**Rationale**: server-side state. Multi-shape extractor (DD-S8-6), defensive parse, hostile uniform list. **Acceptance Critic B3 fix**: `clear_filters` extension cascade per text-search assign è handler logic e va in step 3 (con RED che la pinna), NON in step 4 (template).

**RED** (`test/ideajar_web/live/idea_live/index_test.exs` new describe `text search filter handlers (slice 8 step 3)`):
1. Mount: `@text_search_query == ""`.
2. `update_text_search` con `%{"q" => "mar"}` → `@text_search_query == "mar"`. Reload triggered.
3. `update_text_search` con form-shape `%{"filter" => %{"text_search" => "mar"}}` → stesso (DD-S8-6).
4. `update_text_search` con `%{"q" => ""}` → `@text_search_query == ""`. (User cleared the input.)
5. `update_text_search` con `%{"q" => "ma"}` (< 3 chars) → assign aggiornato (typed text tracked) ma SQL no LIKE.
6. `remove_text_search` → `@text_search_query == ""`.
7. **Hostile uniform list (S1, S2, S3)**: 5 inputs:
   - `%{"q" => 123}` (non-binary)
   - `%{"q" => :atom}`
   - `%{"q" => String.duplicate("a", 201)}` (oversize > 200)
   - `%{}` (missing keys)
   - `%{"filter" => %{}}` (form-shape missing field)
   → tutti no-op (assign invariato a "").
8. **F13 save success NON resetta**: pre-state `@text_search_query = "mar"` + open form + valid submit → after save: `@text_search_query == "mar"`.
9. **F11 clear_filters extension** (Acceptance B3 fix): pre-state `@text_search_query = "mar"` + altri 4 filter attivi (categoria + durata + budget + distanza/ref). Click `Mostra tutte` → tutti 6 axes reset. Pin `@text_search_query == ""` post-clear.

**GREEN** (`lib/ideajar_web/live/idea_live/index.ex`):
- Mount: `assign(:text_search_query, "")`.
- New handler `update_text_search` con multi-shape extractor:
  ```elixir
  def handle_event("update_text_search", params, socket) do
    case extract_text_search_query(params) do
      {:ok, q} -> {:noreply, socket |> assign(:text_search_query, q) |> reload_ideas()}
      :error -> {:noreply, socket}
    end
  end
  
  defp extract_text_search_query(%{"filter" => %{"text_search" => q}}) when is_binary(q) and byte_size(q) <= 200, do: {:ok, q}
  defp extract_text_search_query(%{"q" => q}) when is_binary(q) and byte_size(q) <= 200, do: {:ok, q}
  defp extract_text_search_query(_), do: :error
  ```
- New handler `remove_text_search`:
  ```elixir
  def handle_event("remove_text_search", _params, socket) do
    {:noreply, socket |> assign(:text_search_query, "") |> reload_ideas()}
  end
  ```
- Extend `clear_filters` handler (Acceptance B3 fix): aggiungi `|> assign(:text_search_query, "")` cascade alle 5 reset esistenti (filter_state, duration_filter, cost_filter, user_*, max_distance_index).

**REFACTOR**: docstring su `extract_text_search_query/1` (DD-S8-6 multi-shape).

**Files**: `lib/ideajar_web/live/idea_live/index.ex` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: F2, F5, F10, F11, F12, F13, S1, S2, S3, DD-S8-6, DD-S8-9, DD-S8-10, DD-S8-12.

### Step 4: REFACTOR — `filter_active?/5 → /1` socket-based (no behavior change)

**Complexity**: standard (refactor invariante)
**Rationale**: Design Critic B2 fix — split del refactor in step dedicato. Slice 7b ha forzato la decisione (3→5), slice 8 chiude il ciclo refactorando a /1 socket-based PRIMA di aggiungere il 6° axis. Step behavior-preserving: zero feature change. RED tests pinnano l'invariante.

**RED**:
1. **Arity-pin**: `function_exported?(IdeajarWeb.IdeaLive.Index, :filter_active?, 1)` true. `function_exported?(..., :filter_active?, 5)` false.
2. **Behavior-preservation invariante**: per ognuna delle combinazioni esistenti (categoria-only, durata-only, budget-only, distanza-only, ref-only, combined), il return value di `filter_active?` deve essere identico pre e post-refactor. Testato via mount + state setup + render verifica che `Mostra tutte` button rendering è invariato.
3. **5 callsites template**: i 5 callsites di `filter_active?` nel template renderizzano correttamente post-refactor con la nuova signature.
4. **NO text_search axis ancora**: `filter_active?(socket.assigns)` con `text_search_query = "mar"` e tutti gli altri filter inattivi → ritorna `false` (step 5 lo cambia in `true`, ma step 4 è puro refactor).

**GREEN**:
- `lib/ideajar_web/live/idea_live/index.ex`:
  ```elixir
  @doc """
  Slice 8 step 4 (DD-S8-7) — collapsed filter_active?/5 to /1 taking the
  socket assigns directly. Reading every assign at the call site keeps the
  signature stable as more filter axes are added. Behavior-preserving
  refactor; the text_search axis is added to the body in step 5.
  """
  def filter_active?(%{filter_state: fs, duration_filter: df, cost_filter: cf,
                       max_distance_index: mdi, user_lat: ul}) do
    fs != %{} or MapSet.size(df) > 0 or not is_nil(cf) or
      mdi > 0 or not is_nil(ul)
  end
  ```
- Aggiorna i 5 callsites del template per passare `@socket.assigns` (o `assigns`), es. `filter_active?(assigns)`.

**REFACTOR**: nessuno (è già un refactor).

**Files**: `lib/ideajar_web/live/idea_live/index.ex` (refactor), `lib/ideajar_web/live/idea_live/index.html.heex` (5 callsites update), `test/ideajar_web/live/idea_live/index_test.exs` (arity-pin + invariante tests).
**Spec mapping**: DD-S8-7, R8-2.

### Step 5: HEEx text-search sub-block + `filter_active?/1` text extension + `derive_filter_opts/1` extension

**Complexity**: complex
**Rationale**: cross-cutting (template + filter_active? body extension per text + empty state composition). Costruisce sopra la foundation di step 4 (refactor) e step 3 (handler + clear_filters). NESSUN cambio di arity in questo step.

**RED** (`test/ideajar_web/live/idea_live/index_test.exs` new describe `text search sub-block (slice 8 step 4)`):
1. Mount: render contains sub-block `<div role="group" aria-label="Filtra per testo">` dopo Distanza. (A4 source order pin.)
2. Sub-block contains: text input `id="filter-text-search-input"`, placeholder `Cerca idee`, autocomplete="off", maxlength="200", phx-debounce="300", form wrapper `id="filter-text-search-form"` con `phx-change="update_text_search"`.
3. **A1**: sub-block ha `role="group" aria-label="Filtra per testo"`.
4. **A3**: helper text `La ricerca trova le idee con la parola in titolo o descrizione.` visibile sempre.
5. **A4 (F19 source order)**: Categorie → Durata → Budget → Distanza → Testo nel DOM source order.
6. **F4 integration**: seed ideas + `update_text_search "mar"` → render mostra solo matchanti.
7. **F5 form-shape (real-browser regression pin)**: `view |> form("#filter-text-search-form", filter: %{text_search: "mar"}) |> render_change()` → `@text_search_query == "mar"`, render filtra.
8. **F6 case-insensitive integration**: seed con title "MARE in tempesta", query "mare" → matched.
9. **F8 NULL-description integration**: seed idea con title "Picnic improvviso" + description nil, query "picnic" → matched.
10. **F2/F10**: bottone `Rimuovi filtro testo` hidden quando `@text_search_query == ""`. Visible quando != "".
11. **A6 hit area**: bottone reset ha `min-h-11 min-w-11`.
12. **DD-S8-13 empty state composition**: workspace non-empty + `text_search_query = "qqxz"` (no match) → `Nessuna idea per i filtri attivi.` visible + `Mostra tutte` rendered. **Pin di unit isolation (Acceptance W4)**: `filter_active?(socket.assigns)` con SOLO `text_search_query = "mar"` settato e tutti gli altri filter inattivi → ritorna `true`.
13. **F15 phx-debounce 300**: input ha `phx-debounce="300"`.
14. **XSS regression (S5)**: `update_text_search` con query `<script>alert(1)</script>` → render input value HTML-escaped, no `<script>` element nel DOM.

> NB: arity-pin di `filter_active?/1` + clear_filters extension sono coperti rispettivamente da step 4 (refactor) e step 3 (handler). Step 5 è puro render + filter_active? body extension per text + derive_filter_opts extension.

**GREEN**:
- `lib/ideajar_web/live/idea_live/index.ex`:
  - Estendi `filter_active?/1` body per includere `text_search_query != ""` clause (NON un cambio di arity, solo aggiungere una OR-clause).
  - Extend `derive_filter_opts/1` body con `:text_search` opt (DD-S8-8).
- `lib/ideajar_web/live/idea_live/index.html.heex`:
  - Aggiungi 5° sub-block `Testo` dopo Distanza:
  ```heex
  <p class="text-xs">Testo</p>
  <p class="text-xs text-base-content/70">
    La ricerca trova le idee con la parola in titolo o descrizione.
  </p>
  <div role="group" aria-label="Filtra per testo" class="space-y-2">
    <form id="filter-text-search-form" phx-change="update_text_search">
      <input
        type="text"
        id="filter-text-search-input"
        name="filter[text_search]"
        value={@text_search_query}
        placeholder="Cerca idee"
        phx-debounce="300"
        maxlength="200"
        autocomplete="off"
        class="input w-full"
      />
    </form>
    <button
      :if={@text_search_query != ""}
      type="button"
      phx-click="remove_text_search"
      class="btn btn-ghost btn-sm min-h-11 min-w-11"
    >
      Rimuovi filtro testo
    </button>
  </div>
  ```
  - I 5 callsites di `filter_active?(...)` sono già stati aggiornati nello step 4 (refactor); nessuna modifica al callsite in step 5.

**REFACTOR**: extract helper `text_search_active?/1` se necessario; ma probabile sia inline.

**Files**: `lib/ideajar_web/live/idea_live/index.ex` (extend), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: F1, F2, F4, F5, F6, F8, F14, F15, A1, A3, A4, A5, A6, S5, DD-S8-8, DD-S8-11, DD-S8-13, DD-S8-14, DD-S8-15.

### Step 6: Out-of-scope guard update + docs sync (D1-D5) + plan flip

**Complexity**: standard

**RED**:
1. **D1**: new `describe "docs/conventions.md — slice 8 UI copy"` con 5 stringhe.
2. **D2**: `describe "CONTEXT.md — slice 8 text search exception"` asserisce che `## Decisione su filtri non applicabili` documenta esplicitamente l'eccezione text-search.
3. **D3**: `describe "CONTEXT.md — slice 8 testuale implemented"` asserisce che riga 84 (Ricerca testuale) marcata come implemented (slice 8).
4. **D5 out-of-scope guard regression**: `Cerca punto di partenza` (slice 7b) + `Cerca idee` (slice 8) entrambe presenti nel render. Refute altre stringhe `Cerca*`.

**GREEN**:
- `docs/conventions.md`: append `Stringhe aggiunte in slice 8 (text search on ideas)` table.
- `CONTEXT.md`:
  - Update `## Decisione su filtri non applicabili`: aggiungi paragraph esplicativo per l'eccezione text-search (vedi DD-S8-4 + spec D2 razionale).
  - Update riga 84 filtri Ricerca testuale con marker (slice 8 implementato).
- `test/ideajar/docs_test.exs`: nuove describe.
- `test/ideajar_web/live/idea_live/index_test.exs`: aggiorna out-of-scope guard regex (rimuove `Cerca` standalone — slice 8 implementa — consente `Cerca punto di partenza` + `Cerca idee`).
- Plan flip: `**Status**: approved` → `**Status**: implemented`.

**Files**: `docs/conventions.md` (extend), `CONTEXT.md` (update), `test/ideajar/docs_test.exs` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (update guard), `plans/slice-8-text-search-on-ideas.md` (status flip).
**Spec mapping**: D1, D2, D3, D4, D5.

## Complexity Classification

| Step | Complessità | Motivazione |
|------|-------------|-------------|
| 1 | standard | Pure SQL clause + escape helper + 12 boundary tests (incluso `\`/`%`/`_` integration + description-only match) |
| 2 | standard | Pipeline glue + regression |
| 3 | standard | Handler + multi-shape extractor + hostile uniform + clear_filters cascade extension |
| 4 | standard | REFACTOR puro filter_active?/5 → /1 socket-based, behavior-preserving |
| 5 | **complex** | Cross-cutting template + filter_active?/1 body extension per text + derive_filter_opts + empty state composition |
| 6 | standard | Docs sync + out-of-scope guard update |

## Pre-PR Quality Gate

- [ ] `mix test --include migration` passa.
- [ ] `mix format --check-formatted` exit code 0.
- [ ] `mix credo` passa.
- [ ] `mix deps.audit` passa.
- [ ] `mix compile --warnings-as-errors` passa.
- [ ] `/code-review` su file toccati passa.
- [ ] **F1 traceability**: ogni `Scenario:` Gherkin ha almeno un test.
- [ ] **V1**: 3 screenshot in `docs/screenshots/slice-8/`.
- [ ] **V1a**: Lighthouse a11y mediana ≥ 95.
- [ ] **V1b**: keyboard-only walkthrough.
- [ ] **V2**: manual test live typing rapido + debounce.
- [ ] CI verde sul push.

## Risks & Open Questions

- **R8-1 — `apply_text_search` rule of 3 nel query path**: 5 clausole query-path ora. Trigger per estrazione modulo dedicato `Ideajar.Ideas.Filter.QueryClauses`: 6+ clausole. Slice 8 sotto la soglia.
- **R8-2 — `filter_active?/1` socket-based refactor durante slice 8**: ha 5 callsite nel template. Ricerca/replace + arity-pin test update. Test esistenti continuano a passare se body è equivalente.
- **R8-3 — SQLite LIKE performance su description di idee verbose**: per ~100 idee la full-table scan è O(N) con substring match. Acceptable. Trigger per indice o FTS5: 1000+ idee O latency percepita.
- **R8-4 — Ecto fragment escape syntax (RESOLVED iter1 review)**: il pre-fix iter1 plan usava `"ESCAPE '\\\\'"` (Elixir source 4 chars, SQL output 2-byte `'\\'`), che SQLite rifiuta con `ESCAPE expression must be a single character`. Iter2 ha corretto a `"ESCAPE '\\'"` (Elixir source 2 chars, SQL output 1-byte `'\'`). Authoritative reference: DD-S8-2 byte-mapping note. Pinnato via `Repo.to_sql/2` nei test step 1 RED #4 + #11.
- **R8-5 — `description IS NOT NULL` clause**: doppia evaluation di `description` nel WHERE. SQLite optimizer dovrebbe short-circuit. Performance trascurabile a 100 idee.
- **R8-6 — Form-shape vs bare-shape extractor coverage**: regression pin per il bug slice 7b filter search. Importante per real-browser typing.
- **R8-7 — XSS HEEx auto-escape sul value attribute**: il input `value={@text_search_query}` è auto-escaped da HEEx. Test pin con query maliziosa per regression.
- **R8-8 — gettext deferral (slice 4 R6 carry-over)**: slice 8 aggiunge ~5 stringhe. Cumulative ~90. Trigger residuo (utente non-IT) non scattato.
- **R8-9 — phx-debounce 300ms vs 200ms**: text input usa 300ms (parallel slice 7a iter2 search). Slider è 200ms. Non uniformare per ora — sono UX domains diversi.
- **R8-10 — Out-of-scope guard regex narrowing**: slice 7b ha allargato a `Cerca punto di partenza` + refute altri. Slice 8 allarga a `Cerca idee`. Slice 9+ può richiedere ulteriori narrowing.

## Plan Review Summary

Quattro plan-review personas dispatched in parallel (Acceptance / Design / UX / Strategic). Verdetti finali post-iter2:

### Acceptance Test Critic — `approve` (post-iter2)
**Iter1 blocker fissati**:
- **B1 SQL escape syntax**: corrette tutte le occorrenze fragment a Elixir `"ESCAPE '\\'"` (2-char source → 1-byte runtime `\`), in linea con SQLite `ESCAPE expression must be a single character`. Byte-mapping note esplicita aggiunta in DD-S8-2. Regex pin `~r/ESCAPE '\\'/` in DM3 e step 1 RED #4.
- **B2 description-only match scenario**: aggiunto step 1 RED #11 — query `"stadio"` con seed (idea A title `Concerto rock` desc `Stadio Olimpico`, idea B title `Sirolo`) → solo A returned. Pin che title-false + description-true match.
- **B3 clear_filters TDD discipline**: spostato il GREEN extension del `clear_filters` handler in step 3 (con RED #9 che pin `@text_search_query == ""` post-`Mostra tutte`). Step 5 ora puro template + filter_active?/1 body extension.
- **B4 backslash escape integration**: aggiunto step 1 RED #10 — query `"\\foo"` (runtime `\foo`) con seed `\foo` vs `foo` → solo `\foo` matched. End-to-end escape-character correctness pin.

**Warning residuo (R8-4)**: testo della risk entry rinfrescato post-fix per coerenza con DD-S8-2 authoritative.

### Design & Architecture Critic — `approve` (post-iter2)
**Iter1 blocker fissati**:
- **B1 Ecto fragment escape**: stessa fix verificata indipendentemente. Byte-mapping note "pedagogicamente solida". Step 1 RED #4 + #10 pinnano end-to-end.
- **B2 filter_active?/5 → /1 refactor split**: step 4 è ora un REFACTOR puro behavior-preserving (arity-pin + invariante across 5 axes esistenti + esplicito "NO text axis yet" pin). Step 5 estende SOLO il body (no arity change). Step 3 owns `clear_filters` cascade. Total 6 step.

**Warnings non-bloccanti** (acceptable):
- W1 Rule-of-3 `Filter.QueryClauses` extraction borderline (5 clausole + `escape_like/1`). Defer slice 9.
- W2 `escape_like/1` location in Filter OK per ora; promote a `Filter.Like` se slice 9 introduce un altro LIKE-using clause.
- W3 Doppia eval `description` short-circuited da SQLite. Pattern uniforme con `apply_max_cost`. Keep as-is.
- W4 Multi-shape extractor uniform con slice 7b (lezione applicata correttamente).
- W5 NULL-exclude exception ben documentata (spec lines 26-31, plan DD-S8-4, F8/F9, D2 doc update).
- W6 Hostile uniform list 5 inputs come slice 7b pattern.

### UX Critic — `approve` (con 5 warning non-bloccanti)
- **W1 — Min-3 friction senza feedback visivo**: utente digita "Ro" senza reazione. Suggerimento (deferito): aggiungere "Minimo 3 lettere" all'helper text OR mostrarlo inline solo quando `byte_size(q) in 1..2`. Documentato come iter futuro UX.
- **W2 — Assenza X icon nell'input**: bottone reset sotto l'input occluso da virtual keyboard mobile. Pattern X-icon dentro input out-of-scope slice 8; possibile iter futuro.
- **W3 — Copy `Rimuovi filtro testo` vs `Cancella ricerca`**: coerenza sistemica vince (parallel `Rimuovi filtro distanza`). Confermato.
- **W4 — Cognitive load 5 sub-block + Mostra tutte sotto fold**: validare via screenshot V1 a 360px.
- **W5 — Helper text NULL-exception orientato developer**: `description` è jargon. Possibile rephrasing futuro: "Cerca nel titolo e nelle note dell'idea." Defer.

### Strategic Critic — `approve` (con 3 warning non-bloccanti)
- **W1 Opportunity cost**: slice 8 ritarda il loop real-user feedback di 1-2 giorni. Tradeoff acceptable: chiude la promessa CONTEXT.md (filtro #5) prima del deploy. Slice 9 (PWA) non sarebbe più veloce.
- **W2 Coverage gap**: nessuno slice scoped per onboarding/empty workspace UX. Filare issue prima del deploy.
- **W3 Couple-2-user reality check**: text search useful at 50+ idee. NON misurare il successo della feature contro early adoption metrics; il valore emerge col backlog crescente.

### Iter 2 — convergence
Tutti i 4 reviewers post-fix tornano `approve`. Nessun blocker residuo. Plan flip da `draft` → `approved` autorizzato.
