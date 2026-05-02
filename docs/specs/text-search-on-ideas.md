# Spec: Text search filter on ideas

> Slice 8. Adds a 5th filter sub-block (after Distanza) that performs a
> case-insensitive substring match on `title` + `description` via SQLite
> `LIKE %q%`. Active when query ≥ 3 chars; live-debounced 300 ms.
> NULL-`description` ideas are NOT auto-excluded (documented exception
> to the slice-5/6/7b uniform NULL-exclude pattern). Composes in AND
> with the other 4 filters.

## Intent Description

Slice 8 chiude il set di filtri promesso da CONTEXT.md introducendo la
**ricerca testuale**. User digita una query in un input nel filter row
(5° sub-block, dopo Distanza). Quando la query è **≥ 3 caratteri** il
filtro è attivo: la lista mostra solo le idee il cui `title` OR
`description` contiene la stringa (case-insensitive). Sotto i 3
caratteri il filtro è inattivo (NULL-pass implicit), in linea con il
pattern slice 7a iter2 / 7b filter search.

**Algoritmo**: SQLite `LIKE %q%` con `COLLATE NOCASE` (case-insensitive
nativo). NO FTS5 — overkill per la scala del progetto (~100 idee, 2
utenti). Trigger per upgrade FTS5: 1000+ idee O ranking necessario.

**NULL-exclude — eccezione documentata**. Slice 5 (durata), 6 (budget),
7b (distanza) escludono uniformemente le idee con valore NULL quando il
filtro è attivo. Slice 8 è l'eccezione: la semantica `OR` naturale
prevale (`title LIKE q OR description LIKE q`). Un'idea con
`description = nil` ma `title` matchante PASSA. Razionale: il text
filter è "trova le idee che contengono X"; description NULL non
contribuisce al match ma non penalizza l'idea. La eccezione va
documentata in `CONTEXT.md` `## Decisione su filtri non applicabili`.

**Architettura**: nuovo `Ideajar.Ideas.Filter.apply_text_search/2` nel
query path (NOT post-query come distance — `LIKE` è SQL-friendly).
`Ideas.list_ideas/1` estesa con opt `:text_search :: String.t() | nil`.

**UI**: text input in `<form id="filter-text-search-form" phx-change=
"update_text_search">` (lezione slice 7b: phx-change su input bare non
fira nel browser, deve essere in form). Live debounced 300 ms. Bottone
scoped `Rimuovi filtro testo` quando attivo. `Mostra tutte` resetta
anche text. Refresh resetta la query (LV-session only, parallel al
pattern slice 7b user_*).

**Combined AND**: testo × categoria × durata × budget × distanza —
tutti AND tra tipi di filtro. La pipeline aggiunge un nuovo opt al
keyword args di `list_ideas/1`.

**Out of scope**:
- Ricerca fuzzy / approximate match
- Ranking / scoring dei risultati
- Highlight dei matched terms nelle card
- Search history / suggested queries
- URL params / deep-link query
- Search across `location_name` (slice 7b reference search ha già
  questa semantica per il punto di partenza)
- Search analytics
- FTS5 virtual table / migration

## User-Facing Behavior

