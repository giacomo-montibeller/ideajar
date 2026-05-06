# Plan: Emoji per ogni categoria sui chip

**Created**: 2026-05-06
**Branch**: main
**Status**: approved (2026-05-06)

## Goal

Arricchire la rappresentazione visiva delle categorie con un'emoji prefisso al nome — formato `<emoji> <name>` — sui due chip (`category_chip/1` del form add/edit e `filter_chip/1` della filter row) **e sui badge** delle card idea, per coerenza visiva end-to-end. L'emoji è una proprietà persistente della categoria, vivendo come nuova colonna `emoji` (TEXT NOT NULL) sullo schema `Ideajar.Categories.Category`, popolata sulle 8 righe canoniche da una migration di backfill. Single source of truth: il DB. Nessuna modifica al protocollo di eventi (`toggle_category`, `cycle_filter`) né al contratto ARIA dei chip.

## Acceptance Criteria

- [ ] **F1** — `Ideajar.Categories.Category` ha il campo `:emoji` (string) e `Ideajar.Categories.list_categories/0` ritorna le 8 categorie con emoji canonica popolata: `passeggiata→🚶`, `mare→🏖️`, `museo→🏛️`, `ristorante→🍽️`, `sport→⚽`, `cultura→🎭`, `cinema→🎬`, `viaggio→✈️`.
- [ ] **F2** — Migration up→down→up round-trip riporta lo schema esattamente allo stato target con emoji corrette.
- [ ] **F3** — `Repo.insert(%Category{name: "x", display_order: 999, emoji: nil})` solleva un errore `NOT NULL` (constraint a livello DB).
- [ ] **U1** — `category_chip/1` renderizza `{@emoji} {@name}` (con il check icon esistente quando `selected?`); l'attr `emoji` è required.
- [ ] **U2** — `filter_chip/1` renderizza `{@emoji} {@name}` mantenendo invariato `aria-label` (NON contiene emoji), preservando le tre varianti `:off`/`:optional`/`:required` con i loro icon.
- [ ] **U3** — La pagina home con form aperto mostra le 8 categorie con prefisso emoji, e la filter row idem.
- [ ] **U4** — I badge categoria sulle card delle idee (`<li class="category-badge">`) renderizzano `<emoji> <name>` per coerenza visiva con i chip; lo `<ul aria-label="Categorie">` resta invariato.
- [ ] **D1** — `docs/conventions.md` (UI copy) e `docs/specs/categories-on-ideas.md` aggiornati con la mappa nome→emoji canonica, marcata come single source of truth nello schema/seed.
- [ ] **A1** — Nessuna regressione sui test esistenti per chip/LiveView (assertion testuali aggiornate per accettare il prefisso emoji dove necessario).
- [ ] **A2** — Contratti ARIA preservati: `aria-pressed` sul form chip, `aria-label`/`data-filter-state` sul filter chip, `phx-click` events invariati.
- [ ] **A3** — Le emoji canoniche sono accessibili dai test via una singola costante condivisa (helper in `Ideajar.CategoriesFixtures`) per evitare drift e flake da variation selector inconsistenti.

## User-Facing Behavior

