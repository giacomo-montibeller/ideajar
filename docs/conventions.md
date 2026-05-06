# Convenzioni di progetto — ideajar

Vincoli trasversali che si applicano a tutte le slice. Cambiamenti a questo file devono essere votati nello _spec consistency gate_ della slice corrente, perché impattano tutto il codice esistente.

## Lingua UI

**La lingua UI è italiano.** Tutta la copy mostrata all'utente, etichette di form, messaggi di errore, titoli di pagina, navigazione, e contenuti statici sono in italiano. Nessuna i18n: `--no-gettext` nello scaffold Phoenix è una scelta deliberata.

Eccezioni:
- Identificatori di codice (moduli, funzioni, variabili, atom) restano in inglese, come da convenzione Elixir.
- Commenti tecnici nel codice sono in italiano o inglese a discrezione dell'autore.
- Docstring (`@moduledoc`, `@doc`) preferibilmente in inglese (compatibilità con tooling come ExDoc).

Se in futuro servisse i18n: ri-aggiungere gettext con `mix phx.gen.gettext` e migrare la copy via PO file. Pianificare come slice dedicata.

## UI copy canonica

Stringhe consolidate in slice 1 (device password auth), da riutilizzare consistentemente:

| Elemento                    | Testo IT                                                  |
|-----------------------------|-----------------------------------------------------------|
| `<title>` login             | `ideajar — accesso`                                       |
| `<title>` home              | `ideajar — workspace privato`                             |
| Heading login               | `ideajar`                                                 |
| Helper text login           | `Inserisci la password condivisa per questo dispositivo.` |
| Label campo password        | `Password`                                                |
| Bottone submit login        | `Entra`                                                   |
| Errore login generico       | `Password errata`                                         |

Stringhe aggiunte in slice 2 (add base idea):

| Elemento                          | Testo IT                                              |
|-----------------------------------|-------------------------------------------------------|
| Bottone aggiungi idea             | `+ Aggiungi idea`                                     |
| Bottone submit form               | `Salva`                                               |
| Submit pending (phx-disable-with) | `Salvataggio…`                                        |
| Aria close icon                   | `Chiudi`                                              |
| Label campo titolo                | `Titolo`                                              |
| Label campo descrizione           | `Descrizione`                                         |
| Label campo link                  | `Link`                                                |
| Errore titolo vuoto               | `Il titolo è obbligatorio`                            |
| Errore titolo lungo               | `Il titolo non può superare i 200 caratteri`          |
| Errore link invalido              | `Il link deve iniziare con http:// o https://`        |
| Errore link lungo                 | `Il link non può superare i 2000 caratteri`           |
| Aria link external                | `Apri link in una nuova scheda`                       |
| Empty state                       | `Nessuna idea ancora. Aggiungine una qui sopra.`      |
| Flash success                     | `Idea aggiunta`                                       |
| Flash DB error                    | `Salvataggio non riuscito, riprova`                   |

Stringhe aggiunte in slice 3 (categories on ideas):

| Elemento                          | Testo IT                                              |
|-----------------------------------|-------------------------------------------------------|
| Legend del fieldset categorie     | `Categorie *` (asterisco visivo + sr-only "obbligatorio") |
| Helper text sotto legend          | `Scegli almeno una categoria`                         |
| Errore "almeno una"               | `Seleziona almeno una categoria`                      |
| Errore id invalido                | `Categoria non valida`                                |
| Categoria 1                       | `🚶 passeggiata`                                      |
| Categoria 2                       | `🏖️ mare`                                             |
| Categoria 3                       | `🏛️ museo`                                            |
| Categoria 4                       | `🍽️ ristorante`                                       |
| Categoria 5                       | `⚽ sport`                                            |
| Categoria 6                       | `🎭 cultura`                                          |
| Categoria 7                       | `🎬 cinema`                                           |
| Categoria 8                       | `✈️ viaggio`                                          |

> **slice 14b** — l'emoji è parte del contratto categoria: vive sul campo `emoji` (TEXT NOT NULL) di `Ideajar.Categories.Category`, popolata via migration `add_emoji_to_categories`. UI: i chip (`category_chip/1`, `filter_chip/1`) e i badge (`category-badge` sulle card) renderizzano `<emoji> <name>`. L'`aria-label` del filter chip resta solo nome (es. `mare opzionale`) per non rumorare gli screen reader.

Stringhe aggiunte in slice 4 (filter by category):

