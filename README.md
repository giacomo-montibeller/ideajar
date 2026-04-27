# ideajar

Webapp privata per una coppia che condivide idee di attività nel tempo libero (passeggiate, mare, cultura, viaggi…) con filtri per categoria, durata, budget, distanza e ricerca testuale. Scopo: ridurre il _decision paralysis_ quando le idee buone sono troppe.

Vedi `CONTEXT.md` per il quadro generale, `docs/specs/` per le specifiche per slice, e `plans/` per i piani di implementazione approvati.

## Stack

- Phoenix 1.8+ con LiveView
- SQLite via Ecto (singolo file, backup = copia file)
- Tailwind CSS + daisyUI
- PWA (manifest + service worker minimo solo per installabilità)
- Deploy: Gigalixir free tier

## Prerequisiti

- Erlang/OTP 26.x e Elixir 1.16+ (consigliato via [asdf](https://asdf-vm.com/) — vedi `.tool-versions`)
- `mix archive.install hex phx_new` per il generatore Phoenix (richiesto solo se vuoi rigenerare lo scaffold)
- `git`

## Quick start (sviluppo locale)

```bash
asdf install                   # installa le versioni in .tool-versions
mix setup                      # deps.get + ecto.setup + assets.setup + assets.build
mix ecto.migrate               # idempotente; necessario dopo un git pull che porta nuove migration
mix phx.server                 # avvia su http://localhost:4000
```

In dev la password workspace di default è `dev-only-password-change-me` (vedi `config/dev.exs`). Sovrascrivibile via env var:

```bash
WORKSPACE_PASSWORD="..." mix phx.server
```

## Variabili d'ambiente richieste

L'app rifiuta lo startup se queste sono mancanti o sotto il minimo (vedi `lib/ideajar/config.ex`):

| Variabile          | Scope    | Vincolo                 | Note                                                     |
|--------------------|----------|-------------------------|----------------------------------------------------------|
| `WORKSPACE_PASSWORD` | tutti gli env | string ≥ 12 caratteri | Password condivisa per l'autenticazione device-level     |
| `SECRET_KEY_BASE`    | tutti gli env | string ≥ 64 byte       | Firma il cookie di sessione; **stabile tra deploy**      |
| `DATABASE_PATH`      | `:prod`       | string assoluta        | Es. `/etc/ideajar/ideajar.db`                            |
| `PHX_HOST`           | `:prod`       | string                  | Es. `ideajar.example.com`                                |
| `PHX_SERVER`         | release       | `true` per avviare      | Necessario nei release `mix release`                     |

### Generare `SECRET_KEY_BASE`

```bash
mix phx.gen.secret
```

Produce 64 byte random sicuri per la firma dei cookie.

## Rotazione password (password rotation)

La password workspace **non è progettata per rotazioni frequenti**: è un segreto condiviso tra i due utenti del workspace, scambiato fuori banda. La procedura di rotazione richiede:

1. Generare una nuova password (≥12 caratteri) e comunicarla all'altro utente fuori banda (Signal, di persona, ecc.).
2. Su Gigalixir: `gigalixir config:set WORKSPACE_PASSWORD="..."` e attendere il redeploy.
3. La sessione cookie esistente resta valida finché `SECRET_KEY_BASE` è invariato — quindi rotare `WORKSPACE_PASSWORD` da solo **non** invalida le sessioni dei dispositivi già autenticati. Per forzare il logout di tutti i device, ruotare anche `SECRET_KEY_BASE`.

## Test

```bash
mix test                        # tutti i test
mix format --check-formatted    # formatting
mix credo                       # static analysis
```

## Deploy su Gigalixir

Vedi slice 9 (TBD) — guida completa pubblicata insieme al deploy della prima release.

## Riferimenti

- `CONTEXT.md` — visione di prodotto e roadmap delle slice
- `docs/specs/` — spec BDD + Architecture + Acceptance per ogni slice
- `docs/conventions.md` — convenzioni del progetto (lingua UI, copy canonica)
- `plans/` — piani di implementazione approvati
