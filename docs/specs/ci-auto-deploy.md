# Spec: CI auto-deploy to Gigalixir (slice 13)

> Slice 13. Quando `ci.yml` chiude verde su `main`, un secondo workflow
> GitHub Actions deploya automaticamente su Gigalixir e applica le
> eventuali migration pendenti. Supera **OS2** dello spec slice 11b
> (`docs/specs/gigalixir-deploy.md` — "CI does NOT add a `gigalixir push`
> step"): da questa slice in avanti, la pipeline CI è il path canonico
> di delivery, e il `git push gigalixir main` manuale rimane solo come
> fallback per redeploy d'emergenza tramite `workflow_dispatch`.

## Intent Description

Slice 13 chiude il ciclo di delivery: oggi ogni rilascio richiede un
`git push gigalixir main` manuale dopo l'`git push origin main`, con il
rischio operativo di "ho mergato ma mi sono dimenticato di deployare"
o "ho deployato senza far girare le migration". L'obiettivo è che
**ogni commit verde su `main` arrivi in produzione senza intervento
umano**, e che le migration siano applicate automaticamente nello
stesso run.

La pipeline CI esistente (`.github/workflows/ci.yml`) resta invariata
nel suo contratto: compila, formatta, credo, audit, migra il DB di
test, esegue i test. Aggiungiamo un **secondo workflow** dedicato
(`.github/workflows/deploy.yml`) che si attiva solo quando `ci.yml`
finisce con `conclusion == 'success'` e `head_branch == 'main'`.
Il workflow di deploy installa la CLI Gigalixir, si autentica con
`GIGALIXIR_EMAIL` + `GIGALIXIR_API_KEY` (GitHub Actions secrets),
fa `git push gigalixir HEAD:refs/heads/main`, esegue
`Ideajar.Release.migrate` (idempotente — no-op se non c'è nulla di
pending), e infine fa uno smoke test su `/health` con retry.

I deploy sono serializzati da una concurrency group `deploy-prod`
con `cancel-in-progress: false` per evitare race tra commit ravvicinati.
Rollback resta manuale, come da `docs/deploy.md` §Rollback. Notifiche
si limitano all'email GitHub di default sul fallimento del workflow.

## User-Facing Behavior

```gherkin
Feature: CI auto-deploy to Gigalixir

  Background:
    Given the slice 11b prod stack is live (Dockerfile + Ideajar.Release + /health)
    And GIGALIXIR_EMAIL, GIGALIXIR_API_KEY, GIGALIXIR_APP_NAME are set as repository secrets
    And docs/deploy.md still documents the manual fallback path

  # ── Trigger ─────────────────────────────────────────────────────
  Scenario: Green CI run on main triggers a deploy
    Given a commit lands on main
    And ci.yml completes with conclusion "success"
    When GitHub fires workflow_run for ci.yml
    Then deploy.yml starts a run
    And the run targets the same SHA that ci.yml validated

  Scenario: Failed CI run on main does NOT trigger a deploy
    Given a commit lands on main
    And ci.yml completes with conclusion "failure"
    When GitHub fires workflow_run for ci.yml
    Then deploy.yml does NOT start a run

  Scenario: Green CI run on a feature branch does NOT trigger a deploy
    Given a commit lands on a branch other than main
    And ci.yml completes with conclusion "success"
    When GitHub fires workflow_run for ci.yml
    Then deploy.yml does NOT start a run
    # Filter: head_branch == 'main'

  Scenario: Manual redeploy via workflow_dispatch
    Given the developer needs to redeploy main without a new commit
    When the developer runs deploy.yml via the Actions UI workflow_dispatch button
    Then the workflow runs against the current main SHA
    And follows the same push + migrate + smoke-test path as the auto trigger

  # ── Push to Gigalixir ──────────────────────────────────────────
  Scenario: Successful push deploys the validated SHA
    Given the deploy job is running on the SHA that ci.yml validated
    When the job runs `gigalixir login` with the API-key secrets
    And adds the gigalixir git remote via `gigalixir git:remote $GIGALIXIR_APP_NAME`
    And runs `git push gigalixir HEAD:refs/heads/main`
    Then Gigalixir builds the Docker image
    And the new release replaces the previous one
    And the job's push step exits 0

  Scenario: Checkout uses full history so Gigalixir accepts the push
    Given the deploy job checks out the repo
    When actions/checkout@v4 runs
    Then fetch-depth is 0
    # Gigalixir rejects shallow pushes; this regression-pins the depth

  Scenario: Push failure fails the job
    Given the gigalixir push fails (e.g., build error, auth failure)
    When the push step exits non-zero
    Then the workflow run is marked failed
    And no migration step runs after the failed push
    And GitHub sends the default failure-notification email to repo admins

  # ── Migrations ─────────────────────────────────────────────────
  Scenario: Migrate runs after every successful deploy
    Given the gigalixir push step succeeded
    When the migrate step runs `gigalixir run -- bin/ideajar eval "Ideajar.Release.migrate"`
    Then Ecto.Migrator applies every pending migration
    And the step exits 0
    # Idempotent — if nothing is pending, the migrator is a no-op

  Scenario: Migrate failure fails the job and skips the smoke test
    Given the migrate step exits non-zero
    When the workflow evaluates next steps
    Then the smoke-test step is NOT executed
    And the workflow run is marked failed

  # ── Smoke test ─────────────────────────────────────────────────
  Scenario: Smoke test confirms the deploy is live
    Given the migrate step succeeded
    When the smoke-test step runs `curl -fsS https://$PHX_HOST/health`
    Then it retries up to 10 times at 15-second intervals if the response is not 200
    And on the first 200 response with body containing `"status":"ok"` the step exits 0

  Scenario: Smoke test failure fails the job and prints a recovery hint
    Given the smoke test never returns 200 within the retry window
    When the loop exhausts all 10 attempts
    Then the step prints a message containing "previous release"
    And the step prints the command "gigalixir logs"
    And the step prints the command "gigalixir releases:rollback"
    And the step exits non-zero
    And the workflow run is marked failed
    And NO automatic rollback is performed
    # Manual rollback via `gigalixir releases:rollback`, see docs/deploy.md

  # ── Concurrency ────────────────────────────────────────────────
  Scenario: Two green CI runs in quick succession serialize on deploy
    Given commit A lands on main and ci.yml goes green
    And commit B lands on main before deploy.yml for A starts
    And ci.yml for B also goes green
    When deploy.yml fires for both
    Then both runs are placed in the concurrency group "deploy-prod"
    And the second run waits for the first to finish
    And neither run is cancelled
    # cancel-in-progress: false — queue, do not drop

  # ── Secrets ────────────────────────────────────────────────────
  Scenario: Missing GIGALIXIR_API_KEY fails the workflow with a clear message
    Given GIGALIXIR_API_KEY is not set as a repository secret
    When the deploy job runs
    Then the gigalixir-login step fails
    And the workflow run is marked failed

  Scenario: Secrets are read at the job level, not echoed to logs
    When I read deploy.yml
    Then GIGALIXIR_EMAIL, GIGALIXIR_API_KEY, GIGALIXIR_APP_NAME are referenced via secrets.*
    And no `echo` or `printf` step prints those values to stdout

  # ── Out-of-scope guards ────────────────────────────────────────
  Scenario: Slice 13 does NOT add automatic rollback
    When I read deploy.yml
    Then no step invokes `gigalixir releases:rollback`
    And smoke-test failure does not trigger a rollback action

  Scenario: Slice 13 does NOT add Slack/Discord/PagerDuty notifications
    When I read deploy.yml
    Then no curl/POST step targets a webhook URL
    # GitHub default email notification is the only failure channel

  Scenario: Slice 13 does NOT change ci.yml's contract
    When I read .github/workflows/ci.yml
    Then no step pushes to gigalixir
    And no step references GIGALIXIR_* secrets
    # ci.yml stays test-only; deploy lives in its own file

  Scenario: Slice 13 does NOT skip deploys on docs-only changes
    Given a commit on main only modifies files under docs/
    And ci.yml goes green
    When deploy.yml fires
    Then it runs the full push + migrate + smoke-test sequence
    # No path filters; Docker layer cache makes the no-op deploy fast

  # ── Manual fallback parity ─────────────────────────────────────
  Scenario: Manual `git push gigalixir main` still works as documented
    When the developer follows docs/deploy.md §Routine deploys
    Then the manual flow still produces a working deploy
    # Deploy automation does not lock out the manual escape hatch
```

## Architecture Specification

### Components

| Componente | Tipo | Responsabilità |
|---|---|---|
| `.github/workflows/deploy.yml` | GitHub Actions workflow | Triggerato da `workflow_run` di `ci.yml` + `workflow_dispatch`. Filtra su `conclusion == 'success'` + `head_branch == 'main'`. Esegue checkout full-depth, install CLI Gigalixir, login, git push, migrate, smoke test. |
| `.github/workflows/ci.yml` | Esistente, NON modificato | Resta test-only. Nessuna referenza a Gigalixir o ai suoi secrets. |
| `docs/deploy.md` | Esistente, aggiornamento minimo | Sezione "Routine deploys" annotata: il path automatico è il default; il manuale resta come fallback per `workflow_dispatch` o emergenze. Sezione "Common failure modes" estesa con i sintomi tipici del job CD. |
| `docs/specs/gigalixir-deploy.md` | Esistente, **NON** modificato | OS2 viene segnalato come superato dal nuovo spec via cross-link in questo file. Nessuna riscrittura retroattiva — ogni spec è uno snapshot della sua slice. |

### Interfaces

**`.github/workflows/deploy.yml`** (struttura logica, non implementativa):

```yaml
name: Deploy to Gigalixir

on:
  workflow_run:
    workflows: ["CI"]      # nome del workflow esistente in ci.yml
    types: [completed]
  workflow_dispatch:        # redeploy manuale di main

concurrency:
  group: deploy-prod
  cancel-in-progress: false # serializza, non droppa

jobs:
  deploy:
    if: >
      (github.event_name == 'workflow_dispatch') ||
      (github.event.workflow_run.conclusion == 'success' &&
       github.event.workflow_run.head_branch == 'main')
    runs-on: ubuntu-latest
    env:
      GIGALIXIR_APP_NAME: ${{ secrets.GIGALIXIR_APP_NAME }}
      PHX_HOST: ${{ secrets.PHX_HOST }}    # solo per smoke test
    steps:
      - uses: actions/checkout@v4
        with:
          # workflow_run → head_sha del commit validato da CI;
          # workflow_dispatch → tip-of-main, perché github.sha
          # punta al SHA del workflow file context, non al main corrente.
          ref: ${{ github.event.workflow_run.head_sha || 'refs/heads/main' }}
          fetch-depth: 0   # Gigalixir rejects shallow pushes

      - name: Install gigalixir CLI
        run: pipx install gigalixir

      - name: Authenticate
        run: gigalixir login -e "$GIGALIXIR_EMAIL" -y
        env:
          GIGALIXIR_EMAIL: ${{ secrets.GIGALIXIR_EMAIL }}
          GIGALIXIR_API_KEY: ${{ secrets.GIGALIXIR_API_KEY }}

      - name: Add gigalixir remote
        run: gigalixir git:remote "$GIGALIXIR_APP_NAME"

      - name: Push
        run: git push gigalixir HEAD:refs/heads/main

      - name: Migrate
        run: gigalixir run -- bin/ideajar eval "Ideajar.Release.migrate"

      - name: Smoke test
        run: |
          for i in $(seq 1 10); do
            if curl -fsS "https://$PHX_HOST/health" | grep -q '"status":"ok"'; then
              exit 0
            fi
            sleep 15
          done
          echo "Smoke test failed after 10 attempts; previous release likely still serving."
          echo "Inspect: gigalixir logs"
          echo "Rollback if needed: gigalixir releases:rollback"
          exit 1
```

> Lo snippet definisce il **contratto**, non l'implementazione finale.
> Il TDD del piano può divergere su dettagli (es. nome dei step,
> posizione delle env), ma deve rispettare le acceptance criteria.

### Constraints

- **Single workflow file**, sotto `.github/workflows/deploy.yml`. Non si aggiungono job a `ci.yml`.
- **`ci.yml` resta intoccato.** Stessa concurrency group `ci-${{ github.ref }}` con `cancel-in-progress: true`.
- **Trigger filtri obbligatori:** `conclusion == 'success'` AND `head_branch == 'main'`. Senza entrambi non si deploya.
- **Concurrency group `deploy-prod`, `cancel-in-progress: false`** — serializzazione obbligatoria.
- **Checkout `fetch-depth: 0`** — Gigalixir rifiuta shallow push.
- **CLI Gigalixir installata via `pipx`** (i runner GitHub `ubuntu-latest` hanno Python + pipx out of the box).
- **Auth via `GIGALIXIR_EMAIL` + `GIGALIXIR_API_KEY`** repository secrets. **`GIGALIXIR_APP_NAME`** secret per parametrizzare il nome dell'app (default operativo: `ideajar`, con fallback `ideajar-app`/`ideajar-prod` ereditato dal runbook).
- **`PHX_HOST`** è secret solo per lo smoke test del workflow (curl URL). Sull'app Gigalixir resta nei `gigalixir config` come da slice 11b.
- **Migrate sempre, smoke test sempre.** Nessun path filter, nessun `[skip deploy]` in commit message.
- **Smoke test:** 10 retry × 15s = 150s di tolleranza, calibrato sui cold-start osservati sul free tier dopo Docker build pesanti. A esaurimento dei retry lo step stampa istruzioni di recovery (`gigalixir logs`, `gigalixir releases:rollback`) prima di `exit 1`. Fallisce → job fallisce → email GH default.
- **Nessun rollback automatico.** Manuale via `gigalixir releases:rollback` (runbook).
- **Nessuna notifica custom.** Solo email GH default.
- **Niente segreti in log:** nessun `echo` su `GIGALIXIR_*`. CLI Gigalixir mascher in autonomia in caso.

### Dependencies

- **GitHub Actions secrets**: `GIGALIXIR_EMAIL`, `GIGALIXIR_API_KEY`, `GIGALIXIR_APP_NAME`, `PHX_HOST`.
- **`pipx`** (preinstallato su `ubuntu-latest`).
- **`gigalixir` CLI** (PyPI).
- **`Ideajar.Release.migrate/0`** già esistente da slice 11b.
- **`/health` endpoint** già esistente da slice 11b.
- **Nessun nuovo Hex dep.** Nessun cambio di codice Elixir, di Dockerfile, di `config/runtime.exs`.

### Out of scope

- Auto-rollback su smoke-test failure
- Notifiche Slack/Discord/PagerDuty/issue auto-aperta
- Path filter / `[skip deploy]` / branch-filter avanzati
- Promuovere artefatti (es. immagine Docker pre-built da CI a Gigalixir) — Gigalixir rebuilda dal git push, è il loro modello canonico
- Custom domain
- Multi-environment (staging) — couple-2-user, single env
- Modifiche al codice runtime (`Ideajar.Release`, `/health`, `config/runtime.exs`, Dockerfile) — già coperti slice 11b
- Riscrittura retroattiva di `docs/specs/gigalixir-deploy.md` OS2 — gli spec sono snapshot per slice
- Cambiare `ci.yml`

## Acceptance Criteria

### Workflow file presence + structure

- [ ] **W1** — `.github/workflows/deploy.yml` esiste e parsa come workflow YAML valido (`actionlint` o lint built-in).
- [ ] **W2** — Trigger `workflow_run` con `workflows: ["CI"]` e `types: [completed]`.
- [ ] **W3** — Trigger `workflow_dispatch` presente (redeploy manuale).
- [ ] **W4** — Job `deploy` ha `if:` che richiede `conclusion == 'success'` AND `head_branch == 'main'` (oppure `workflow_dispatch`).
- [ ] **W5** — Concurrency group `deploy-prod` con `cancel-in-progress: false`.

### Checkout + auth

- [ ] **A1** — `actions/checkout@v4` con `fetch-depth: 0` e `ref` agganciato a `github.event.workflow_run.head_sha` (per `workflow_run`) o `refs/heads/main` (per `workflow_dispatch`). `github.sha` NON è ammesso come fallback per `workflow_dispatch` perché punta al SHA del workflow file context, non al main corrente.
- [ ] **A2** — Step "Install gigalixir CLI" via `pipx install gigalixir`.
- [ ] **A3** — Step "Authenticate" usa `secrets.GIGALIXIR_EMAIL` + `secrets.GIGALIXIR_API_KEY`. Nessun `echo` di queste variabili.
- [ ] **A4** — `gigalixir git:remote "$GIGALIXIR_APP_NAME"` aggiunge il remote.

### Push + migrate

- [ ] **P1** — Step "Push" esegue `git push gigalixir HEAD:refs/heads/main`.
- [ ] **P2** — Push failure fa fallire il job e blocca i passi successivi.
- [ ] **M1** — Step "Migrate" esegue `gigalixir run -- bin/ideajar eval "Ideajar.Release.migrate"`.
- [ ] **M2** — Migrate failure fa fallire il job e blocca lo smoke test.

### Smoke test

- [ ] **S1** — Step "Smoke test" fa `curl -fsS "https://$PHX_HOST/health"`.
- [ ] **S2** — Retry: 10 tentativi a 15 secondi (totale 150s), esce 0 al primo 200 con body `"status":"ok"`.
- [ ] **S3** — Pin strutturale degli exit code: `exit 0` viene emesso DENTRO un ramo condizionale dopo un `grep -q` riuscito (mai incondizionatamente); `exit 1` viene emesso solo DOPO l'esaurimento del retry loop.
- [ ] **S4** — A esaurimento dei retry, lo step stampa esplicitamente: una frase contenente `previous release`, il comando `gigalixir logs`, il comando `gigalixir releases:rollback`. La presenza di queste tre stringhe è pinnata via test.
- [ ] **S5** — Smoke-test failure fa fallire il job; nessun rollback automatico.

### Out-of-scope guards

- [ ] **OS1** — `.github/workflows/ci.yml` resta invariato sui suoi step e non referenzia `GIGALIXIR_*`.
- [ ] **OS2** — `deploy.yml` non **invoca** `gigalixir releases:rollback` come comando. Il pattern di rollback può comparire solo dentro `echo` (recovery hint dello smoke test, S4); non come bare command. Test pin: nessuna riga matcha la regex `^\s*gigalixir releases:rollback` (i.e., non come prima parola di una `run:` line) — la stringa è ammessa solo all'interno di `echo`/`printf`.
- [ ] **OS3** — `deploy.yml` non contiene chiamate webhook esterne (Slack/Discord/PagerDuty domain literals; pattern `curl -X POST`/`curl --data`; action di terze parti notification).
- [ ] **OS4** — Nessun path filter su `paths:` / `paths-ignore:` nel trigger.

### Documentation

- [ ] **D1** — `docs/deploy.md` §Routine deploys aggiornato: il path automatico (CI verde su `main`) è il default; il manuale resta documentato come fallback.
- [ ] **D2** — `docs/deploy.md` §Common failure modes esteso con sintomi tipici del CD (es. workflow_run non parte, gigalixir push fallisce in CI, smoke test in retry-loop, advisory-lock fail su migrate concorrente).
- [ ] **D3** — `docs/deploy.md` lista i secrets richiesti (`GIGALIXIR_EMAIL`, `GIGALIXIR_API_KEY`, `GIGALIXIR_APP_NAME`, `PHX_HOST`) con istruzioni per impostarli (`Settings → Secrets and variables → Actions`) e l'ordering constraint di settarli **prima del merge**.
- [ ] **D4** — `docs/deploy.md` ha una sezione "First-time activation" che spiega: il merge che introduce `deploy.yml` non triggera `workflow_run` (GH Actions richiede che il workflow esista già su `main` quando l'evento upstream parte); l'operatore deve lanciare un `workflow_dispatch` manuale subito dopo il merge per fare bootstrap del primo deploy.
- [ ] **D5** — `docs/deploy.md` annota che la pipeline CD applica le migration pendenti automaticamente; per le migration **additive** (current schema slice 1-12) questo è safe; future migration **breaking** (drop colonna, rename) richiedono pause della CD o downtime pianificato.

### Operational

- [ ] **O1** — Nessun cambio a Elixir code, Dockerfile, `config/runtime.exs`, `mix.exs`, `lib/ideajar/release.ex`.
- [ ] **O2** — Nessun nuovo Hex dep.
- [ ] **O3** — Test suite esistente resta verde (la slice non tocca codice runtime).
- [ ] **O4** — Validation manuale post-merge: una volta unito su `main`, il primo `workflow_run` su `ci.yml` verde deve produrre un deploy verde end-to-end (osservato in Actions UI + `gigalixir logs`).

## Consistency Gate

- [x] **Intent unambiguo** — CD via secondo workflow GH Actions, triggerato da CI verde su main, deploy + migrate + smoke test, no rollback auto, no notifiche custom
- [x] **Ogni behavior ha BDD scenario** — trigger (positivo + negativi), push, migrate, smoke test, concurrency, secrets, out-of-scope guards, manual fallback parity
- [x] **Architecture senza over-engineering** — un solo file workflow nuovo, CLI Gigalixir riusata per push e migrate, zero codice nuovo, zero dipendenze runtime
- [x] **Termini consistenti** — `deploy-prod` (concurrency), `GIGALIXIR_EMAIL`/`GIGALIXIR_API_KEY`/`GIGALIXIR_APP_NAME` (secrets), `Ideajar.Release.migrate` (canonico da slice 11b), `/health` (canonico da slice 11b)
- [x] **Nessuna contraddizione** — la deroga su OS2 dello spec slice 11b è dichiarata esplicitamente nel preambolo; nessuna modifica retroattiva a `gigalixir-deploy.md`; il manual deploy resta supportato (parity scenario)

**Verdict: PASS** — ready for `/plan`.
