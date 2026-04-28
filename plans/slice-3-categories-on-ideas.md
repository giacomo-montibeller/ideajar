# Plan: Slice 3 — Categorie seeded e assegnabili alle idee

**Created**: 2026-04-27
**Branch**: main (trunk-based)
**Status**: implemented
**Spec**: `docs/specs/categories-on-ideas.md`

## Build conventions (carried from slice 1 + 2)

- **Strict TDD** — RED → GREEN → REFACTOR per step.
- **Ogni commit** attraverso la skill `commit-message`.
- Pre-step gate locale: `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo`, `mix deps.audit`, `mix test` (con `--include migration`). Stessi gate in CI su ogni push.
- Domain in `Ideajar.*` (nuovo bounded context `Ideajar.Categories`), delivery in `IdeajarWeb.*`.
- UI copy in italiano canonica appesa a `docs/conventions.md` nel commit che la introduce.

## Goal

Estendere la LiveView slice 2 con tagging multi-categoria. Aggiunge un dominio `Ideajar.Categories` read-only (8 categorie seeded in migration: `passeggiata, mare, museo, ristorante, sport, cultura, cinema, viaggio`), una tabella join `idea_categories` con CASCADE/RESTRICT, ed estende il form add-idea con chip toggleabili (`<button type="button" aria-pressed=…>`). Almeno una categoria obbligatoria, validata a livello changeset; nessuna UI di gestione categorie. Le idee dev di slice 2 sono cancellate da una migration dedicata (dati di test).

Fuori scope: filtri per categoria (slice 4), search per nome (slice 8), badge colorati, CRUD UI categorie.

## Decisioni architetturali pre-build (chiuse iter 2)

- **A1 — Validation venue**: "almeno una categoria" è single source of truth a livello changeset (`validate_length(:categories, min: 1, ...)`). Nessun vincolo DB equivalente (SQLite non supporta nativamente "min:1 in associazione many-to-many" e per 2 utenti il changeset è sufficiente).
- **A2 — Pure changeset**: `Idea.changeset/2` è puro (niente `Repo` calls). Riceve `%{categories: [%Category{}]}` già risolto. Il fetch + dedup + invalid_id check vive in `Ideas.create_idea/1` (impure boundary).
- **A3 — Drop `on_replace: :delete`** *(rivista iter 2)*: il flag è inutile in slice 3 (solo create). Il default `:raise` farà fallire rumorosamente la prima edit landing che lo richieda — meglio una decisione esplicita in quella slice.
- **A4 — Display order ordering**: tutte le query esposte (`list_categories/0`, preload `:categories` in `list_ideas/0`) ordinano per `display_order ASC` esplicitamente — niente affidamento all'insertion order. **Top-level idea ordering invariato da slice 2** (`inserted_at DESC, id DESC`).
- **A5 — Chip a11y + visual contract**: `<fieldset>` con `<legend>Categorie *</legend>` (asterisco indica required, helper text inline `Scegli almeno una categoria`). Ogni chip è `<button type="button" aria-pressed={selected?} phx-click="toggle_category" phx-value-id={id} class="min-h-11 min-w-11 …">{name}</button>`. Stato selezionato distinto da uno stato deselezionato tramite **due cue indipendenti dal colore**: (1) un'icona `<.icon name="hero-check" />` leading visibile solo quando selected, e (2) attributo `data-selected="true"` (assertable in test). Entrambi gli stati hanno contrasto testo ≥ 4.5:1 sul background; differenza di luminosità tra selected/deselected ≥ 3:1 (verificato via Lighthouse).
- **A6 — Focus push su error categorie** *(rivista iter 2)*: quando submit fallisce con `:categories` come primo invalid in priority order, `push_event("ideajar:focus", %{to: "#idea-categories-error"})` (focus su elemento `<p role="alert" tabindex="-1">` che contiene il messaggio errore — pattern WAI-ARIA APG per gruppi). Lo screen reader annuncia l'errore prima che il primo chip sia raggiungibile via Tab. Priority order: `:title → :categories → :url → :description`.
- **A7 — Selected state in MapSet**: `@selected_category_ids :: MapSet.t(integer)`. Lo state vive fuori dal `@form` perché i chip non sono input HTML standard. Il save handler inietta `category_ids` in attrs prima di chiamare `Ideas.create_idea/1`. Reset su `close_form` e su save success; preservato attraverso reconnect transient (LiveView preserva assigns by default).
- **A8 — Dropping slice-2 dev data — migration dedicata** *(rivista iter 2)*: la migration `wipe_slice2_dev_ideas` (Step 4a) usa raw SQL `execute("DELETE FROM ideas")` come `up/0`, niente nel `down/0`. Self-documenting nel nome del file e indipendente da future rinomine dello schema `Idea`. La migration `create_idea_categories` (Step 4b) è purely additive (DDL only) ed è auditabile separatamente in cronologia git. **Guard**: la migration di wipe documenta in commento che è ammissibile solo perché slice 2 è dev/test data; futuri prod-deploy con dati reali non eseguiranno questa migration (è già stata applicata).
- **A9 — Migration idempotency strategy**: il seed delle 8 categorie usa `Repo.insert_all(..., on_conflict: :nothing, conflict_target: :name)` così che un'invocazione manuale di `up/0` su un DB già seeded non duplichi righe. Il test pinna esattamente questo: `Ecto.Migrator.up/4` invocata due volte → 8 righe finali, no exception.
- **A10 — Errore "Categoria non valida" — single error path** *(rivista iter 2)*: `Ideas.create_idea/1` rifiuta `category_ids` con id non risolvibili. Per evitare doppio errore su `:categories` (bug iter 1: `Idea.changeset` aggiungeva "Seleziona almeno una categoria" anche nel path invalid-id), il path errore costruisce il changeset SENZA passare per `Idea.changeset/2`: cast solo dei campi non-categories (title/description/url), poi `add_error(:categories, "Categoria non valida")`. Asserito esplicitamente in Step 6 RED che `length(Keyword.get_values(cs.errors, :categories)) == 1`.
- **A11 — `Categories.list_by_ids/1` come boundary** *(nuova iter 2)*: per non far reachare `Ideas` dentro lo schema `Category`, il context `Categories` espone `list_by_ids(ids :: [any]) :: {:ok, [Category.t()]} | {:error, :not_found}`. La funzione: (a) cast int safe (rifiuta non-integer/negative/zero/nil con `:not_found`); (b) dedupe POST cast (così `["1", 1]` deduplicano); (c) query `WHERE id IN ^unique_ids`; (d) ritorna `{:ok, cats}` solo se `length(cats) == length(unique_ids)`, altrimenti `{:error, :not_found}`. `Ideas` chiama solo questa funzione, niente import dello schema.
- **A12 — Test fixture in modulo dedicato** *(nuova iter 2)*: il seed delle 8 categorie nei test vive in `test/support/fixtures/categories_fixtures.ex` (export `seed_canonical_categories!/0`, `category_fixture/1`). DataCase resta pulita; ogni test che ne ha bisogno chiama esplicitamente `setup_all` o `setup` con il fixture. Slice 4/8 riusano lo stesso modulo.
- **A13 — Auth boundary su nuovi handler** *(nuova iter 2)*: `toggle_category` e `save` sono dispatched solo dopo mount autenticato — la difesa è il mount redirect di slice 2. Nessun guard aggiuntivo nei handler (il socket non esiste se mount ha redirect). Test esplicito S4 verifica che `live_isolated` con session vuota → `{:error, {:redirect, %{to: "/login?return_to=%2F"}}}` anche se i nuovi events sono definiti.