> **DEPRECATED slice 6** — il filter-status live-region è stato rimosso completamente. Le righe `Live-region *` sotto non sono più renderizzate dal template (decisione UX consapevole post-slice 5: l'announce era percepito come noise). Sono mantenute qui solo per traccia storica.

| Elemento                          | Testo IT                                              |
|-----------------------------------|-------------------------------------------------------|
| Bottone reset filtro              | `Mostra tutte`                                        |
| Empty state filter-no-match       | `Nessuna idea per i filtri attivi.`                   |
| Helper text discoverability       | `Tocca per filtrare: 1× opzionale · 2× obbligatoria · 3× rimuovi` |
| Label visivo filter row           | `Filtra per:`                                         |
| Aria-label chip filter off        | `<nome>`                                              |
| Aria-label chip filter optional   | `<nome> opzionale`                                    |
| Aria-label chip filter obbligatoria | `<nome> obbligatoria`                               |
| Live-region prefix optional (deprecated slice 6 — live-region rimosso) | `<nome> opzionale, ` |
| Live-region prefix required (deprecated slice 6 — live-region rimosso) | `<nome> obbligatoria, ` |
| Live-region prefix off (deprecated slice 6 — live-region rimosso)      | `<nome> rimossa, ` |
| Live-region prefix clear (deprecated slice 6 — live-region rimosso)    | `Filtri rimossi, ` |
| Live-region count singolare (deprecated slice 6 — live-region rimosso) | `1 idea` |
| Live-region count plurale (deprecated slice 6 — live-region rimosso)   | `<N> idee` (incluso `0 idee`) |

Stringhe aggiunte in slice 5 (duration on ideas):

> **DEPRECATED slice 6** — il filter-status live-region è stato rimosso completamente. Le righe `Live-region *` sotto non sono più renderizzate dal template (decisione UX consapevole post-slice 5). Sono mantenute qui solo per traccia storica.

| Elemento                                   | Testo IT                                                          |
|--------------------------------------------|-------------------------------------------------------------------|
| Label fieldset durata (form)               | `Durata` (no asterisco — opzionale)                               |
| Helper text form duration                  | (nessuno — campo opzionale)                                       |
| Chip durata 1 (atom `:poche_ore`)          | `poche ore`                                                       |
| Chip durata 2 (atom `:mezza_giornata`)     | `mezza giornata`                                                  |
| Chip durata 3 (atom `:giornata`)           | `giornata`                                                        |
| Chip durata 4 (atom `:weekend`)            | `weekend`                                                         |
| Chip durata 5 (atom `:piu_giorni`)         | `più giorni`                                                      |
| Errore duration invalida                   | `Durata non valida`                                               |
| Sub-label filter Categorie (visivo)        | `Categorie`                                                       |
| Sub-label filter Durata (visivo)           | `Durata`                                                          |
| Aria-label sub-block categorie (SR)        | `Filtra per categoria`                                            |
| Aria-label sub-block durata (SR)           | `Filtra per durata`                                               |
| Helper text NULL-exclusion                 | `Le idee senza durata sono nascoste quando un filtro è attivo.`   |
| Aria-label filter chip off                 | `<label>`                                                         |
| Aria-label filter chip on                  | `<label> attiva`                                                  |
| Live-region action prefix on (deprecated slice 6 — live-region rimosso)  | `<label> attiva, `      |
| Live-region action prefix off (deprecated slice 6 — live-region rimosso) | `<label> rimossa, `     |
| Live-region compound suffix categoria (deprecated slice 6 — live-region rimosso) | `, filtri categoria attivi` |
| Live-region compound suffix durata (deprecated slice 6 — live-region rimosso)    | `, filtri durata attivi`    |
| Badge durata su idea card                  | `<label>` (label IT, non atom)                                    |

Stringhe aggiunte in slice 6 (budget on ideas):

| Elemento                                   | Testo IT                                                          |
|--------------------------------------------|-------------------------------------------------------------------|
| Label fieldset budget (form)               | `Budget` (no asterisco — opzionale)                               |
| Helper text form budget                    | (nessuno — campo opzionale)                                       |
| Chip budget 1 (value 0)                    | `gratis`                                                          |
| Chip budget 2 (value 20)                   | `fino a 20€`                                                      |
| Chip budget 3 (value 50)                   | `fino a 50€`                                                      |
| Chip budget 4 (value 100)                  | `fino a 100€`                                                     |
| Chip budget 5 (value 200)                  | `fino a 200€`                                                     |
| Chip budget 6 (value 500)                  | `fino a 500€`                                                     |
| Chip budget 7 (value 1000)                 | `oltre 1000€`                                                     |
| Errore budget invalido                     | `Budget non valido`                                               |
| Sub-label filter Budget (visivo)           | `Budget`                                                          |
| Aria-label sub-block budget (SR)           | `Filtra per budget`                                               |
| Helper text NULL-exclusion                 | `Le idee senza prezzo sono nascoste quando un filtro è attivo.`   |
| Aria-label filter chip off                 | `<label>` (es. `gratis`, `fino a 100€`, `oltre 1000€`)            |
| Aria-label filter chip on                  | `<label> attiva` (es. `gratis attiva`, `fino a 100€ attiva`, `oltre 1000€ attiva`) |
| Badge budget su idea card                  | `<label>` (uguale al chip label)                                  |

Stringhe aggiunte in slice 7a (location on ideas):

| Elemento                                   | Testo IT                                                          |
|--------------------------------------------|-------------------------------------------------------------------|
| Label fieldset posizione (form)            | `Posizione` (no asterisco — opzionale)                            |
| Label text input                           | `Luogo`                                                           |
| Placeholder text input                     | `es. Casa di nonna`                                               |
| Bottone apri map picker                    | `📍 Apri mappa`                                                   |
| Bottone rimuovi posizione                  | `Rimuovi posizione`                                               |
| Titolo dialog                              | `Scegli posizione`                                                |
| Bottone chiudi dialog                      | aria-label `Chiudi` (visualizza `✕` come slice 2 form close)      |
| OSM attribution (visibile)                 | `© OpenStreetMap` con link a `https://www.openstreetmap.org/copyright` |
| Errore posizione incompleta                | `Posizione incompleta`                                            |
| Errore posizione non valida (range/cast)   | `Posizione non valida`                                            |
| Errore nome luogo troppo lungo             | `Il nome del luogo non può superare i 200 caratteri`              |
| Flash error geocoding service down         | `Geocodifica non disponibile, inserisci il nome manualmente`      |
| Inline hint coords impostate (CC19)        | `📍 Coordinate impostate`                                         |
| Badge location card                        | `📍 <location_name>`                                              |
| Badge data-testid                          | `idea-location-badge`                                             |

Stringhe aggiunte in slice 7b (distance filter on ideas):

| Elemento                                       | Testo IT                                                                     |
|------------------------------------------------|------------------------------------------------------------------------------|
| Sub-label visibile filtro Distanza             | `Distanza`                                                                   |
| Aria-label sub-block (screen reader)           | `Filtra per distanza`                                                        |
| Bottone geolocation                            | `📍 Usa la mia posizione`                                                    |
| Placeholder filter search input                | `Cerca punto di partenza`                                                    |
| Label punto di riferimento                     | `Punto di riferimento: <name>`                                               |
| `@user_location_name` per geolocation          | `La mia posizione`                                                           |
| Bottone rimuovi ref point                      | `Rimuovi punto di riferimento`                                               |
| Bottone rimuovi filtro distanza                | `Rimuovi filtro distanza`                                                    |
| Slider valuetext idx 0                         | `Disattivo`                                                                  |
| Slider valuetext idx 1                         | `fino a 5 km`                                                                |
| Slider valuetext idx 2                         | `fino a 25 km`                                                               |
| Slider valuetext idx 3                         | `fino a 50 km`                                                               |
| Slider valuetext idx 4                         | `fino a 200 km`                                                              |
| Slider valuetext idx 5                         | `fino a 500 km`                                                              |
| Slider valuetext idx 6                         | `oltre 1000 km`                                                              |
| Caption visibile sotto slider                  | `Distanza: <valuetext>`                                                      |
| Helper text disabled state                     | `Imposta un punto di riferimento per usare il filtro distanza`               |
| Helper text NULL-exclude (sempre visibile)     | `Le idee senza posizione sono nascoste quando un filtro è attivo.`           |
| Flash error permission denied                  | `Permesso di geolocalizzazione negato`                                       |
| Flash error generico geolocation               | `Posizione non disponibile, riprova`                                         |
| Flash error ricerca punto di partenza non disponibile | `Ricerca non disponibile, riprova`                                    |

Stringhe aggiunte in slice 8 (text search on ideas):

| Elemento                                       | Testo IT                                                                     |
|------------------------------------------------|------------------------------------------------------------------------------|
| Sub-label visibile filtro Testo                | `Testo`                                                                      |
| Aria-label sub-block (screen reader)           | `Filtra per testo`                                                           |
| Helper text NULL-exception                     | `La ricerca trova le idee con la parola in titolo o descrizione.`            |
| Placeholder text input                         | `Cerca idee`                                                                 |
| Bottone rimuovi filtro testo                   | `Rimuovi filtro testo`                                                       |

Stringhe aggiunte in slice 9 (budget chip → slider conversion):

| Elemento                                       | Testo IT                                                                     |
|------------------------------------------------|------------------------------------------------------------------------------|
| Filter aria-valuetext idx 0                    | `Disattivo`                                                                  |
| Filter aria-valuetext idx 1                    | `Gratis`                                                                     |
| Filter aria-valuetext idx 2                    | `fino a 20€`                                                                 |
| Filter aria-valuetext idx 3                    | `fino a 50€`                                                                 |
| Filter aria-valuetext idx 4                    | `fino a 100€`                                                                |
| Filter aria-valuetext idx 5                    | `fino a 200€`                                                                |
| Filter aria-valuetext idx 6                    | `fino a 500€`                                                                |
| Filter aria-valuetext idx 7                    | `oltre 1000€`                                                                |
| Filter caption sotto slider                    | `Budget: <valuetext>`                                                        |
| Bottone rimuovi filtro budget                  | `Rimuovi filtro budget`                                                      |
| Form aria-valuetext idx 0                      | `Non specificato`                                                            |
| Form aria-valuetext idx 1                      | `Gratis`                                                                     |
| Form aria-valuetext idx 2..6                   | `20€` / `50€` / `100€` / `200€` / `500€`                                      |
| Form aria-valuetext idx 7                      | `1000+€`                                                                     |
| Form caption sotto slider                      | `Budget: <valuetext>`                                                        |
| Bottone form rimuovi prezzo                    | `Rimuovi prezzo`                                                             |
| Bottone toggle filter row collapse (0 attivi)  | `Filtri`                                                                     |
| Bottone toggle filter row collapse (N attivi)  | `Filtri (N)`                                                                 |

Stringhe aggiunte in slice 10 (PWA installability — manifest content):

| Elemento                                       | Testo IT                                                                     |
|------------------------------------------------|------------------------------------------------------------------------------|
| Manifest `name`                                | `Ideajar`                                                                    |
| Manifest `short_name`                          | `Ideajar`                                                                    |
| Manifest `description`                         | `Idee da fare insieme`                                                       |

Stringhe aggiunte in slice 12 (eliminare un'idea):

| Elemento                                       | Testo IT                                                                     |
|------------------------------------------------|------------------------------------------------------------------------------|
| Aria-label bottone trash su card               | `Elimina idea`                                                               |
| Modal title                                    | `Eliminare questa idea?`                                                     |
| Modal body (template)                          | `Elimina l'idea "<title>". L'idea sarà rimossa definitivamente.`             |
| Bottone modal annulla                          | `Annulla`                                                                    |
| Bottone modal conferma (danger)                | `Elimina`                                                                    |
| `phx-disable-with` su `Elimina`                | `Eliminazione…`                                                              |
| Flash success (role="status")                  | `Idea eliminata`                                                             |
| Flash race (role="status")                     | `Idea già eliminata`                                                         |
| Flash errore DB (role="alert")                 | `Eliminazione non riuscita, riprova`                                         |

Nuova copy aggiunta da slice future va appesa qui per evitare drift.

## Architettura

- `Ideajar.*` — _domain_ layer (pure logic, no HTTP/web concerns). Esempio: `Ideajar.Auth`, `Ideajar.Config`.
- `IdeajarWeb.*` — _delivery_ layer (HTTP, controller, plug, template, web-only helpers). Esempio: `IdeajarWeb.LoginController`, `IdeajarWeb.SafeRedirect`.

Non spostare URL/redirect/CSRF logic in `Ideajar.*`; non spostare business invariants in `IdeajarWeb.*`.

## TDD e quality gate

- Ogni cambiamento di comportamento segue **RED → GREEN → REFACTOR**.
- Pre-PR gate: `mix test`, `mix format --check-formatted`, `mix credo` (default mode), `/code-review`.
- Spec BDD e Acceptance Criteria sono _contract_: ogni Gherkin scenario in `docs/specs/<slug>.md` ha almeno un test ExUnit che lo cita per nome (commento `# Scenario: …` sopra il `test "…" do`).

## Git e commit

- Ogni commit passa per la skill `commit-message` (proposta multi-opzione + scelta utente). Niente `git commit -m "..."` diretto.
- Commit message in inglese, imperativo, focalizzato sull'_intent_, senza prefissi tipo `feat:`/`chore:`.

## Sicurezza

- Niente segreti in repository. `SECRET_KEY_BASE`, `WORKSPACE_PASSWORD`, etc. solo via env var.
- `.claude/settings.local.json` è gitignored (per-developer).
- Boot fallisce se le env var di sicurezza sono assenti o sotto il minimo (`Ideajar.Config.validate!/1`).