```gherkin
Feature: Filter ideas by free-text query on title and description

  Background:
    Given my browser holds a valid signed session cookie
    And the workspace has these ideas:
      | title             | description                       |
      | Sirolo            | Mare bellissimo, spiaggia bianca  |
      | Uffizi            | Galleria di Firenze               |
      | Picnic improvviso |                                   |
      | Pizza in terrazza | Cena estiva sul tetto             |
      | MARE in tempesta  |                                   |
      | Concerto rock     | Stadio Olimpico, energia pura     |

  # ── Initial state ───────────────────────────────────────────────
  Scenario: Visiting / shows the text search sub-block empty
    When I visit "/"
    Then I see a sub-group with aria-label "Filtra per testo"
    And there is a text input "Cerca idee"
    And the input is empty
    And there is no "Rimuovi filtro testo" button (no query set)
    And every idea is rendered

  # ── Query length threshold ──────────────────────────────────────
  Scenario: Query with < 3 chars leaves the filter inactive
    When I type "ma" into the search input
    Then the filter is NOT applied
    And I still see every idea

  Scenario: Query with exactly 3 chars activates the filter
    When I type "mar" into the search input
    Then the filter is applied
    And I see "Sirolo" (description contains "mare")
    And I see "MARE in tempesta" (title contains "mare", case-insensitive)
    And I do not see "Uffizi"
    And I do not see "Picnic improvviso"
    And I do not see "Pizza in terrazza"
    And I do not see "Concerto rock"

  # ── Match scope: title + description ────────────────────────────
  Scenario: Query matches title
    When I type "uffi"
    Then I see "Uffizi"
    And I do not see anyone else

  Scenario: Query matches description
    When I type "Firenze"
    Then I see "Uffizi" (description contains "Firenze")
    And I do not see anyone else

  Scenario: Query matches both title and description across ideas
    When I type "stadio"
    Then I see "Concerto rock" (description contains "Stadio")
    And I see no idea whose title contains "stadio"
    # Result is the OR — AT LEAST one of title/description must match.

  # ── Case insensitivity ──────────────────────────────────────────
  Scenario: Match is case-insensitive
    When I type "MARE"
    Then I see "Sirolo" (description "mare bellissimo")
    And I see "MARE in tempesta" (title "MARE in tempesta")

  Scenario: Match is case-insensitive — lowercase query, mixed-case data
    When I type "mare"
    Then I see "MARE in tempesta"

  # ── NULL-description exception (D2 spec decision) ───────────────
  Scenario: Idea with NULL description still matches when title matches
    Given "Picnic improvviso" has description = NULL
    When I type "picnic"
    Then I see "Picnic improvviso"
    # No NULL-exclude — title match wins.

  Scenario: Idea with NULL description is excluded only when neither field matches
    Given "Picnic improvviso" has description = NULL
    When I type "stadio"
    Then I do not see "Picnic improvviso"
    # Excluded because title doesn't match either, NOT because description is NULL.

  # ── Combined filters ────────────────────────────────────────────
  Scenario: Text search composes with category as AND
    Given category "mare" required
    When I type "mare"
    Then result is ideas with category "mare" AND (title OR description containing "mare")

  Scenario: 5-way combined AND across all filter types
    Given category "mare" required + duration weekend + budget 500 + reference Sirolo + slider 50 km
    When I type "spiaggia"
    Then result is the AND across all 5 filter axes

  # ── Reset behaviors ─────────────────────────────────────────────
  Scenario: "Rimuovi filtro testo" button clears the query
    Given the search input contains "mare"
    When I click "Rimuovi filtro testo"
    Then the input is empty
    And every idea is rendered again
    And the "Rimuovi filtro testo" button is hidden

  Scenario: "Mostra tutte" resets the text query alongside the other filters
    Given category "mare" required + slider 50 km + search "spiaggia"
    When I click "Mostra tutte"
    Then category, distance, and text are all reset
    And the search input is empty

  Scenario: Refresh resets the text query (LV-session only)
    Given the search input contains "mare"
    When I reload "/"
    Then the input is empty
    And no filter is applied

  Scenario: Form submission does NOT reset the text query
    Given the search input contains "mare"
    And the form is opened
    And a valid idea is submitted
    Then after save success: the query is unchanged
    And the new idea is in the list (filtered if its title/description doesn't match)

  # ── Live behavior ───────────────────────────────────────────────
  Scenario: phx-change is debounced 300 ms
    When I type "mar" in 50 ms
    Then only one server update_text_search event is dispatched (after 300 ms idle)

  # ── Hostile inputs ──────────────────────────────────────────────
  Scenario: update_text_search with non-binary payload is a no-op
    When the LV receives update_text_search %{"q" => 123}
    Then the @text_search_query is unchanged
    And the LV process stays alive

  Scenario: update_text_search with oversize query (>200 chars) is a no-op
    When I dispatch a query of 201 chars
    Then the @text_search_query is unchanged
    And the LV process stays alive

  Scenario: SQL injection attempt is neutralised by Ecto interpolation
    When I type "'; DROP TABLE ideas;--"
    Then the query runs as a literal substring search
    And no SQL command is executed beyond the parametrised SELECT
    And the LV process stays alive

  Scenario: LIKE wildcard characters in the query are treated literally
    When I type "%_a"
    Then the search uses `\%\_a` (escaped) — wildcards do NOT bypass the literal substring match
    # Otherwise a user typing "%" would match every idea regardless of intent.

  # ── XSS regression ──────────────────────────────────────────────
  Scenario: Malicious query is HTML-escaped on render
    When I type "<script>alert(1)</script>"
    Then the input value attribute is HTML-escaped on re-render
    And no <script> element appears in the DOM
    And the LV process stays alive

  # ── Empty state composition (slice 5 invariant) ─────────────────
  Scenario: Workspace empty + text query inactive → "Nessuna idea ancora"
    Given the workspace has 0 ideas
    And the search input is empty
    Then I see "Nessuna idea ancora. Aggiungine una qui sopra."

  Scenario: Workspace non-empty + text query active + zero matches → empty-filter state
    Given 6 ideas seeded
    When I type "qqxz"
    Then I see "Nessuna idea per i filtri attivi."
    And the "Mostra tutte" button is rendered

  # ── Out-of-scope guard ──────────────────────────────────────────
  Scenario: Slice 8 does NOT introduce highlight of matched terms
    When I type "mare" and an idea matches
    Then the rendered card does NOT contain a <mark> or highlighted span
    # Highlight is slice 9+.

  Scenario: Slice 8 does NOT introduce search history
    When I visit / after a previous session search
    Then the search input is empty
    # No localStorage, no DB persistence.

  # ── Domain-layer pins ───────────────────────────────────────────
  Scenario: Filter.apply_text_search/2 with nil opt is a no-op
    When I call Filter.apply(query, text_search: nil)
    Then the emitted SQL has no LIKE clause on title or description

  Scenario: Filter.apply_text_search/2 with < 3 chars is a no-op
    When I call Filter.apply(query, text_search: "ma")
    Then the emitted SQL has no LIKE clause

  Scenario: Filter.apply_text_search/2 with ≥ 3 chars emits LIKE on title OR description
    When I call Filter.apply(query, text_search: "mar")
    Then the emitted SQL contains:
      WHERE (LOWER(title) LIKE '%mar%' OR LOWER(description) LIKE '%mar%')
    # Or equivalently: COLLATE NOCASE on the comparison.

  Scenario: Filter.apply_text_search/2 escapes LIKE wildcards in the query
    When I call Filter.apply(query, text_search: "%_a")
    Then the bound parameter is "%\\%\\_a%" (with ESCAPE clause)
    # Wildcards in user input are literal characters, not SQL operators.

  Scenario: list_ideas/1 with [text_search: "mar"] returns only matching ideas (regression DM)
    When I call list_ideas(text_search: "mar")
    Then the returned list is the AND of base query + text filter

  Scenario: list_ideas/1 with [] returns all ideas regardless of text filter (regression)
    When I call list_ideas([])
    Then every idea is returned ordered by inserted_at DESC, id DESC
```