## Acceptance Criteria

> Mappatura uno-a-uno con `docs/specs/categories-on-ideas.md` (sync iter 2 in Step 9).

### Functional / behavioral
- [ ] **F1** — Tutti gli scenari Gherkin **automatabili** passano (LiveView via `Phoenix.LiveViewTest`, domain via `DataCase`). Scenari `:manual` esclusi: `Re-running mix ecto.migrate does not duplicate categories` (testato come "manuale up/0 reinvocazione"), V1/V1a/V1b.
- [ ] **F2** — `Ideas.create_idea/1` con `category_ids: []` o senza la chiave → `{:error, changeset}` con `errors[:categories]` esattamente `Seleziona almeno una categoria` (singola entry, no duplicati).
- [ ] **F3** — `Ideas.create_idea/1` con `category_ids: [valid_id]` → `{:ok, %Idea{categories: [%Category{}]}}` con la riga in `idea_categories`. **Boundary minimo**: 1 categoria sufficiente.
- [ ] **F4** — `Ideas.list_ideas/0` ritorna idee con `:categories` preloaded ordinate per `display_order` ASC. **Top-level ordering preservato da slice 2** (inserted_at DESC, id DESC) — pinato da regression test.
- [ ] **F5** — Click su un chip con `aria-pressed="true"` produce `aria-pressed="false"` al render successivo, e un submit subseguente non include quel `category_id`.
- [ ] **F6** — Click `✕` (close_form) e successivo click `+ Aggiungi idea` (toggle_form) → tutti i chip rendered con `aria-pressed="false"` e `data-selected="false"`.
- [ ] **F7** — Dopo save success, click `+ Aggiungi idea` nella stessa LV session → tutti i chip `aria-pressed="false"` e `data-selected="false"`.
- [ ] **F8** — Recovery: dopo error "Seleziona almeno una categoria", l'utente seleziona un chip e re-submit → idea creata con title/description/url originali (no re-typing).

### Security
- [ ] **S1** — XSS: nome categoria escapato in render. Test esplicito: insert categoria con `name: "<script>alert(1)</script>"` via Repo (bypass seed) → form rendered contiene `&lt;script&gt;alert(1)&lt;/script&gt;` E **non** contiene la stringa literal `<script>alert(1)</script>` (entrambe le metà richieste).
- [ ] **S2** — `category_ids` con valori non risolvibili in DB → `{:error, changeset}` con `errors[:categories]` esattamente `Categoria non valida`. **Coverage hostile inputs** (ognuno è un test): `[999_999]` (id non esistente), `[-1]`, `[0]`, `["abc"]` (non-integer string), `[""]` (empty string), `[nil]`, `[1.5]`, `[valid_id, 999_999]` (mix valid + invalid → no partial commit). Nessun caso solleva un'eccezione: tutti producono il controlled error.
- [ ] **S3** — `category_ids` duplicati silenziosamente normalizzati post-cast. **Coverage**: `[1, 1, 2]` → 2 categorie distinte; `[1, 1, 1]` → 1 categoria (sufficiente per min:1, idea creata); `["1", 1]` → 1 categoria distinta (dedupe è POST integer cast, non prima).
- [ ] **S4** — *(nuova iter 2)* Auth boundary: `live_isolated(conn, IdeaLive.Index, session: %{})` ritorna `{:error, {:redirect, %{to: "/login?return_to=%2F"}}}` anche dopo l'aggiunta dei nuovi event handlers. Test esplicito che la session-empty mount non assegna `@categories` né `@selected_category_ids`.

### Operational / data
- [ ] **O1** — Migration forward seeds 8 categorie con `display_order` 1..8 univoci.
- [ ] **O2** — Round-trip migration test (up → down → up) per ognuna delle migration aggiunte: `create_categories`, `seed_categories`, `wipe_slice2_dev_ideas`, `create_idea_categories`. Up→down→up termina nello stesso schema state che up.
- [ ] **O3** *(rivista iter 2)* — Manualmente invocare `Ecto.Migrator.up/4` per la seed-categories migration su un DB già migrato → 0 righe duplicate (count rimane 8), nessuna exception.
- [ ] **O4** — `ON DELETE CASCADE` su `idea_categories.idea_id` verificato (`Repo.delete!(idea)` rimuove le righe join).
- [ ] **O5** — `ON DELETE RESTRICT` su `idea_categories.category_id` verificato (`Repo.delete!(category)` con riga referenziata raise `Ecto.ConstraintError` matching `~r/foreign key|FOREIGN KEY|RESTRICT|constraint/i`).
- [ ] **O6** *(nuova iter 2)* — `PRIMARY KEY (idea_id, category_id)` su `idea_categories` previene duplicati: `Repo.insert_all/3` con (idea_id, category_id) duplicato di una riga esistente raise constraint error matching `~r/unique|UNIQUE|primary key/i`. Defense in depth oltre `Enum.uniq`.

### Validation venue
- [ ] **V1** — 4 screenshot mobile (iPhone 13 + Pixel 7 + 360px Pixel 4a): form aperto con tutti i chip non selezionati, form aperto con 3 chip selezionati, form con errore "Seleziona almeno una categoria", lista con 3 idee multi-category.
- [ ] **V1a** — Lighthouse a11y mobile preset, 3 run consecutivi, mediana ≥ 95 sulla home con form aperto + chip `[mare, museo, viaggio]` selezionati. Tutti e 3 i JSON allegati.
- [ ] **V1b** — Keyboard-only walkthrough esplicito (verifica focus push su error region per A6):
  1. Tab dal pulsante `+ Aggiungi idea` → form aperto, focus su `#idea-title`.
  2. Tab attraverso Titolo → Descrizione → Link → primo chip (display_order=1, passeggiata).
  3. Sui chip: Space toggle `aria-pressed`; SR annuncia il nome chip + nuovo stato; Tab passa al chip successivo (no roving tabindex per slice 3).
  4. Tab dall'ultimo chip → bottone `Salva`.
  5. **Submit con title valido + zero chip selezionati** → focus push su `#idea-categories-error` (elemento `<p role="alert" tabindex="-1">`); SR annuncia "Seleziona almeno una categoria".
  6. Da quell'elemento, Tab → ritorna sul primo chip; selezionare un chip e Salva → idea creata, focus push su `#add-idea-button`.
  7. Verifica assenza di focus trap in entrambe le direzioni (Tab e Shift+Tab attraverso form aperto).

### Documentation
- [ ] **D1** — `docs/conventions.md` "UI copy" table aggiornata con: legend `Categorie *`, helper text `Scegli almeno una categoria`, errori `Seleziona almeno una categoria` + `Categoria non valida`, e i nomi delle 8 categorie.
- [ ] **D2** — `docs/specs/categories-on-ideas.md` sync con plan iter 2 (vedi Step 9): scenari Gherkin aggiornati con focus pin esplicito, scenari boundary aggiunti, "mix ecto.migrate" scenario riformulato come "manual up/0 reinvocation".

### UI copy aggiunta (canonical)