```gherkin
Feature: Le chip categoria mostrano un'emoji prefisso al nome

  Background:
    Given my browser holds a valid signed session cookie
    And the system has the canonical 8 seeded categories with the canonical emoji map:
      | name        | emoji |
      | passeggiata | 🚶    |
      | mare        | 🏖️    |
      | museo       | 🏛️    |
      | ristorante  | 🍽️    |
      | sport       | ⚽    |
      | cultura     | 🎭    |
      | cinema      | 🎬    |
      | viaggio     | ✈️    |

  Scenario: Form add-idea — i chip mostrano emoji + nome
    Given I am on "/"
    When I click "+ Aggiungi idea"
    Then the chip for "mare" renders the text "🏖️ mare"
    And the chip preserves type="button" and aria-pressed="false"

  Scenario: Form chip selezionato mostra check + emoji + nome nell'ordine
    Given the add-idea form is expanded
    When I click the "mare" chip
    Then the rendered chip contains the hero-check icon followed by "🏖️ mare"
    And aria-pressed="true"

  Scenario: Filter row — i chip mostrano emoji + nome ma aria-label non contiene emoji
    Given I am on "/"
    Then the filter chip for "mare" renders the text "🏖️ mare"
    And its aria-label is exactly "mare" when state is :off
    And its aria-label is "mare opzionale" when state is :optional
    And its aria-label is "mare obbligatoria" when state is :required

  Scenario: Card idea — i badge categoria mostrano emoji + nome
    Given the workspace has an idea "Mare a Sirolo" tagged "mare" and "viaggio"
    When I visit "/"
    Then the rendered card shows badges in this order: "🏖️ mare", "✈️ viaggio"
    And the surrounding <ul> still has aria-label="Categorie"

  Scenario: Migration backfill — DB esistente con 8 righe ottiene le emoji canoniche
    Given the categories table has 8 rows without emoji
    When the add_emoji_to_categories migration runs
    Then every row has a non-null emoji matching the canonical map
    And subsequent attempts to insert a category with nil emoji fail at the DB level
```

## Steps

### Step 1: Persistere `emoji` sullo schema, popolare le 8 righe canoniche, e fissare la mappa di test

**Complexity**: standard
**RED**:
1. In `test/support/fixtures/categories_fixtures.ex`, esporre una nuova funzione `canonical_emojis/0 :: %{String.t() => String.t()}` che ritorna la mappa nome→emoji come **single source of truth per i test**. Il valore viene assertato dal test seguente, quindi se il seed cambia la mappa diverge subito.
2. In `test/ideajar/categories_test.exs` (o nuovo file dedicato), aggiungere un test che, per ognuno dei nomi canonici (`passeggiata`, `mare`, `museo`, `ristorante`, `sport`, `cultura`, `cinema`, `viaggio`), asserisce che `Categories.list_categories()` ritorna una `%Category{}` con `emoji` esattamente uguale a `CategoriesFixtures.canonical_emojis()[name]`.
3. In `test/ideajar/categories/category_test.exs`, aggiungere un test `rejects a nil emoji with a NOT NULL constraint error` analogo all'esistente per `name`.
4. Aggiornare gli `Repo.insert(%Category{name: ..., display_order: ...})` esistenti in `category_test.exs` per includere un valore di `emoji` (es. `"🧪"`) — altrimenti i test esistenti falliranno una volta aggiunto il vincolo NOT NULL.

**GREEN**:
1. Aggiungere `field :emoji, :string` allo schema in `lib/ideajar/categories/category.ex` (e includerlo in `@type t`).
2. Creare `priv/repo/migrations/<ts>_add_emoji_to_categories.exs` che, in `up/0`:
   - `ALTER TABLE categories ADD COLUMN emoji TEXT` (nullable).
   - `UPDATE categories SET emoji = $1 WHERE name = $2` per ognuna delle 8 coppie nome→emoji (via `Repo.update_all/3` con `from c in "categories", where: c.name == ^name`).
   - `ALTER TABLE categories ALTER COLUMN emoji SET NOT NULL`.
   - In `down/0`: `ALTER TABLE categories DROP COLUMN emoji`.
3. La migration dev'essere idempotente in senso pratico: rieseguendo `up/0` su un DB già migrato, le `update_all` riportano lo stesso valore (no-op effettivo). L'idempotenza forte è gestita da Ecto stesso (le migrations già applicate non rieseguono).
4. Aggiungere `canonical_emojis/0` nel modulo `Ideajar.CategoriesFixtures` — l'unica copia delle stringhe emoji nel codice di test, così le forme con/senza VS16 non drifano fra fixture, assertion sui chip, badges e doc test.