## Architecture Specification

### Components

| Componente | Tipo | Responsabilità |
|---|---|---|
| `Ideajar.Ideas.Filter.apply_text_search/2` (nuovo, query layer) | Helper privato | Estende il `apply/2` del modulo `Filter`. `nil` o query < 3 chars → no-op. ≥ 3 chars → `WHERE LOWER(title) LIKE LOWER(?) OR LOWER(description) LIKE LOWER(?)` con la query wrapped in `%...%` (con escape di `%`/`_`). |
| `Ideajar.Ideas.Filter.apply/2` (esteso) | Public fn | Aggiunge il chain `\|> apply_text_search(Keyword.get(opts, :text_search))`. Resta una `Ecto.Query.t()` → `Ecto.Query.t()`. |
| `Ideajar.Ideas.list_ideas/1` (esteso) | Context fn | Nuovo opt `:text_search :: String.t() \| nil`. Pipeline invariata (`build_query \|> Repo.all \|> Repo.preload \|> Filter.apply_post`). `apply_post/2` invariato (no post-query change). |
| `IdeajarWeb.IdeaLive.Index` (esteso) | LiveView | Nuovo assign `@text_search_query :: String.t()` (default `""`). Nuovi handler `update_text_search` (defensive parse + assign + reload), `remove_text_search` (reset). `clear_filters` esteso (DD-S8-1). `filter_active?/N` esteso (DD-S8-2). `derive_filter_opts/1` esteso (DD-S8-3). |
| Template `index.html.heex` (esteso) | HEEx | Nuovo sub-block `<div role="group" aria-label="Filtra per testo">` dopo Distanza. Sub-block contiene: label visibile `Testo`, helper text NULL-exclude exception, `<form id="filter-text-search-form" phx-change="update_text_search">` con text input + bottone `Rimuovi filtro testo` (conditional). |