| Elemento | Testo IT |
|---|---|
| Legend del fieldset | `Categorie *` |
| Helper text sotto legend | `Scegli almeno una categoria` |
| Errore "almeno una" | `Seleziona almeno una categoria` |
| Errore id invalido | `Categoria non valida` |
| Categoria 1 | `passeggiata` |
| Categoria 2 | `mare` |
| Categoria 3 | `museo` |
| Categoria 4 | `ristorante` |
| Categoria 5 | `sport` |
| Categoria 6 | `cultura` |
| Categoria 7 | `cinema` |
| Categoria 8 | `viaggio` |

## User-Facing Behavior

> Verbatim sync con `docs/specs/categories-on-ideas.md` iter 2 (Step 9 fa il sync). I test ExUnit citano gli scenari per nome con commento `# Scenario: …` per traceability.

```gherkin
Feature: Tag ideas with one or more curated categories

  Background:
    Given my browser holds a valid signed session cookie
    And the workspace has no ideas
    And the system has the canonical 8 seeded categories with display_order:
      | order | name        |
      | 1     | passeggiata |
      | 2     | mare        |
      | 3     | museo       |
      | 4     | ristorante  |
      | 5     | sport       |
      | 6     | cultura     |
      | 7     | cinema      |
      | 8     | viaggio     |

  # ── Form: chip rendering ────────────────────────────────────────
  Scenario: Opening the form shows all 8 categories as toggleable chips
  Scenario: Each chip toggles its aria-pressed state on click
  Scenario: Multiple chips can be selected at once
  Scenario: Selected chip carries a non-color cue (icon + data-selected)

  # ── Submit: validation ──────────────────────────────────────────
  Scenario: Submitting with at least one category creates the idea
  Scenario: Submitting with exactly one category creates the idea (boundary minimo)
  Scenario: Submitting with no category selected shows the validation error and pushes focus to the error region
  Scenario: The category validation accumulates with title/url errors and focus targets #idea-title (priority)
  Scenario: A toggled-then-untoggled chip submits as no category
  Scenario: Recovery — fixing the category-only error preserves title/description/url

  # ── List: render ────────────────────────────────────────────────
  Scenario Outline: Idea card renders its categories in display_order
    Examples:
      | tags             | rendered order  |
      | cinema, cultura  | cultura, cinema |
      | mare, sport      | mare, sport     |
      | passeggiata, viaggio | passeggiata, viaggio |
  Scenario: An idea with all 8 categories renders all 8 badges in display_order

  # ── Reset semantics ─────────────────────────────────────────────
  Scenario: Closing then reopening the form clears chip selection (F6)
  Scenario: After successful save, reopening the form clears chip selection (F7)

  # ── Persistence semantics ───────────────────────────────────────
  Scenario: Manually re-invoking the seed-categories migration up/0 is a no-op
  Scenario: Deleting an idea cascades on idea_categories but leaves categories intact
  Scenario: Attempting to delete a category that an idea references raises Ecto.ConstraintError
  Scenario: PRIMARY KEY on idea_categories prevents duplicate (idea_id, category_id) inserts

  # ── Hostile inputs (S2/S3) ─────────────────────────────────────
  Scenario Outline: Calling Ideas.create_idea/1 with hostile category_ids returns "Categoria non valida"
    Examples:
      | category_ids        |
      | [999999]            |
      | [-1]                |
      | [0]                 |
      | ["abc"]             |
      | [""]                |
      | [nil]               |
      | [1.5]               |
      | [valid_id, 999999]  |
  Scenario: All-duplicate category_ids dedupe to one and pass min:1
  Scenario: Mixed-type duplicates ["1", 1] dedupe to one category
  Scenario: XSS — a category whose name contains HTML is escaped on render

  # ── Auth boundary (S4) ─────────────────────────────────────────
  Scenario: Unauthenticated mount cannot reach the chip form

  # ── Out-of-scope guard ─────────────────────────────────────────
  Scenario: There is no UI to manage categories (broadened regex)
  Scenario: Ideajar.Categories module exposes only list_categories/0 and list_by_ids/1
```

(Full Gherkin in `docs/specs/categories-on-ideas.md` post Step 9 — pinned by file existence + spec-sync test in Step 9.)

## Steps

### Step 1: Categories table + Category schema (skeleton)

**Complexity**: standard
**RED** (`test/ideajar/categories/category_test.exs` + `test/ideajar/categories/migration_test.exs`):
1. `Repo.insert(%Category{name: "passeggiata", display_order: 1})` → `{:ok, %Category{id: id}}` con timestamps utc.
2. `assert_raise Exqlite.Error, ~r/NOT NULL/, fn -> Repo.insert(%Category{name: nil, display_order: 99}) end`.
3. UNIQUE su `display_order`: `Repo.insert!(%Category{name: "x", display_order: 1})` poi `Repo.insert(%Category{name: "y", display_order: 1})` → `{:error, _}` o `assert_raise` matching `~r/unique|UNIQUE/i`.
4. UNIQUE su `name`: stessa logica.
5. `Category.__schema__(:fields) == [:id, :name, :display_order, :inserted_at, :updated_at]`.
6. **Migration round-trip** (`async: false`, `:migration` tag): up → down → up.

**GREEN**:
- Migration `create_categories` con `add :name, :string, null: false`, `add :display_order, :integer, null: false`, `timestamps(:utc_datetime)`, `create unique_index(:categories, [:name])`, `create unique_index(:categories, [:display_order])`. Niente seed in questo step.
- `lib/ideajar/categories/category.ex` con schema. Niente changeset/funzioni.

**REFACTOR**: nessuno.
**Files**: `priv/repo/migrations/<ts>_create_categories.exs`, `lib/ideajar/categories/category.ex`, `test/ideajar/categories/category_test.exs`, `test/ideajar/categories/migration_test.exs`.
**Spec mapping**: O2 (parte), foundational per F1-F4/S1-S3.

### Step 2: Seed migration (idempotent) + 8 categorie

**Complexity**: standard
**RED**:
1. Dopo `Ecto.Migrator.up/4` per la seed migration: `SELECT name, display_order FROM categories ORDER BY display_order` → esattamente le 8 in ordine `[passeggiata, mare, museo, ristorante, sport, cultura, cinema, viaggio]` con display_order 1..8.
2. **Idempotenza** (O3): re-eseguire `Ecto.Migrator.up/4` sulla stessa migration su DB già seeded → ritorna senza eccezione, count rimane 8.

**GREEN**:
- Migration `seed_categories` con `up/0` che chiama `Repo.insert_all(:categories, [...8 maps con name, display_order, inserted_at, updated_at...], on_conflict: :nothing, conflict_target: :name)`. `down/0` esegue `Repo.delete_all(from c in "categories", where: c.name in ^[8 nomi])`.

**REFACTOR**: estrarre `@seed_categories` module attribute.
**Files**: `priv/repo/migrations/<ts>_seed_categories.exs`, `test/ideajar/categories/seed_migration_test.exs`.
**Spec mapping**: O1, O3.

### Step 3: Ideajar.Categories context (list_categories + list_by_ids)