**REFACTOR**: estrarre la mappa nome→emoji in un attribute privato della migration (`@emoji_by_name`) per leggibilità. Niente abstraction layer nel dominio: il dominio legge dal DB, i test leggono dal fixture, la migration la dichiara.

**Files**:
- `lib/ideajar/categories/category.ex`
- `priv/repo/migrations/<ts>_add_emoji_to_categories.exs` (nuovo)
- `test/support/fixtures/categories_fixtures.ex`
- `test/ideajar/categories_test.exs`
- `test/ideajar/categories/category_test.exs`

**Commit**: bozza — *"Add emoji column to categories with canonical backfill"*

---

### Step 2: Render emoji nel `category_chip/1` (form add/edit)

**Complexity**: standard
**RED**: in `test/ideajar_web/components/category_chip_test.exs`, aggiungere/aggiornare i test del form chip:
- Test che asserisce che, dato `emoji: "🏖️"` e `name: "mare"`, l'HTML renderizzato contiene la stringa `🏖️ mare` (assertion strutturale: emoji subito prima del nome, separati da uno spazio).
- Test che asserisce che `aria-pressed` rimane invariato (`"true"` quando `selected?`, `"false"` altrimenti).
- Test che asserisce che, quando `selected?`, l'icona hero-check precede l'emoji (ordine: icon → emoji → name).

**GREEN**:
1. In `lib/ideajar_web/components/category_chip.ex`, aggiungere `attr :emoji, :string, required: true` a `category_chip/1` e renderizzare `{@emoji} {@name}` dopo l'eventuale icona.
2. In `lib/ideajar_web/live/idea_live/index.html.heex`, passare `emoji={category.emoji}` ai `<.category_chip />` (riga ~53–57).
3. Eseguire la suite e aggiornare ogni assertion in `test/ideajar_web/live/idea_live/index_test.exs` che ispeziona il testo dei chip del form (sweep mirato — la maggior parte testa `aria-pressed`/`phx-click`, ma alcune assertion text-based vanno aggiornate per accettare il prefisso emoji).

**REFACTOR**: nessuno necessario (il pattern è simmetrico al resto della famiglia chip).

**Files**:
- `lib/ideajar_web/components/category_chip.ex`
- `lib/ideajar_web/live/idea_live/index.html.heex`
- `test/ideajar_web/components/category_chip_test.exs`
- `test/ideajar_web/live/idea_live/index_test.exs` (sweep)

**Commit**: bozza — *"Render category chip with emoji prefix in the add/edit form"*

---

### Step 3: Render emoji nel `filter_chip/1` (filter row), preservando `aria-label`

**Complexity**: standard
**RED**: in `test/ideajar_web/components/category_chip_test.exs`, aggiungere/aggiornare i test del filter chip:
- Test che asserisce che, dato `emoji: "🏖️"` e `name: "mare"`, l'HTML renderizzato contiene `🏖️ mare`.
- Test che asserisce che `aria-label` è esattamente `"mare"` (state `:off`), `"mare opzionale"` (state `:optional`), `"mare obbligatoria"` (state `:required`) — **nessuna emoji nell'aria-label**.
- Test che asserisce che gli icon di stato (`hero-check` per `:optional`, `hero-lock-closed` per `:required`) precedono l'emoji.

**GREEN**:
1. In `lib/ideajar_web/components/category_chip.ex`, aggiungere `attr :emoji, :string, required: true` a `filter_chip/1` e renderizzare `{@emoji} {@name}` dopo gli eventuali icon. Lasciare `filter_chip_aria_label/2` invariato (usa solo `name`).
2. In `lib/ideajar_web/live/idea_live/index.html.heex`, passare `emoji={category.emoji}` ai `<.filter_chip />` (riga ~203–206).
3. Sweep su `index_test.exs` per le assertion testuali sui filter chip.

**REFACTOR**: nessuno necessario.

**Files**:
- `lib/ideajar_web/components/category_chip.ex`
- `lib/ideajar_web/live/idea_live/index.html.heex`
- `test/ideajar_web/components/category_chip_test.exs`
- `test/ideajar_web/live/idea_live/index_test.exs` (sweep)