### Interfaces

**Domain API:**
```elixir
defmodule Ideajar.Ideas.Filter do
  # ... existing apply/2 ...

  @doc """
  Composes every active query-layer clause onto `query` based on `opts`.
  Slice 8: adds :text_search clause.
  """
  @spec apply(Ecto.Query.t(), keyword()) :: Ecto.Query.t()
  # NEW chain step: |> apply_text_search(Keyword.get(opts, :text_search))

  # NEW slice 8 — :text_search in [:nil, < 3 chars] → no-op
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

  defp escape_like(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end

# list_ideas/1 opts (extended):
#   required: [integer]
#   optional: [integer]
#   durations: [atom]
#   max_cost: integer | nil
#   max_distance_km: integer | nil
#   ref_lat: float | nil
#   ref_lng: float | nil
#   text_search: String.t() | nil   # NEW slice 8
```

**LiveView assigns (estesi):**
- `@text_search_query :: String.t()` (default `""`)

**LiveView events:**
- `update_text_search` con `%{"q" => binary} | %{"filter" => %{"text_search" => binary}}` — text input phx-change. Defensive: non-binary → no-op; > 200 chars → no-op (oversize guard); altrimenti assign + `reload_ideas`.
- `remove_text_search` — bottone click. Reset `@text_search_query = ""` + reload.
- `clear_filters` (esteso slice 8) — reset 6 axes (categoria + durata + budget + distanza + ref point + testo).

**Template structure (5° sub-block dopo Distanza):**
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

### Constraints

- **Min query length 3 chars**: `apply_text_search/2` no-op on `byte_size(q) < 3`. Server-side enforcement (no JS). Parallel slice 7a iter2 + slice 7b filter search.
- **Case-insensitive**: SQLite `LOWER(...) LIKE LOWER(...)` su entrambi i lati. Più portable di `COLLATE NOCASE` (che è SQLite-only attribute).
- **LIKE wildcard escape**: input `%`/`_`/`\` viene escaped a `\%`/`\_`/`\\` con `ESCAPE '\'`. Senza escape, un utente che digita `%` matcherebbe ogni idea.
- **NULL-description exception**: `description LIKE` clause è gated by `description IS NOT NULL` (per evitare valutazione 3-valued logic in modo confuso); MA il `title LIKE` clause non ha NULL-guard (title è NOT NULL nel schema). Quindi un'idea con description NULL passa SE il title matcha.
- **Oversize input guard (S2)**: query > 200 chars (matching `maxlength="200"` del template) → no-op server-side. Doubles maxlength del HTML attribute con guard server-side per hostile bypass.
- **Hostile uniform list**: non-binary, oversize, malformed payload → no-op silenzioso. Ecto `^pattern` parametrization previene SQL injection by default.
- **XSS regression**: la query è renderizzata SOLO come `value` attribute dell'input (HEEx auto-escape). NO display nelle card.
- **`@text_search_query` LV-session only**: no localStorage, no DB. Refresh = reset. Save success NON resetta (filter survives submit, parallel slice 7b DD11).
- **5° sub-block layout**: `<div role="group" aria-label="Filtra per testo">` dopo Distanza. Source order: Categorie → Durata → Budget → Distanza → Testo. NO RovingTabindex (singolo input).
- **Form wrapping mandatorio**: `phx-change` su input bare non fira nel browser (lezione slice 7b). Il `<form id="filter-text-search-form">` è il container che propaga il change event.
- **`Mostra tutte` extension**: 6 reset (categoria + durata + budget + distanza + ref point + testo).
- **Combined filter AND**: testo × categoria × durata × budget × distanza tutti AND.
- **Empty state composition**: 3-way empty state (slice 5 invariant) include text filter nel `filter_active?` check via `@text_search_query != ""` clause.