**Complexity**: standard
**RED** (`test/ideajar/categories_test.exs`):
1. `Categories.list_categories/0` con DB seeded → ritorna 8 `%Category{}` ordinate per `display_order` ASC. Verifica nomi esattamente in ordine.
2. `Categories.list_categories/0` con DB vuoto → `[]`.
3. **`list_by_ids/1` happy path**: con DB seeded, `list_by_ids([cat_mare.id, cat_sport.id])` → `{:ok, [%Category{}, %Category{}]}` con id corrispondenti.
4. **`list_by_ids/1` not_found**: `list_by_ids([999_999])` → `{:error, :not_found}`.
5. **`list_by_ids/1` mixed**: `list_by_ids([cat_mare.id, 999_999])` → `{:error, :not_found}` (no partial).
6. **`list_by_ids/1` integer cast**: `list_by_ids(["#{cat_mare.id}"])` → `{:ok, [%Category{}]}` (string number accettata e convertita).
7. **`list_by_ids/1` rifiuta non-integer**: per ogni valore in `["abc", "", nil, 1.5, -1, 0]` → `{:error, :not_found}` (no exception).
8. **`list_by_ids/1` dedupe POST cast**: `list_by_ids([cat_mare.id, cat_mare.id])` → `{:ok, [una_sola_category]}`. `list_by_ids(["#{cat_mare.id}", cat_mare.id])` → idem (una sola).
9. **`list_by_ids/1` empty input**: `list_by_ids([])` → `{:ok, []}`.

**GREEN**:
```elixir
def list_categories do
  Repo.all(from c in Category, order_by: [asc: c.display_order])
end

def list_by_ids(raw_ids) when is_list(raw_ids) do
  with {:ok, ints} <- safe_cast_ints(raw_ids) do
    unique = Enum.uniq(ints)
    cats = Repo.all(from c in Category, where: c.id in ^unique)
    if length(cats) == length(unique), do: {:ok, cats}, else: {:error, :not_found}
  end
end

defp safe_cast_ints(raw) do
  Enum.reduce_while(raw, {:ok, []}, fn
    n, {:ok, acc} when is_integer(n) and n > 0 -> {:cont, {:ok, [n | acc]}}
    s, {:ok, acc} when is_binary(s) ->
      case Integer.parse(s) do
        {n, ""} when n > 0 -> {:cont, {:ok, [n | acc]}}
        _ -> {:halt, {:error, :not_found}}
      end
    _, _ -> {:halt, {:error, :not_found}}
  end)
  |> case do
    {:ok, list} -> {:ok, Enum.reverse(list)}
    err -> err
  end
end
```

**REFACTOR**: docstring + `@spec`.
**Files**: `lib/ideajar/categories.ex`, `test/ideajar/categories_test.exs`.
**Spec mapping**: F1 (list_categories), foundational per S2/S3.

### Step 4a: Wipe migration per slice-2 dev data

**Complexity**: standard (migration distruttiva ma circoscritta)
**RED** (`test/ideajar/categories/wipe_migration_test.exs`):
1. Setup: insert 2 idee dummy via Repo (`%Idea{title: "x"}`, etc.) — bypassa changeset di slice 3 perché il join non esiste ancora in questo step.
2. `Ecto.Migrator.up/4` per la wipe migration → `SELECT COUNT(*) FROM ideas` ritorna 0; `SELECT COUNT(*) FROM categories` ritorna 8 (intatte da Step 2).
3. Re-eseguire la wipe → no exception.

**GREEN**:
- Migration `wipe_slice2_dev_ideas` con `up/0` = `execute("DELETE FROM ideas")`, `down/0` = `:ok` (irreversibile by design). Commento esplicito sul rationale (vedi A8).

**REFACTOR**: nessuno.
**Files**: `priv/repo/migrations/<ts>_wipe_slice2_dev_ideas.exs`, `test/ideajar/categories/wipe_migration_test.exs`.
**Spec mapping**: A8 (preparazione per Step 4b).

### Step 4b: idea_categories join + Idea many_to_many association

**Complexity**: complex (cross-context schema, FK semantics CASCADE/RESTRICT/UNIQUE)
**RED** (estensione `idea_test.exs` + nuovo `test/ideajar/ideas/idea_categories_constraint_test.exs`):
1. `Idea.__schema__(:associations)` contiene `:categories` (many_to_many).
2. Insert idea con 2 categorie via `Ecto.Changeset.put_assoc/3` su un changeset minimale → persiste; `Repo.preload(:categories)` ritorna 2 `%Category{}` ordinate per display_order.
3. **CASCADE su idea_id (O4)**: insert idea + 2 categorie → `Repo.delete!(idea)` → query SQLite `SELECT COUNT(*) FROM idea_categories WHERE idea_id = ?` ritorna 0; `categories` ancora 8 righe.
4. **RESTRICT su category_id (O5)**: insert idea + 1 categoria → `Repo.delete!(category)` → `assert_raise Ecto.ConstraintError, ~r/foreign key|FOREIGN KEY|RESTRICT|constraint/i, fn -> ... end`.
5. **UNIQUE PK (O6)**: insert idea + categoria mare via put_assoc → `Repo.insert_all(:idea_categories, [%{idea_id: idea.id, category_id: cat_mare.id}])` → `assert_raise Postgrex.Error / Exqlite.Error / Ecto.ConstraintError, ~r/unique|UNIQUE|primary key/i`.
6. **Wipe pin**: pre-condizione setup verifica che categories abbia 8 righe; post-Step-4b migrate, ideas table è vuoto e categories ancora 8 (regression contro destruction-of-wrong-table).
7. **Migration round-trip**: up/down/up, niente exception.

**GREEN**:
- Migration `create_idea_categories` con `change/0`:
  ```elixir
  create table(:idea_categories, primary_key: false) do
    add :idea_id, references(:ideas, on_delete: :delete_all), null: false, primary_key: true
    add :category_id, references(:categories, on_delete: :restrict), null: false, primary_key: true
  end
  ```
- Estendere `Ideajar.Ideas.Idea` con `many_to_many :categories, Ideajar.Categories.Category, join_through: "idea_categories"` (NESSUN `on_replace` — drop A3 iter 2; default `:raise` è la scelta esplicita).

**REFACTOR**: nessuno.
**Files**: `priv/repo/migrations/<ts>_create_idea_categories.exs`, `lib/ideajar/ideas/idea.ex` (extend), `test/ideajar/ideas/idea_test.exs`, `test/ideajar/ideas/idea_categories_constraint_test.exs`.
**Spec mapping**: O2, O4, O5, O6; preparazione per F2/F3/F4.

### Step 5: Idea changeset put_assoc + validate_length min: 1

**Complexity**: complex (gotcha ordering: validate_length deve girare DOPO put_assoc; touching slice-2 callers)
**RED** (estensione `idea_test.exs`, stringhe canoniche):
1. `Idea.changeset(%Idea{}, %{title: "x", categories: [c1]})` → valid? = true.
2. `Idea.changeset(%Idea{}, %{title: "x"})` (chiave assente) → invalid, `errors[:categories]` esattamente `Seleziona almeno una categoria`. Asserto: `length(Keyword.get_values(cs.errors, :categories)) == 1`.
3. `Idea.changeset(%Idea{}, %{title: "x", categories: []})` → idem.
4. `Idea.changeset(%Idea{}, %{title: "x", categories: [c1, c2]})` con 2 categorie persistite → valid, `cs.changes[:categories]` ha 2 elementi.
5. **Slice-2 LV regression**: `live(conn, "/")` con session valida → `{:ok, view, html}` senza raise; `html =~ "+ Aggiungi idea"`; `:sys.get_state(view.pid).socket.assigns.form` è `%Phoenix.HTML.Form{}` non-nil; `form_visible? == false`. La changeset interna del form vuoto è invalid (manca title E categories) ma non rendera errori finché form_visible? == false.
6. **Ordering pin (R1)**: helper privato `validate_categories_present/1` incapsula `validate_length(:categories, min: 1, ...)`. Test che la chiamata diretta (in ordine inverso: validate_length PRIMA di put_assoc) sull'API privata produrrebbe il bug → questo test è esplicitamente skippato con `@tag :doc_only` ma resta come documentazione del gotcha.