**Commit**: bozza — *"Render filter chip with emoji prefix while keeping aria-label clean"*

---

### Step 4: Render emoji nei badge categoria sulle card delle idee

**Complexity**: standard
**RED**: in `test/ideajar_web/live/idea_live/index_test.exs` (o test dedicato sul rendering della card), aggiungere un test che:
- Crea un'idea taggata con due categorie note (es. `mare`, `viaggio`) via fixture.
- Renderizza la home e asserisce che il `<ul data-testid="idea-categories">` contiene due `<li>` con testi esattamente `"🏖️ mare"` e `"✈️ viaggio"` in `display_order`, usando `CategoriesFixtures.canonical_emojis()` per le emoji attese.
- Asserisce che lo `<ul aria-label="Categorie">` resta invariato.

**GREEN**:
1. In `lib/ideajar_web/live/idea_live/index.html.heex`, alla riga ~494 cambiare `{cat.name}` in `{cat.emoji} {cat.name}`.
2. Sweep su altre eventuali assertion testuali in `index_test.exs` che ispezionano i badges (es. test esistenti che cercano `"mare"` come substring tipicamente continuano a passare; quelli che cercano la stringa esatta `"mare"` come testo del `<li>` vanno aggiornati).

**REFACTOR**: nessuno necessario (un solo touch point nel template).

**Files**:
- `lib/ideajar_web/live/idea_live/index.html.heex`
- `test/ideajar_web/live/idea_live/index_test.exs` (e altri test che renderizzano le card, se esistono)

**Commit**: bozza — *"Show emoji prefix on category badges in idea cards"*

---

### Step 5: Aggiornare la documentazione canonica

**Complexity**: trivial
**RED**: in `test/ideajar/docs_test.exs` (esistente — verifica copy canonica), estendere o aggiungere un test che asserisce che `docs/conventions.md` contiene la mappa nome→emoji per tutte le 8 categorie canoniche, leggendo le stringhe attese da `CategoriesFixtures.canonical_emojis()` e i nomi dal seed.

**GREEN**:
1. `docs/conventions.md` — estendere la "UI copy" table (rifsa: `Categoria 1` … `Categoria 8`) con una colonna `Emoji` (o riga aggiuntiva), referenziando lo schema/seed come single source of truth.
2. `docs/specs/categories-on-ideas.md` — aggiungere una breve nota nella sezione "UI copy aggiunta" e nello schema Architecture > Components che il campo `emoji` è parte del contratto categoria a partire da slice 14b (o numero appropriato; lasciare al reviewer la scelta del marker di slice). Aggiungere uno scenario Gherkin breve sul rendering del prefisso `<emoji> <name>` sui chip e sui badge, riferito a questo plan.

**REFACTOR**: nessuno.

**Files**:
- `docs/conventions.md`
- `docs/specs/categories-on-ideas.md`
- `test/ideajar/docs_test.exs`

**Commit**: bozza — *"Document the canonical emoji map across UI copy and slice-3 spec"*

---

## Complexity Classification

Step 1–4 sono `standard`. Step 5 è `trivial` (pura documentazione + un assertion test). Nessuno step è `complex`.

## Pre-PR Quality Gate

- [ ] `mix test` — tutta la suite verde
- [ ] `mix format --check-formatted` — pulito
- [ ] `mix compile --warnings-as-errors` — pulito
- [ ] `mix credo --strict` se in uso (verificare `mix.exs`)
- [ ] `/code-review` sul branch passa
- [ ] Verifica visiva manuale (browser): home con form aperto + filter row aperta — i chip mostrano correttamente le 8 emoji canoniche
- [ ] Documentazione aggiornata se appropriato (vedi Open Questions)

## Risks & Open Questions