### Dependencies

Nessuna nuova dep Hex. Nessuna migration (LIKE è native SQLite).

### Out of scope

- Ricerca fuzzy / approximate match (Levenshtein, trigrams)
- Ranking / scoring dei risultati
- Highlight matched terms nelle card (`<mark>`, span colorato)
- Search history / suggested queries
- URL params / deep-link query
- Search across `location_name`
- Search analytics
- FTS5 virtual table

## Acceptance Criteria

### Functional / behavioral

- [ ] **F1** — Tutti gli scenari Gherkin automatabili passano (DataCase + LiveViewTest).
- [ ] **F2** — Mount: `@text_search_query == ""`. Sub-block render. Bottone reset hidden.
- [ ] **F3** — `update_text_search` con `%{"q" => "ma"}` (< 3 chars) → assign aggiornato, ma SQL non emette LIKE.
- [ ] **F4** — `update_text_search` con `%{"q" => "mar"}` (≥ 3 chars) → SQL emette LIKE su title + description.
- [ ] **F5** — `update_text_search` con form-shape `%{"filter" => %{"text_search" => "mar"}}` → stesso comportamento di F4 (real browser shape pin).
- [ ] **F6** — Match case-insensitive su title.
- [ ] **F7** — Match case-insensitive su description.
- [ ] **F8** — Idea con `description = nil` ma title matchante → IN risultato.
- [ ] **F9** — Idea con `description = nil` e title non matchante → OUT risultato.
- [ ] **F10** — `remove_text_search` → `@text_search_query = ""`. Bottone reset hidden.
- [ ] **F11** — `clear_filters` (Mostra tutte) → reset 6 filter types incluso text.
- [ ] **F12** — Refresh resetta `@text_search_query` (LV remount).
- [ ] **F13** — Save success NON resetta `@text_search_query` (filter survives submit).
- [ ] **F14** — Filter combined AND con altri 4 (categoria + durata + budget + distanza).
- [ ] **F15** — phx-debounce 300 ms (regression pin via attribute presence).
- [ ] **F16** — LIKE wildcards (`%`, `_`) in query → escaped a literal characters.

### Domain layer

- [ ] **D1** — `Filter.apply_text_search/2` con `nil` → no-op (SQL invariato).
- [ ] **D2** — `Filter.apply_text_search/2` con < 3 chars → no-op.
- [ ] **D3** — `Filter.apply_text_search/2` con ≥ 3 chars → emette `WHERE LOWER(title) LIKE LOWER(?) ESCAPE '\\' OR (description IS NOT NULL AND LOWER(description) LIKE LOWER(?) ESCAPE '\\')`.
- [ ] **D4** — `Filter.apply_text_search/2` non-binary → no-op (defensive).
- [ ] **D5** — `Ideas.list_ideas([])` invariato (regression).
- [ ] **D6** — `Ideas.list_ideas([text_search: "mar"])` → solo idee matchanti.
- [ ] **D7** — `Ideas.list_ideas([required: [...], durations: [...], max_cost: ..., max_distance_km: ..., ref_lat: ..., ref_lng: ..., text_search: ...])` → 6-way combined AND.
- [ ] **D8** — `Filter.apply_text_search/2` escapa `%` e `_` letterali nella query.

### Accessibility

- [ ] **A1** — Sub-block ha `role="group" aria-label="Filtra per testo"`.
- [ ] **A2** — Input ha `placeholder="Cerca idee"`, `autocomplete="off"`, `maxlength="200"`.
- [ ] **A3** — Helper text NULL-exception visibile.
- [ ] **A4** — Filter row sub-block order: Categorie → Durata → Budget → Distanza → Testo (DOM source order).
- [ ] **A5** — Form wrapper `<form id="filter-text-search-form">` per phx-change browser firing.
- [ ] **A6** — Bottone `Rimuovi filtro testo` hit area ≥ 44×44 (`min-h-11 min-w-11`).