**GREEN**:
```elixir
def changeset(%__MODULE__{} = idea, attrs) do
  idea
  |> cast(attrs, [:title, :description, :url])
  |> trim_text(:title)
  |> trim_text(:url)
  |> validate_required([:title], message: @title_required)
  |> validate_length(:title, max: 200, message: @title_too_long)
  |> validate_length(:url, max: 2000, message: @url_too_long)
  |> validate_url(:url)
  |> put_categories(attrs)
  |> validate_categories_present()
end

defp put_categories(cs, %{categories: cats}) when is_list(cats), do: put_assoc(cs, :categories, cats)
defp put_categories(cs, %{"categories" => cats}) when is_list(cats), do: put_assoc(cs, :categories, cats)
defp put_categories(cs, _attrs), do: cs

defp validate_categories_present(cs), do: validate_length(cs, :categories, min: 1, message: @categories_required)
```

**REFACTOR**: aggiungere `@categories_required "Seleziona almeno una categoria"`.
**Files**: `lib/ideajar/ideas/idea.ex` (extend), `test/ideajar/ideas/idea_test.exs` (extend).
**Spec mapping**: F2 (parte changeset), parte di F3.

### Step 6: Ideas.create_idea + Ideas.list_ideas extensions (Categories context boundary)

**Complexity**: complex (impure boundary, single-error path discipline)
**RED** (`test/ideajar/ideas_test.exs` estensione):
1. **F3** — `Ideas.create_idea(%{title: "x", category_ids: [c1.id]})` → `{:ok, %Idea{categories: [%Category{id: id1}]}}`.
2. **F2 lista vuota** — `Ideas.create_idea(%{title: "x", category_ids: []})` → `{:error, cs}`, `errors[:categories]` esattamente `Seleziona almeno una categoria`, **una sola entry**.
3. **F2 chiave assente** — stesso errore.
4. **S2 hostile inputs** — per ognuno di `[999_999]`, `[-1]`, `[0]`, `["abc"]`, `[""]`, `[nil]`, `[1.5]`, `[valid_id, 999_999]` → `{:error, cs}` con `errors[:categories]` esattamente `Categoria non valida`, **una sola entry**, no exception, no row in `ideas`/`idea_categories`.
5. **S3 dedupe** — `[c1.id, c1.id, c2.id]` → 2 categorie distinte. `[c1.id, c1.id, c1.id]` → 1 categoria, idea creata. `["#{c1.id}", c1.id]` → 1 categoria distinta.
6. **F4** — Inserire 2 idee in successione. `Ideas.list_ideas/0` ritorna entrambe; per ogni idea `:categories` preloaded ordinato per display_order. **Outer ordering invariato**: `hd(list_ideas).id == ultima_inserita.id` (regression slice 2 inserted_at DESC).
7. **F8 recovery** — chiama `create_idea` con `%{title: "Sirolo", url: "https://example.com", category_ids: []}` → `{:error, cs}`. Rispatchare con `category_ids: [c1.id]` mantiene title e url originali (verificato sui changes del cs valid risultante).
8. **No partial commit**: con `category_ids: [valid_id, 999_999]` verificare che **dopo** l'errore: `Repo.aggregate(Idea, :count) == 0` e `Repo.aggregate("idea_categories", :count) == 0`.

**GREEN**:
```elixir
def create_idea(attrs) when is_map(attrs) do
  raw_ids = fetch_raw_ids(attrs)

  case Categories.list_by_ids(raw_ids) do
    {:ok, cats} ->
      attrs_with_cats = Map.put(attrs, :categories, cats)
      %Idea{}
      |> Idea.changeset(attrs_with_cats)
      |> Repo.insert()
      |> case do
        {:ok, idea} -> {:ok, Repo.preload(idea, categories: from(c in Categories.Category, order_by: [asc: c.display_order]))}
        err -> err
      end

    {:error, :not_found} ->
      cs =
        %Idea{}
        |> Ecto.Changeset.cast(attrs, [:title, :description, :url])
        |> Ecto.Changeset.add_error(:categories, "Categoria non valida")

      {:error, cs}
  end
end

defp fetch_raw_ids(attrs), do: Map.get(attrs, "category_ids") || Map.get(attrs, :category_ids) || []

def list_ideas do
  Repo.all(from i in Idea, order_by: [desc: i.inserted_at, desc: i.id])
  |> Repo.preload(categories: from(c in Categories.Category, order_by: [asc: c.display_order]))
end
```

> Nota A11: `Ideas` chiama `Categories.list_by_ids/1` — non legge la table direttamente. Niente `from c in Category` in `lib/ideajar/ideas.ex` salvo per il preload (che resta in `Categories.Category` namespace ma è una preload query, non un boundary di lettura).

**REFACTOR**: estrarre `categories_preload_query/0` private helper.
**Files**: `lib/ideajar/ideas.ex` (extend), `test/ideajar/ideas_test.exs` (extend).
**Spec mapping**: F2, F3, F4, F8, S2, S3.

### Step 7: LiveView mount preload + chip rendering + toggle handler

**Complexity**: complex (LV state across handlers, fieldset+legend+helper a11y, non-color cue, new fixtures module)
**RED** (estensione `test/ideajar_web/live/idea_live/index_test.exs` + nuovo `test/support/fixtures/categories_fixtures.ex`):
1. **Setup**: `seed_canonical_categories!/0` da `categories_fixtures.ex` inserisce le 8 via `Repo.insert_all` (NON tramite migration nei test).
2. **Mount con seed** — `live_isolated/3` con session valida → `view.assigns.categories` è la lista delle 8 ordinate, `view.assigns.selected_category_ids == MapSet.new()`.
3. **Form aperto rendera fieldset + legend "Categorie *" + helper text**: `render_click(view, "toggle_form")` → html contiene `<fieldset>`, `<legend>Categorie *</legend>` (esatto), helper `Scegli almeno una categoria`, 8 `<button type="button" aria-pressed="false" data-selected="false" phx-click="toggle_category" phx-value-id="…" id="category-chip-N">{name}</button>` dove N = display_order.
4. **Non-color cue (A5)**: ogni chip `aria-pressed="true"` contiene il sotto-elemento `<.icon name="hero-check" />` (assertable via `html =~ ~s(class="hero-check)`); ogni chip `aria-pressed="false"` NON lo contiene. `data-selected="true"` su chip selezionati, `data-selected="false"` su deselezionati.
5. **Toggle aria-pressed e data-selected**: `render_click(view, "toggle_category", %{"id" => "#{c_mare.id}"})` → chip "mare" con `aria-pressed="true"` e `data-selected="true"` e icona check; gli altri 7 con `aria-pressed="false"`. `view.assigns.selected_category_ids == MapSet.new([c_mare.id])`.
6. **Toggle off**: secondo click sullo stesso chip → `aria-pressed="false"`, `data-selected="false"`, MapSet vuoto.
7. **Multi-select**: 3 toggle distinti → 3 chip pressed, MapSet con 3 id.
8. **Hit area / a11y class names** (indirect check; reale 44×44 verificato in V1b): ogni chip ha class string contenente `min-h-11 min-w-11`. **Nota**: questo test asserta i class names tailwind, non la geometria reale; V1b manuale verifica i 44 px.
9. **F6 reset on close**: toggle 1 chip → render_click "close_form" → render_click "toggle_form" → MapSet vuoto, html senza `aria-pressed="true"` né `data-selected="true"`.