**Decisioni prese in approval (2026-05-06)**:
- ✅ **D-OQ1** — Badge sulle card delle idee aggiornati con `<emoji> <name>` per coerenza visiva chip↔badge (step 4).
- ✅ **D-OQ2** — Documentazione (`docs/conventions.md` + `docs/specs/categories-on-ideas.md`) aggiornata con la mappa canonica (step 5).
- ✅ **D-OQ3** — Mappa emoji esposta come `Ideajar.CategoriesFixtures.canonical_emojis/0`, single source of truth per tutti i test (step 1).

**Rischi attivi**:
- **R1 — Test existing inserts**: gli inserts diretti via `Repo.insert(%Category{...})` in `category_test.exs` rompono se la NOT NULL viene introdotta prima di aggiornarli. Mitigazione: lo step 1 fa entrambe le cose nello stesso commit (test + schema + migration).
- **R2 — Postgres `ALTER COLUMN SET NOT NULL` bloccante**: su tabella piccola (8 righe) non è un problema. In produzione la migration è O(8) UPDATE e una ALTER su tabella minuscola: nessun rischio operazionale.
- **R3 — Variation selector drift**: emoji come `🏖️` (U+1F3D6 + U+FE0F) e `✈️` (U+2708 + U+FE0F) hanno forma testo+VS16. Se la stringa nel DB e quella nel fixture differiscono per VS16, le assertion sui chip falliscono in modo confondente. Mitigazione: la migration scrive le stringhe esatte dal `@emoji_by_name`, e `CategoriesFixtures.canonical_emojis/0` espone le **stesse** stringhe; i test non hardcodano emoji inline.

## Self-Review (lightweight)

In sostituzione del dispatch formale dei 4 reviewer (acceptance / design / UX / strategic), date le dimensioni del cambio (5 step, ~5 file di codice + 1 migration + 2 file di doc + sweep test):

- **Acceptance Test Critic**: criteri F1–F3, U1–U4, D1, A1–A3 sono tutti osservabili e direttamente test-abili. Step 1 → F1/F2/F3/A3; step 2 → U1/U3/A2; step 3 → U2/U3/A2; step 4 → U4; step 5 → D1. Il sweep test negli step 2/3/4 copre A1.
- **Design & Architecture Critic**: nessuna nuova astrazione di dominio. Mappa nome→emoji presente in due luoghi *deliberati*: (a) la migration (write side, una tantum), (b) `CategoriesFixtures.canonical_emojis/0` (read side, solo test). Il dominio runtime legge dal DB e non duplica la mappa. I component aggiungono un attr required, fail-fast in compile/test se dimenticato. Pattern simmetrico ai chip esistenti.
- **UX Critic**: emoji + nome aumenta scansionabilità senza rimuovere il testo (a11y mantenuta). `aria-label` del filter chip resta emoji-free per non leggere "🏖️ mare opzionale" a screen reader. I badge sulle card (`<ul aria-label="Categorie">`) mantengono l'aria-label sul container; il prefisso emoji nel `<li>` è puro contenuto visivo. Min hit area 44×44 invariata.
- **Strategic Critic**: scope chiuso, blast radius limitato (slice 3-touch only), rischio basso. Doc-update in step 5 previene drift documentazione/codice. Inclusione dei badge previene incoerenza visiva nota.

## Plan Review Summary

Stato: piano coerente, scope ben delimitato, traceability TDD completa. Nessun blocker.

**Warnings**:
- R3 (variation selector emoji): mitigato da `canonical_emojis/0` come single source of truth nei test, ma resta da verificare che le stringhe scritte dalla migration in DB combacino esattamente al byte con quelle nel fixture.

**Observations**:
- Bundling step 1 (test + schema + migration nello stesso commit) è obbligato dalla NOT NULL: separarli rompe la build intermedia.
- Step 5 è marcato `trivial` ma dipende dallo step 1 (test docs legge la fixture); va eseguito dopo step 1 — ordine già rispettato.
- Postgres con encoding UTF8 (default Phoenix) gestisce le emoji nativamente; nessun config delta richiesto.