### Security / robustness

- [ ] **S1** — `update_text_search` con non-binary `%{"q" => 123}` → no-op (uniform list).
- [ ] **S2** — `update_text_search` con oversize query > 200 chars → no-op (server-side guard).
- [ ] **S3** — `update_text_search` con malformed payload (missing keys, wrong shape) → no-op.
- [ ] **S4** — SQL injection attempt `"'; DROP TABLE ideas;--"` → trattato come literal substring, no SQL execution.
- [ ] **S5** — XSS: query maliziosa `<script>alert(1)</script>` → HEEx auto-escape, no script execution.
- [ ] **S6** — LIKE wildcards in input non bypassano la semantica literal (escape).

### Operational / data

- [ ] **O1** — Nessuna migration. Schema slice 7a + slice 7b sufficiente.
- [ ] **O2** — `Filter.apply_text_search/2` testato indipendentemente con unit test (5+ casi: nil / < 3 / ≥ 3 / case / NULL desc).
- [ ] **O3** — Performance: `list_ideas` con 5 filter attivi + 100 idee fixture < 100 ms (sanity).
- [ ] **O4** — SQL emission pin: la WHERE clause include LIKE su title + description quando text_search active.

### Validation venue

- [ ] **V1** — Screenshot mobile (iPhone 13, Pixel 7, 360px Pixel 4a): sub-block testo vuoto, sub-block con query attiva, empty-filter state.
- [ ] **V1a** — Lighthouse a11y mediana ≥ 95 con tutti i 5 filtri attivi.
- [ ] **V1b** — Keyboard-only walkthrough: Tab al sub-block testo, type 3+ chars, Tab al `Rimuovi filtro testo`, Enter.
- [ ] **V2** — Manual test live: typing rapido durante drag mouse → debounce funziona, no flicker.

### Documentation

- [ ] **D1d** — `docs/conventions.md` UI copy table aggiornata con stringhe slice 8 (~8 strings).
- [ ] **D2d** — `CONTEXT.md` `## Decisione su filtri non applicabili` esteso per documentare l'eccezione text-search.
- [ ] **D3d** — `CONTEXT.md` riga 84 (filtri Ricerca testuale) marca come implemented (slice 8).
- [ ] **D4d** — `test/ideajar/docs_test.exs`: nuova `describe "slice-8 UI copy"`.
- [ ] **D5d** — Out-of-scope guard regex update: rimuove `Cerca` standalone (slice 8 implementa). Guard ora consente `Cerca punto di partenza` (slice 7b) + `Cerca idee` (slice 8) come due strings legittime.

### UI copy aggiunta (canonical)

| Elemento | Testo IT |
|---|---|
| Sub-label visibile filtro Testo | `Testo` |
| Aria-label sub-block (SR) | `Filtra per testo` |
| Helper text NULL-exception | `La ricerca trova le idee con la parola in titolo o descrizione.` |
| Placeholder text input | `Cerca idee` |
| Bottone rimuovi filtro testo | `Rimuovi filtro testo` |

## Consistency Gate

- [x] Intent unambiguo — query length threshold (3 chars), match scope (title + description), NULL-exception, algorithm (LIKE), live behavior (debounce 300ms) tutti chiariti
- [x] Ogni behavior ha BDD scenario corrispondente (length threshold, match scope title/description, case insensitivity, NULL exception, combined AND, reset, refresh, hostile inputs, XSS, LIKE escape, domain layer pins)
- [x] Architecture constrains without over-engineering (LIKE in query layer giustificato da SQL-friendliness, NO FTS5, no migration, form wrapping mandatorio per browser eventfiring)
- [x] Termini consistenti (text search, query, NULL-exception, ≥ 3 chars, AND, debounce 300ms)
- [x] No contradictions — NULL-exception documentata esplicitamente come deviazione dal pattern uniforme; LV-session vs save-success preservation parallel slice 7b

**Verdict: PASS** — ready for `/plan`.