**GREEN**:
- Mount: `assign(socket, :categories, Categories.list_categories())`, `assign(socket, :selected_category_ids, MapSet.new())`.
- `handle_event("toggle_category", %{"id" => id_str}, socket)` toggle nel MapSet (parse safe; id non-int rimane no-op silenzioso, non assert critico per slice 3 dato A13).
- `handle_event("toggle_form", ...)` aggiunge reset MapSet.
- `handle_event("close_form", ...)` aggiunge reset MapSet.
- Nuovo function component `IdeajarWeb.Components.CategoryChip` in `lib/ideajar_web/components/category_chip.ex`. Renderizza `<button>` con icon condizionale e `data-selected`.
- Template `idea_live/index.html.heex`: `<fieldset class="…"><legend>Categorie *</legend><p class="text-sm text-base-content/70">Scegli almeno una categoria</p><div class="flex flex-wrap gap-2"><.category_chip :for={c <- @categories} … /></div></fieldset>`.
- `test/support/fixtures/categories_fixtures.ex`: `seed_canonical_categories!/0` + `category_fixture/1`.

**REFACTOR**: nessuno.
**Files**: `lib/ideajar_web/live/idea_live/index.ex` (extend), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `lib/ideajar_web/components/category_chip.ex` (new), `test/ideajar_web/live/idea_live/index_test.exs` (extend), `test/support/fixtures/categories_fixtures.ex` (new).
**Spec mapping**: chip rendering scenarios, F5, F6, A5, A11, A12.

### Step 8: Save flow + idea card render + error focus on legend region

**Complexity**: complex (cross-cutting: save handler + error rendering + focus push to error region + idea card render + reset + recovery)
**RED** (estensione `idea_live/index_test.exs`):
1. **Happy path** — open form, fill title="Mare a Sirolo", toggle "mare" + "viaggio", submit → idea persistita; html contiene badges con testi "mare" e "viaggio" (mare display_order=2, viaggio=8 → "mare" prima nel DOM). `assert_push_event(view, "ideajar:focus", %{to: "#add-idea-button"})`. Flash "Idea aggiunta".
2. **F7** — Dopo save success, re-open form → MapSet vuoto, no `aria-pressed="true"`, no `data-selected="true"`.
3. **No category error → focus su error region (A6)** — open form, fill title only, submit → html contiene `<p id="idea-categories-error" role="alert" tabindex="-1">Seleziona almeno una categoria</p>`. `assert_push_event(view, "ideajar:focus", %{to: "#idea-categories-error"})`. Form ancora visibile. Fieldset ha `aria-describedby="idea-categories-error"` quando error presente.
4. **Errors accumulate, focus on title (priority)** — submit con title vuoto + url ftp + no category → html contiene tutti e 3 gli error. `assert_push_event(view, "ideajar:focus", %{to: "#idea-title"})` — title ha priorità superiore a categories.
5. **F8 recovery** — fill title="Sirolo" + url="https://example.com", submit con no chip → error. Toggle chip "mare" e re-submit → idea creata; verificare via `Repo.preload` che title="Sirolo" e url="https://example.com" (no re-typing).
6. **Toggle then untoggle** — toggle "mare" → toggle "mare" → submit con title="x" → error "Seleziona almeno una categoria".
7. **Tutte le 8 categorie** — toggle 8 chip → submit con title="x" → idea creata, html del card contiene tutti gli 8 badge in display_order.
8. **Card badge visual descended** — il badge nel card (rendered) usa lo stesso CSS pill family dei chip ma senza border (deselected family). Asserta classe css `category-badge` (definita in app.css o tailwind utility) presente sul li/span.
9. **Invalid id (S2 LV path)** — simulare submit con `category_ids: [999_999]` (via send/assigns manipulation o evento sintetico) → html contiene "Categoria non valida" associato al fieldset; idea NON persistita.

**GREEN**:
- `handle_event("save", %{"idea" => attrs}, socket)`: aggiungere `category_ids = MapSet.to_list(socket.assigns.selected_category_ids)`, costruire `attrs_with_ids = Map.put(attrs, "category_ids", category_ids)`, chiamare `Ideas.create_idea(attrs_with_ids)`.
- Su `{:ok, _idea}`: aggiungere `assign(socket, :selected_category_ids, MapSet.new())` e gli altri reset di slice 2.
- Su `{:error, changeset}`: estendere `focus_first_invalid/1` con priorità `:title → :categories → :url → :description`. Per `:categories` → `"#idea-categories-error"`.
- Idea card template: blocco `<ul :if={idea.categories != []} class="flex flex-wrap gap-2 mt-2"><li :for={cat <- idea.categories} class="category-badge">{cat.name}</li></ul>` dopo description e link.
- Template fieldset: aggiungere `aria-describedby={if has_error?(@form, :categories), do: "idea-categories-error"}` + `<p :if={…} id="idea-categories-error" role="alert" tabindex="-1">Seleziona almeno una categoria</p>` (o "Categoria non valida").
- Helper `has_error?/2` private nel LV per il conditional aria-describedby.

**REFACTOR**: estrarre `category_error_message/1` se la logica è duplicata.
**Files**: `lib/ideajar_web/live/idea_live/index.ex` (extend), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `assets/css/app.css` (add `.category-badge` style se necessario), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: F1 happy path, F7, F8, S2 (LV), submit validation scenarios, A6, A8 (visual descended).

### Step 9: Out-of-scope guard + auth boundary + docs sync + spec sync

**Complexity**: standard
**RED**:
1. **Out-of-scope guard (LiveView)** — `live(conn, "/")` autenticato + open form → html non matcha `~r/(Aggiungi|Modifica|Elimina|Gestisci) categori[ae]/i` e nessun elemento ha `phx-click` matching `~r/categor/` salvo `phx-click="toggle_category"` (esplicitamente whitelist).
2. **Out-of-scope guard (module API)** — `Ideajar.Categories.__info__(:functions)` contiene solo `:list_categories/0` e `:list_by_ids/1` (nessun `:create_category`, `:update_category`, `:delete_category` arity-anything).
3. **S4 auth boundary** — `live_isolated(conn, IdeajarWeb.IdeaLive.Index, session: %{})` → `{:error, {:redirect, %{to: "/login?return_to=%2F"}}}`. Stessa cosa con `session: %{"authenticated" => false}`. Verifica che il redirect avviene anche se `toggle_category` è dichiarato handle_event (cioè il modulo continua a montare con redirect, non crasha).
4. **D1 — UI copy table** — `docs/conventions.md` contiene tutte e 12 le stringhe della UI copy table di slice 3 (legend con asterisco, helper, errori, 8 nomi).
5. **D2 — Spec sync** — `docs/specs/categories-on-ideas.md` contiene la versione iter-2 del Gherkin block: scenari con focus pin esplicito, scenario outline hostile inputs, scenario `Manually re-invoking the seed-categories migration up/0 is a no-op` (NON il vecchio "mix ecto.migrate"), scenario `Ideajar.Categories module exposes only list_categories/0 and list_by_ids/1`. Test minimo: `File.read!(...) =~ "Manually re-invoking"` e **non** contiene `"running mix ecto.migrate"`.

