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
| Heading home placeholder    | `Workspace privato`                                       |

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