**GREEN**:
- Estendere `docs/conventions.md` con tabella slice 3.
- Riscrivere `docs/specs/categories-on-ideas.md` Gherkin block con la versione iter 2 (in sync con plan iter 2).

**REFACTOR**: nessuno.
**Files**: `docs/conventions.md` (extend), `docs/specs/categories-on-ideas.md` (rewrite Gherkin), `test/ideajar/docs_test.exs` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: D1, D2, S4, out-of-scope guards.

## Complexity Classification

| Step | Complessità | Motivazione |
|------|-------------|-------------|
| 1 | standard | Schema + table con 2 UNIQUE constraints |
| 2 | standard | Seed migration con on_conflict |
| 3 | standard | Context con list_categories + list_by_ids (parsing safe + dedupe POST cast) |
| 4a | standard | Migration distruttiva circoscritta, raw SQL |
| 4b | **complex** | Join table cross-context + CASCADE/RESTRICT/UNIQUE, schema many_to_many |
| 5 | **complex** | Changeset gotcha (validate_length DOPO put_assoc), tocca slice-2 callers |
| 6 | **complex** | Boundary impuro, dedupe POST int cast, single-error path discipline |
| 7 | **complex** | LV state cross-handler + fieldset/legend/helper a11y + non-color cue + chip component + fixtures module |
| 8 | **complex** | Save+render+focus+reset+recovery+S2-LV-path; error focus su region invece di chip |
| 9 | standard | Guards + docs/spec sync |

## Pre-PR Quality Gate

- [ ] `mix test --include migration` passa.
- [ ] `mix format --check-formatted` passa.
- [ ] `mix credo` passa.
- [ ] `mix deps.audit` passa.
- [ ] `mix compile --warnings-as-errors` passa.
- [ ] `/code-review` su file toccati passa.
- [ ] **F1 traceability**: ogni `Scenario:` Gherkin (escluso V1/V1a/V1b/V1c) ha almeno un test ExUnit/LiveViewTest che lo cita per nome (`# Scenario: …` sopra il `test`).
- [ ] **V1**: 4 screenshot in `docs/screenshots/slice-3/` (incluso 360px Pixel 4a).
- [ ] **V1a**: Lighthouse a11y mobile ≥95 mediana di 3 run — JSON allegati.
- [ ] **V1b**: walkthrough keyboard-only verificato secondo i 7 step.
- [ ] CI verde sul push.

## Risks & Open Questions

- **R1 — `validate_length(:categories, min: 1)` su put_assoc**: la `validate_length` su un'associazione many_to_many funziona solo DOPO `put_assoc` perché Ecto popola `cs.changes[:categories]` con la lista. Step 5 incapsula in `validate_categories_present/1` privata e l'ordine è deliberato; un futuro refactor che inverte l'ordine fallirebbe i test #2/#3 di Step 5. R1 chiuso da incapsulamento.
- **R2 — DataCase + seed categories**: chiuso da A12 (modulo fixture dedicato `categories_fixtures.ex`).
- **R3 — Slice-2 LV form vuoto rotto**: pinato da test #5 di Step 5. La changeset è invalid ma non viene rendered finché `form_visible? == false`.
- **R4 — `on_replace: :delete`**: chiuso da A3 iter 2 (drop, default `:raise` forza decisione esplicita in slice edit).
- **R5 — SQLite `INSERT ... ON CONFLICT DO NOTHING`**: SQLite 3.24+ (2018) supportato; `ecto_sqlite3` lo emette correttamente. Pinato da test #2 di Step 2.
- **R6 — Migration di Step 4a wipa idee dev locali**: accettato. Il commit message di Step 4a esplicita il rationale; in prod la migration viene eseguita su DB ancora vuoto (slice 9 deploy non è ancora avvenuto). Guard `Mix.env()` esplicitamente NON applicato (vedi A8: il guard sarebbe paranoia per l'ambiente single-developer attuale).
- **R7 — Chip a11y senza roving tabindex**: 8 button consecutivi nel tab order. Per 8 voci accettabile (slice 4 con filtri sarà la chiave per scoping); per 30+ andrebbe rivisto. Decisione consapevole. V1b verifica esplicitamente assenza di focus trap.
- **R8 — Cap massimo categorie selezionate**: nessuno (D4 utente). Multi-select 8/8 è uno scenario testato (Step 8 RED #7).
- **R9 — Race condition: categoria deleta tra resolve e insert**: out of scope per slice 3. Per 2 utenti senza UI di delete categoria, lo scenario richiede manipulation DB direct via console — accetabile. Lo scenario **non è coperto** dai test e nessun guard transazionale è applicato.
- **R10 — XSS regression test (S1)**: insert via Repo direct di una categoria con name HTML-like; verifica positiva (escaped) E negativa (literal assente). Categoria rimossa dal DB nel teardown sandbox.
- **R11 *(nuova iter 2)* — Visual contract chip**: la decisione A5 (icona check + data-selected come cue indipendenti dal colore) richiede un'icona Heroicons disponibile in `core_components.ex`. Verificato che `<.icon name="hero-check" />` è già disponibile (slice 1 lo usa). Niente nuovo asset.
- **R12 *(nuova iter 2)* — Helper text ridondante con asterisco?**: Il legend `Categorie *` + helper `Scegli almeno una categoria` è deliberatamente ridondante per coprire diversi modelli di lettura (asterisco è convenzione web, helper è prosa naturale). Non semplificare a uno solo: l'asterisco da solo è opaco per non-techies, l'helper da solo non si vede al primo sguardo.

## Plan Review Summary (iter 2)

> Iter 1 reviewers: acceptance + design + UX = needs-revision; strategic = approve.
> Iter 2 incorpora tutti i blocker e i warning ad alto leverage.

### Modifiche di iter 2 rispetto a iter 1

**Acceptance fixes:**
- S2 hostile inputs esteso a 8 casi enumerati (era solo `[999_999]`); test esplicito che nessun caso solleva eccezione.
- S3 dedupe ordering pin: cast int PRIMA di Enum.uniq (era il contrario, bug silente su `["1", 1]`).
- O3 wording riformulato: "manualmente invocare up/0" invece di "mix ecto.migrate" (che è no-op a livello migrator).
- F4 outer ordering invariante esplicitato.
- F5/F6 phrasing spostato da `view.assigns` a osservabile aria-pressed/data-selected.
- F8 nuovo (recovery preserva input non-categories).
- S4 nuovo (auth boundary).
- O6 nuovo (UNIQUE PK su idea_categories).
- Errors-accumulate scenario pinna `#idea-title` come focus target.
- V1a deterministico (3 run mediana, chip set fissato).

**Design fixes:**
- A11 nuovo: `Categories.list_by_ids/1` come boundary; `Ideas` non legge più `Category` schema direttamente.
- A10 rivista: invalid-id path costruisce changeset minimale (cast solo title/desc/url), niente `Idea.changeset` → niente doppio errore su `:categories`. Pinato da test #2/#4 di Step 6 (`length(Keyword.get_values(...)) == 1`).
- A8 rivista: wipe migration dedicata (`wipe_slice2_dev_ideas`) separata da `create_idea_categories`. Raw SQL `execute("DELETE FROM ideas")` indipendente da future rinomine.
- A12 nuovo: fixtures in modulo dedicato, niente DataCase pollution.
- A3 rivista: drop `on_replace: :delete` (premature, default `:raise` migliore).
- Step 4 splittato in 4a (wipe) + 4b (join).

**UX fixes:**
- A5 esteso con visual contract: icona check + data-selected come 2 cue indipendenti dal colore (WCAG 1.4.11). Pinato da test #4 di Step 7.
- Legend con asterisco `Categorie *` + helper text `Scegli almeno una categoria` (UX warning iter 1: required indicator mancante).
- A6 rivista: focus push su `#idea-categories-error` (region con role=alert tabindex=-1) invece di `#category-chip-1`. SR annuncia errore prima.
- F8 nuovo: scenario di recovery esplicito.
- 360px Pixel 4a aggiunto al V1 (mobile chip wrap behaviour).

**Strategic fixes:**
- Step 8 NON splittato (warning iter 1): le 9 RED tests sono tutte legate dal save→render→focus chain, splittare creerebbe 3 step con setup duplicato. Decisione consapevole. La complessità è gestita dai sub-test enumerati.
- Mix.env guard sulla wipe migration NON applicato (warning iter 1): paranoia per il contesto attuale single-developer.
- "Defer min:1 a slice 4" (warning iter 1): rifiutato — utente ha esplicitamente scelto "almeno una categoria obbligatoria".
- Card badge render NON deferito a slice 4: l'utente vuole il feedback visivo ora.

### Warning iter 1 ancora aperti (tracciati per `/build`)

- **Acceptance V1a (Lighthouse jitter)**: gestito con mediana di 3 run.
- **Acceptance V1b "spot check" → step esplicito**: V1b step 5 ora è esplicito sul focus push e sull'annuncio SR.
- **Design "Step 8 piles 6 concerns"**: accettato as-is con sub-tests enumerati.
- **UX "Categoria non valida dead-end"**: warning aperto. Per slice 3 mostra solo il messaggio nel fieldset; recovery action ("Ricarica le categorie") deferita a slice future quando il rischio sarà reale (oggi è solo via DevTools tampering).
- **UX "SR live-region announcement on toggle"**: deferito a V1b verifica manuale; aria-pressed flip è sufficiente per la maggior parte dei SR moderni.

### Net assessment

Plan iter 2 è **implementation-ready** per il ri-review di iter 2. Tutti i blocker chiusi; warning a basso leverage tracciati ma non implementati.

## Plan Review Summary (iter 2 — final verdicts)

> **Verdetti finali**: acceptance approve, design approve, UX approve, strategic approve (già da iter 1).
> Plan è ready for `/build`. Le warning sotto sono refinement implementation-time, non blocker strutturali.

### Warning superstiti da tracciare durante implementation

**Acceptance (4 → tutti minor):**
- W1 — F4 outer ordering: il test `hd(list_ideas).id == ultima_inserita.id` può essere flaky se due insert in 1 secondo condividono `inserted_at`. Aggiungere durante /build un sub-test che forza stesso `inserted_at` via `Repo.update_all` per pin del tiebreaker `id DESC`.
- W2 — Step 8 RED #9 (S2 LV path) meccanismo vago: in normal flow solo id validi entrano nel MapSet (chips render solo le 8 seedate). Drop il test o pinnare via `:sys.replace_state` durante /build.
- W3 — F8 recovery: aggiungere assertion intermedia che dopo il primo failed submit, il render contiene ancora `value="Sirolo"` e `value="https://example.com"` (pin che `@form` data sopravvive l'error path).
- W4 — Step 1 RED #5 schema fields equality è order-dependent su Ecto internals; sostituire con `MapSet.new(...) == MapSet.new(...)` durante /build.
- W5 — Step 4b RED #5 `assert_raise Postgrex/Exqlite/Ecto.ConstraintError` slash-list: pinare a `Exqlite.Error` (stack è SQLite).
- W6 — Step 5 RED #6 `:doc_only` skipped test: sostituire con commento in `idea.ex`.
- W7 — Step 9 RED #5 spec sync test: estendere assertion a presenza dei nuovi scenari (Outline hostile inputs, Mixed-type duplicates, Unauthenticated mount, PRIMARY KEY).
- W8 — Step 7 GREEN `toggle_category` no-op silenzioso su id non-int: aggiungere RED test esplicito per pinare il comportamento.

**Design (3 → tutti minor):**
- W9 — Residual schema reference: `Ideas.list_ideas/0` e `Ideas.create_idea/1` usano ancora `from c in Categories.Category, order_by: [...]` per il preload. Considerare `Categories.preload_query/0` per spostare il knowledge in Categories context. Se non fatto in slice 3, traccia per slice 4.
- W10 — String vs atom keys nel error path: aggiungere Step 6 RED esplicito che `create_idea(%{"title" => ..., "category_ids" => [bad]})` (string keys, mirroring LV) preserva i changes su `:title`/`:url`.
- W11 — Step 8 shotgun-surgery accettata: durante implementation estrarre `focus_first_invalid/1` e `category_error_message/1` come helper privati nominati per localizzare future modifiche.

**UX (2 → tutti minor):**
- W12 — Legend `Categorie *` SR-friendly: aggiungere `<span aria-hidden="true">*</span><span class="sr-only"> obbligatorio</span>` o `aria-describedby="idea-categories-help"` sul fieldset. Pinare in Step 7 RED #3.
- W13 — `aria-describedby` permanente sul fieldset (non solo on error): puntare a `idea-categories-help idea-categories-error` (space-separated) così il helper è sempre associato e l'error si aggiunge quando presente. Pinare in Step 8 RED #3.

**Strategic (0):** già tutti accettati o risolti in iter 1.

### Reviewer observations (preservate per contesto)

- **Acceptance**: i 5 blocker iter 1 sono tutti chiusi con test pin espliciti (S2 con 8 casi enumerati, S3 con cast-before-uniq, O3 con manual up/0, focus su #idea-title, S4 con live_isolated empty session). I criteri O6 (PK constraint) e A11 (boundary list_by_ids) sono ben tracciati.
- **Design**: A11 + A10 + Step 4 split + A12 fixtures + A3 drop on_replace = scelte canoniche che chiudono tutti i blocker iter 1. Domain/web boundary rispettato; out-of-scope guard al module API level (Step 9 RED #2) è una regression test rara e di valore.
- **UX**: visual contract A5 (icona + data-selected + contrasti) chiude WCAG 1.4.11; pivot a focus su error region (A6) è il pattern WAI-ARIA APG corretto; V1b 7-step esplicito è raro vedere a plan time. F8 recovery chiude il più realistico failure path.
- **Strategic**: scope discipline mantenuta; out-of-scope tight (filtri slice 4, search slice 8, badge colorati, CRUD UI); ogni step rimane committable on trunk.

### Net assessment iter 2

Plan è **implementation-ready** per `/build`. Le warning di iter 2 sono tutte di livello implementation-time (test brittleness, helper extraction, SR refinement) — nessuna richiede revisione strutturale prima di iniziare.
