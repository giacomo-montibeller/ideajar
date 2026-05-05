# Plan: Slice 13 — CI auto-deploy to Gigalixir

**Created**: 2026-05-04
**Branch**: main (trunk-based)
**Status**: approved
**Spec**: `docs/specs/ci-auto-deploy.md`

## Build conventions (carried from slice 1-12)

- Strict TDD per file machine-checkable (deploy.yml structural properties asserted via ExUnit string tests).
- Pure-mechanical files (markdown docs) are gated by manual review + the corresponding test pin in the spec.
- Pre-step gate compile/format/credo/audit/test su `MIX_ENV=test`.
- commit-message skill option 1 for every commit.
- Trunk-based on `main`; ogni step lascia il repo in stato committable.
- Slice 11b è prerequisito (Dockerfile, `Ideajar.Release.migrate`, `/health` endpoint, `docs/deploy.md` runbook) — non si tocca.
- `ci.yml` resta intoccato (OS1).

## Goal

Slice 13 trasforma l'attuale flusso "merge su main → push manuale a Gigalixir" in un CD automatico: ogni `ci.yml` verde su `main` triggera `.github/workflows/deploy.yml`, che fa push + migrate + smoke test verso Gigalixir senza intervento umano. Il `git push gigalixir main` manuale resta come fallback per redeploy d'emergenza tramite `workflow_dispatch`. Nessun cambio Elixir / Dockerfile / runtime config — la slice è puramente delivery + ops.

## Decisioni architetturali pre-build

- **DD-S13-1 — Workflow separato, NO modifica a ci.yml.** `deploy.yml` è un file nuovo. `ci.yml` non viene toccato (OS1). Riduce blast radius e conflitti con la concurrency esistente di CI.

- **DD-S13-2 — Trigger `workflow_run` + `workflow_dispatch`.** `workflow_run` su `ci.yml` con filtro `conclusion == 'success'` AND `head_branch == 'main'` è il path automatico. `workflow_dispatch` è il bottone manuale (redeploy senza commit). PR e branch ≠ main NON deployano.

- **DD-S13-3 — Concurrency `deploy-prod` con `cancel-in-progress: false`.** Serializza i deploy in coda — non droppa. Diversa dalla concurrency di CI (che è `cancel-in-progress: true` per le build, corretta per quella).

- **DD-S13-4 — CLI Gigalixir come unico tool nel runner.** `pipx install gigalixir`, `gigalixir login`, `gigalixir git:remote $APP`. Riusiamo lo stesso CLI per push e per `Ideajar.Release.migrate`. Zero action di terze parti.

- **DD-S13-5 — Checkout asimmetrico per i due trigger.** `actions/checkout@v4` con `fetch-depth: 0` (Gigalixir rifiuta shallow push). Il `ref` cambia per trigger:
  - `workflow_run`: `ref: ${{ github.event.workflow_run.head_sha }}` — il SHA esatto che CI ha validato.
  - `workflow_dispatch`: `ref: refs/heads/main` — il manual redeploy deve sempre prendere tip-of-main, perché `github.sha` per `workflow_dispatch` punta al SHA del commit che ha definito il workflow, non al main corrente. Questo era un blocker della review architetturale.
  Pinned via test (A1a + A1b).

- **DD-S13-6 — Migrate sempre, idempotente, con assunzione di compatibilità additiva.** `Ecto.Migrator.run/4` con `all: true` è no-op se non c'è pending. Diverso da slice 11b (manuale per scelta) — qui l'invocazione è esplicita post-deploy single-shot dal job CD, non on-container-start, quindi il rischio multi-istanza on-boot non si applica.
  - **Race operatore manuale vs CD**: se l'operatore lancia `gigalixir run -- bin/ideajar eval "Ideajar.Release.migrate"` mentre il job CD esegue lo stesso comando, il secondo migrator può fallire con "could not obtain lock" (Postgres advisory lock di `Ecto.Migrator`). Questo è documentato in §Common failure modes (D2): operatori usano `workflow_dispatch`, non `gigalixir run` manuale. Catturato in R7.
  - **Race migrate vs cutover**: `gigalixir run` apre un container one-off in parallelo al rollout dei container web. Se il rollout è lento, la migration può venire applicata mentre i container vecchi servono ancora traffico. Per tutto il database schema attuale di ideajar (slice 1-12: solo migration additive — colonne nullable o tabelle nuove) questo è safe. Per future migration breaking (drop colonna, rename) l'operatore deve disabilitare la pipeline CD per quel deploy o accettare un breve downtime — documentato in D2.

- **DD-S13-7 — Smoke test su `/health` con 10×15s retry + recovery hint a fallimento.** Cold-start del free tier dopo Docker build può superare 50s; allargo a 150s totali per ridurre flake. Allo scadere dei retry il workflow stampa istruzioni esplicite (`gigalixir logs`, `gigalixir releases:rollback`) prima di `exit 1`, in modo che l'operatore veda il next step direttamente nel log Actions. Failure = job failed = email GH default. NO rollback automatico.

- **DD-S13-8 — Secrets a livello repo, non environment.** `GIGALIXIR_EMAIL`, `GIGALIXIR_API_KEY`, `GIGALIXIR_APP_NAME`, `PHX_HOST`. Single env, no staging — environment GH overkill. *Forward-compat*: se in futuro si aggiunge staging, la migrazione a GH Environments è un refactor `secrets.X` → environment-scoped senza modifiche di codice.

- **DD-S13-9 — Test approach con assertion strutturali, non solo lessicali.** Il deploy.yml è machine-checkable. Si aggiunge `test/ideajar/deploy_workflow_test.exs` che legge il file come stringa e asserisce:
  1. **Token presence** dove basta la presenza (es. `pipx install gigalixir`).
  2. **Exact substring match** per espressioni booleane critiche dove un token-AND può essere strutturalmente sbagliato — in particolare l'`if:` del job (canonical form intero asserito letteralmente). Risolve il blocker della review acceptance.
  3. **Step ordering** via posizione relativa nel file: `Push` precede `Migrate` precede `Smoke test`. Risolve il blocker P2/M2.
  4. **Negative pins** (es. `||` non collega `success` e `head_branch`; `continue-on-error: true` non appare; webhook URL non appaiono).
  La validazione end-to-end (workflow gira davvero) è O4, manual post-merge.

- **DD-S13-10 — `actionlint` come gate strutturale.** Aggiunto al pre-PR gate (locale via `actionlint .github/workflows/deploy.yml`). Cattura errori che gli string-test non vedono: indent sbagliato, chiavi duplicate, `types: completed` invece di `types: [completed]`, riferimenti a context inesistenti. Risolve il W1 dello spec (che richiedeva esplicitamente "actionlint o lint built-in"). NON aggiunto a `ci.yml` (OS1 — `ci.yml` resta intoccato); resta gate locale + manual smoke documentato.

- **DD-S13-11 — Lock-in Gigalixir esplicito.** Il modello `git push gigalixir` è specifico di Gigalixir. Migrare a un altro host (Fly.io, Render, ecc.) richiede riscrittura di `deploy.yml` ma nessun cambio di codice applicativo. Catturato come constraint dichiarato, non come risk.

## Acceptance Criteria

> Mappatura uno-a-uno con `docs/specs/ci-auto-deploy.md`.

### Workflow file presence + structure
- [ ] **W1** — `actionlint .github/workflows/deploy.yml` non riporta errori (gate locale, pinnato in pre-PR checklist).
- [ ] **W2** — Trigger `workflow_run` con `workflows: ["CI"]` e `types: [completed]`.
- [ ] **W3** — Trigger `workflow_dispatch` presente.
- [ ] **W4** — Job `deploy` ha l'`if:` con la **forma canonica esatta** `(github.event_name == 'workflow_dispatch') || (github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.head_branch == 'main')` — `workflow_dispatch` come prima alternativa, AND tra `conclusion` e `head_branch`. Test pin via exact substring match. **Negative pin**: il file NON contiene `||` che colleghi `conclusion` con `head_branch`.
- [ ] **W5** — Concurrency group `deploy-prod` con `cancel-in-progress: false`.

### Checkout + auth
- [ ] **A1a** — `actions/checkout@v4` con `fetch-depth: 0`.
- [ ] **A1b** — Il `ref` differenzia i due trigger: `workflow_run` → `${{ github.event.workflow_run.head_sha }}`; `workflow_dispatch` → `refs/heads/main`. (Implementabile come blocco `if`/`else` con due step di checkout, oppure via `ref: ${{ github.event.workflow_run.head_sha || 'refs/heads/main' }}`.)
- [ ] **A2** — Step "Install gigalixir CLI" via `pipx install gigalixir`.
- [ ] **A3** — Step "Authenticate" usa `secrets.GIGALIXIR_EMAIL` + `secrets.GIGALIXIR_API_KEY`. NO `echo` di queste variabili. *Coverage gap noto*: il fallimento di `gigalixir login` su API key mancante è solo verificabile a runtime → coperto da O4, non da unit test.
- [ ] **A4** — `gigalixir git:remote "$GIGALIXIR_APP_NAME"` aggiunge il remote.

### Push + migrate
- [ ] **P1** — Step "Push" esegue `git push gigalixir HEAD:refs/heads/main`.
- [ ] **P2** — Né "Push" né "Migrate" né "Smoke test" hanno `continue-on-error: true` (negative pin globale).
- [ ] **P3** — Step ordering pinnato: posizione di "Push" < posizione di "Migrate" < posizione di "Smoke test" nel file. Garantisce che il fail-stop default di GH Actions valga in sequenza corretta.
- [ ] **M1** — Step "Migrate" esegue `gigalixir run -- bin/ideajar eval "Ideajar.Release.migrate"`.
- [ ] **M2** — Migrate failure blocca lo smoke test (coperto da P2 + P3).

### Smoke test
- [ ] **S1** — Step "Smoke test" fa `curl -fsS "https://$PHX_HOST/health"`.
- [ ] **S2** — Retry: **10 tentativi a 15s** (totale 150s), esce 0 al primo 200 con body `"status":"ok"`.
- [ ] **S3** — Pin strutturale del flusso: `exit 0` appare in un blocco condizionale (dentro `if [...]; then` o equivalente, dopo il `grep -q`) PRIMA di `sleep 15`; `exit 1` appare DOPO la chiusura del loop.
- [ ] **S4** — A fallimento, lo step stampa esplicitamente: messaggio "Smoke test failed after 10 attempts; previous release likely still serving", riferimento a `gigalixir logs`, comando `gigalixir releases:rollback`. Pinned via token.
- [ ] **S5** — Smoke-test failure fa fallire il job; nessun rollback automatico (coperto da OS2).

### Out-of-scope guards
- [ ] **OS1a** — `.github/workflows/ci.yml` non contiene la stringa `gigalixir`.
- [ ] **OS1b** — `.github/workflows/ci.yml` non contiene `GIGALIXIR_`.
- [ ] **OS1c** — `.github/workflows/ci.yml` contiene la riga `name: CI` (pin simmetrico — il `workflow_run` matcha sul nome, non sul filename, quindi rinominare `ci.yml` rompe il trigger silently).
- [ ] **OS2** — `deploy.yml` non **invoca** `gigalixir releases:rollback` come bare command. La stringa è ammessa solo all'interno di `echo`/`printf` (recovery hint S4). Test pin: nessuna riga dello script matcha la regex `^\s*gigalixir releases:rollback\b` (cattura il bare command e ignora i contesti `echo "..."`).
- [ ] **OS3** — `deploy.yml` non contiene chiamate webhook esterne. Heuristica multi-token:
  - NO domain literals: `hooks.slack.com`, `discord.com/api/webhooks`, `events.pagerduty.com`
  - NO outbound POST patterns: `curl -X POST`, `curl --data`, `curl -d "`
  - NO action di terze parti notification: regex `uses: .*(notify|slack|discord|pagerduty)`
- [ ] **OS4** — Nessun `paths:` / `paths-ignore:` nei trigger.

### Documentation
- [ ] **D1** — `docs/deploy.md` §Routine deploys riscritto: apre con una frase che dichiara "Sotto condizioni normali nessuna azione manuale è necessaria; se `deploy.yml` segnala uno smoke-test failure il release precedente sta ancora servendo — vedi §Common failure modes". Sotto-sezioni "Automatic (default)" + "Manual fallback" che preservano il comando `git push gigalixir main`.
- [ ] **D2** — `docs/deploy.md` §Common failure modes esteso con righe CD-specifiche, raggruppate sotto un caption bold `**CD-specific failures**` per separarle dai failure pre-esistenti del manual deploy. Coperti almeno: (a) `workflow_run` non parte (CI failed o branch ≠ main); (b) deploy.yml job fallisce sul push (auth/SHA stale/Gigalixir build error); (c) smoke test in retry-loop e poi fail (interpretazione: "build OK + migrate OK + /health non raggiunge 200 in 150s — release precedente ancora live"); (d) "could not obtain lock" sul migrate se l'operatore lancia manualmente in parallelo (R7).
- [ ] **D3** — Nuova §"GitHub Actions secrets" che lista i 4 secrets (`GIGALIXIR_EMAIL`, `GIGALIXIR_API_KEY`, `GIGALIXIR_APP_NAME`, `PHX_HOST`), il path UI per settarli (`Settings → Secrets and variables → Actions → New repository secret`), e una frase di **ordering constraint**: "Set these before merging slice 13, otherwise the first `workflow_dispatch` will fail at the Authenticate step." Pinned via token.
- [ ] **D4** — Nuova §"First-time activation" che spiega: "Il merge che introduce `deploy.yml` non triggera un deploy automatico — `workflow_run` richiede che il workflow sia già su `main` quando l'evento upstream parte. Subito dopo il merge, l'operatore lancia un `workflow_dispatch` manuale dalla UI Actions per validare la pipeline. Da quel momento ogni CI verde su main triggera il deploy." Pinned via token.
- [ ] **D5** — `docs/deploy.md` annota una nota sulla sicurezza delle migration: "La pipeline CD applica ogni migration pendente automaticamente. Per il database schema attuale (additive only) questo è sicuro anche se i container web sono ancora in rolling update. Per future migration breaking (drop colonna, rename), pausa la pipeline CD via `workflow_dispatch` disabilitato o pianifica downtime."

### Operational
- [ ] **O1** — Nessun cambio a Elixir/Dockerfile/runtime.exs/mix.exs/release.ex.
- [ ] **O2** — Nessun nuovo Hex dep.
- [ ] **O3** — Test suite resta verde.
- [ ] **O4** — Validation manuale post-merge in **due fasi**:
  - **O4a (bootstrap)** — Subito dopo il merge, l'operatore lancia `workflow_dispatch` manuale. Il job deve completare verde end-to-end (push + migrate + smoke test). Risolve l'ambiguità di R4: il primo deploy reale è il `workflow_dispatch`, non il primo `workflow_run`.
  - **O4b (auto-trigger)** — Il primo `workflow_run` post-bootstrap (es. il commit successivo su main) deve produrre un deploy verde end-to-end senza intervento manuale. Solo a questo punto la pipeline CD è validata.

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

  Scenario: Smoke test failure fails the job (no auto-rollback)
    Given the smoke test never returns 200 within the retry window
    When the step exits non-zero
    Then the workflow run is marked failed
    And NO automatic rollback is performed

  # ── Concurrency ────────────────────────────────────────────────
  Scenario: Two green CI runs in quick succession serialize on deploy
    Given commit A lands on main and ci.yml goes green
    And commit B lands on main before deploy.yml for A starts
    And ci.yml for B also goes green
    When deploy.yml fires for both
    Then both runs are placed in the concurrency group "deploy-prod"
    And the second run waits for the first to finish
    And neither run is cancelled

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

  Scenario: Slice 13 does NOT add Slack/Discord/PagerDuty notifications
    When I read deploy.yml
    Then no curl/POST step targets a webhook URL

  Scenario: Slice 13 does NOT change ci.yml's contract
    When I read .github/workflows/ci.yml
    Then no step pushes to gigalixir
    And no step references GIGALIXIR_* secrets

  Scenario: Slice 13 does NOT skip deploys on docs-only changes
    Given a commit on main only modifies files under docs/
    And ci.yml goes green
    When deploy.yml fires
    Then it runs the full push + migrate + smoke-test sequence

  # ── Manual fallback parity ─────────────────────────────────────
  Scenario: Manual `git push gigalixir main` still works as documented
    When the developer follows docs/deploy.md §Routine deploys
    Then the manual flow still produces a working deploy
```

## Steps

> Ogni step segue RED → GREEN → REFACTOR. Il file di test
> `test/ideajar/deploy_workflow_test.exs` cresce step-by-step;
> ad ogni RED il test fallisce, ad ogni GREEN passa con il diff
> minimo nel workflow YAML.

### Step 1 — Skeleton workflow + trigger + concurrency

**Complexity**: standard
**Scenarios**: "Green CI run on main triggers a deploy", "Failed CI run on main does NOT trigger a deploy", "Green CI run on a feature branch does NOT trigger a deploy", "Manual redeploy via workflow_dispatch", "Two green CI runs in quick succession serialize on deploy"
**Spec mapping**: W2, W3, W4, W5 (W1 a Step 7)

**RED** — `test/ideajar/deploy_workflow_test.exs` (new):
- Test "deploy.yml exists" — `File.exists?(".github/workflows/deploy.yml")` → true
- Test "triggers on workflow_run for CI completion" — content contains `workflow_run:` AND `workflows: ["CI"]` AND `types: [completed]`
- Test "triggers on workflow_dispatch" — content contains `workflow_dispatch:`
- Test **W4 exact** "deploy job `if:` matches the canonical expression" — content contains the exact substring (whitespace-normalized): `(github.event_name == 'workflow_dispatch') || (github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.head_branch == 'main')`
- Test **W4 negative** — content does NOT contain `conclusion == 'success' || github.event.workflow_run.head_branch` (would deploy on failed CI for main, or success for any branch)
- Test "concurrency serializes deploys" — content contains `group: deploy-prod` AND `cancel-in-progress: false`

**GREEN**:
- Crea `.github/workflows/deploy.yml` con `name`, `on:` (entrambi i trigger), `concurrency:` (deploy-prod, cancel-in-progress: false), un job `deploy` con l'`if:` esatto e un singolo step placeholder `run: echo "skeleton"` (YAML valido).

**REFACTOR**: helper privato `read_deploy_yml/0` nel test module se più di 3 test lo riusano.

**Files**:
- `test/ideajar/deploy_workflow_test.exs` (new)
- `.github/workflows/deploy.yml` (new)

**Commit (draft)**: `Add the deploy workflow skeleton gated to workflow_dispatch or a green CI run on main`

---

### Step 2 — Checkout + CLI Gigalixir + auth + remote

**Complexity**: standard
**Scenarios**: "Successful push deploys the validated SHA", "Checkout uses full history so Gigalixir accepts the push", "Manual redeploy via workflow_dispatch", "Missing GIGALIXIR_API_KEY fails the workflow with a clear message" (parziale, vedi note A3), "Secrets are read at the job level, not echoed to logs"
**Spec mapping**: A1a, A1b, A2, A3, A4

**RED** (estendi `deploy_workflow_test.exs`):
- Test **A1a** "checkout uses fetch-depth 0" — match su `actions/checkout@v4` + `fetch-depth: 0`
- Test **A1b workflow_run case** — match su `${{ github.event.workflow_run.head_sha }}` come `ref:`
- Test **A1b workflow_dispatch case** — match su `refs/heads/main` come `ref:` (alternativa o secondo step di checkout). Negative pin doppio: il file NON contiene (a) `ref: ${{ github.sha }}` come unica forma di checkout, NÉ (b) la regex `ref:\s*\$\{\{\s*github\.sha\s*\|\|` (typo trap: `github.sha` è sempre truthy su `workflow_run`, quindi il fallback `|| 'refs/heads/main'` non scatterebbe mai — il `head_sha` corretto è `github.event.workflow_run.head_sha`).
- Test **A2** "installs gigalixir CLI via pipx" — match su `pipx install gigalixir`
- Test **A3 presence** "authenticates with email + API-key secrets" — match su `secrets.GIGALIXIR_EMAIL` AND `secrets.GIGALIXIR_API_KEY` AND `gigalixir login`
- Test **A3 negative** "no echo of GIGALIXIR_* secrets" — il file NON contiene `echo $GIGALIXIR_API_KEY`, `echo "$GIGALIXIR_EMAIL"`, `printf` su quei tokens (regex anchor: `(echo|printf).*GIGALIXIR_`)
- Test **A4** "adds gigalixir remote with the app-name secret" — match su `gigalixir git:remote "$GIGALIXIR_APP_NAME"` con secret `GIGALIXIR_APP_NAME`

> **Coverage note esplicita** (A3): "missing API key" failure è behavioural — `gigalixir login` deve fallire a runtime. Lo unit test conferma solo la presenza dei riferimenti ai secrets, NON che la CLI fallisca correttamente. Quel comportamento è coperto solo da O4 (manual smoke). Documentato in §Risks come parte di R7.

**GREEN**: aggiungi gli step `Checkout` (con `ref` distinto per i due trigger via condizione `if`), `Install gigalixir CLI`, `Authenticate`, `Add gigalixir remote` al job `deploy`. Rimuovi il placeholder `echo "skeleton"`.

**REFACTOR**: env block consolidato a livello job invece che ripetuto sui singoli step se più di uno step legge le stesse var.

**Files**: `.github/workflows/deploy.yml`, `test/ideajar/deploy_workflow_test.exs`.

**Commit (draft)**: `Check out the validated SHA on workflow_run and the main tip on dispatch, then authenticate against Gigalixir`

---

### Step 3 — Push + migrate + step ordering

**Complexity**: standard
**Scenarios**: "Successful push deploys the validated SHA", "Push failure fails the job", "Migrate runs after every successful deploy", "Migrate failure fails the job and skips the smoke test"
**Spec mapping**: P1, P2, P3, M1, M2

**RED**:
- Test **P1** "push step exists with the documented git command" — match su `git push gigalixir HEAD:refs/heads/main`
- Test **M1** "migrate step exists with the Release.migrate eval" — match su `gigalixir run -- bin/ideajar eval "Ideajar.Release.migrate"`
- Test **P2 (negative)** "no continue-on-error: true anywhere in the file" — la stringa esatta `continue-on-error: true` NON appare nel file
- Test **P3 (ordering)** "Push precedes Migrate precedes Smoke test" — usando `String.split` su step delimiters (es. `- name:` ricerca offset), asserisci che l'offset di `name: Push` < offset di `name: Migrate`. Lo step "Smoke test" sarà aggiunto in Step 4; questo test viene esteso in quel passo.

**GREEN**: aggiungi gli step `Push` e `Migrate` in ordine. P2 + P3 sono già garantiti per costruzione — i test passano subito dopo aver scritto gli step.

**REFACTOR**: nessuno previsto.

**Files**: `.github/workflows/deploy.yml`, `test/ideajar/deploy_workflow_test.exs`.

**Commit (draft)**: `Push the validated SHA to Gigalixir and run the release migrator from the same job`

---

### Step 4 — Smoke test con retry + recovery hint

**Complexity**: standard
**Scenarios**: "Smoke test confirms the deploy is live", "Smoke test failure fails the job (no auto-rollback)"
**Spec mapping**: S1, S2, S3, S4, S5; estende P3 con il terzo ordering pin

**RED**:
- Test **S1** "smoke test curls /health on PHX_HOST" — match su `curl -fsS "https://$PHX_HOST/health"`
- Test **S2** "retries 10 times at 15s intervals" — match su `for i in $(seq 1 10)` AND `sleep 15`
- Test **S2 body match** — match su `"status":"ok"` (literal substring)
- Test **S3 happy-path exit code** — match strutturale: il pattern `if [...]; then\n *exit 0` (o equivalente bash dove `exit 0` è dentro un blocco condizionale) appare nel file. Negative pin: il file NON contiene `exit 0` come prima riga di uno step (cioè exit 0 sempre).
- Test **S3 failure exit code** — `exit 1` appare DOPO l'ultima istanza di `sleep 15` nel file (offset-based check). Garantisce che il loop fallisca a esaurimento retry.
- Test **S4** "failure prints recovery hint" — il file contiene tutti i token: `previous release`, `gigalixir logs`, `gigalixir releases:rollback`. Pinned in modo che un futuro edit non rimuova il messaggio.
- Test **P3 esteso** — offset di `name: Migrate` < offset di `name: Smoke test`.

**GREEN**: aggiungi step `Smoke test` con bash inline:

```bash
for i in $(seq 1 10); do
  if curl -fsS "https://$PHX_HOST/health" | grep -q '"status":"ok"'; then
    echo "Smoke test passed on attempt $i."
    exit 0
  fi
  sleep 15
done
echo "Smoke test failed after 10 attempts; previous release likely still serving."
echo "Inspect: gigalixir logs"
echo "Rollback if needed: gigalixir releases:rollback"
exit 1
```

**REFACTOR**: bash inline è ~10 righe, no estrazione necessaria. Se in futuro il messaggio cresce, valutare uno script in `scripts/smoke_test.sh` (deferred).

**Files**: `.github/workflows/deploy.yml`, `test/ideajar/deploy_workflow_test.exs`.

**Commit (draft)**: `Poll /health with a ten-attempt retry and surface a recovery hint when it fails`

---

### Step 5 — Out-of-scope guards (test pins)

**Complexity**: trivial
**Scenarios**: "Slice 13 does NOT add automatic rollback", "Slice 13 does NOT add Slack/Discord/PagerDuty notifications", "Slice 13 does NOT change ci.yml's contract"
**Spec mapping**: OS1a, OS1b, OS1c, OS2, OS3, OS4

**RED**:
- Test **OS1a** "ci.yml does not push to gigalixir" — leggi `.github/workflows/ci.yml`, NON contiene `gigalixir`
- Test **OS1b** "ci.yml does not reference GIGALIXIR_* secrets" — il file NON contiene `GIGALIXIR_`
- Test **OS1c** "ci.yml's workflow name is exactly 'CI'" — il file CONTIENE la riga `name: CI` (case-sensitive). Pin simmetrico al `workflows: ["CI"]` di deploy.yml: rinominare CI rompe il trigger di deploy senza errori visibili.
- Test **OS2** "deploy.yml does not invoke releases:rollback as a bare command" — nessuna riga matcha la regex `^\s*gigalixir releases:rollback\b`. La stringa è ammessa solo all'interno di un `echo`/`printf` (S4 recovery hint).
- Test **OS3 domain literals** "no Slack/Discord/PagerDuty domains" — il file NON contiene `hooks.slack.com`, `discord.com/api/webhooks`, `events.pagerduty.com`
- Test **OS3 outbound POST** "no curl POST patterns" — il file NON contiene `curl -X POST`, `curl --data`, né regex `curl.*-d "` (heuristica per webhook generici)
- Test **OS3 third-party action** "no notify-style action references" — regex `uses: .*(notify|slack|discord|pagerduty)` non matcha
- Test **OS4** "deploy.yml does not use path filters" — il file NON contiene `paths:` né `paths-ignore:`

**GREEN**: i test passano già — sono pin di assenza/presenza simmetrica. Conferma che entrambi i file sono puliti.

**REFACTOR**: nessuno.

**Files**: `test/ideajar/deploy_workflow_test.exs`.

**Commit (draft)**: `Pin the slice 13 out-of-scope boundary so future edits cannot add rollback, webhooks, or rename CI silently`

---

### Step 6 — Aggiornamento `docs/deploy.md`

**Complexity**: standard (mechanical doc edit con test pin esteso)
**Scenarios**: "Manual `git push gigalixir main` still works as documented"
**Spec mapping**: D1, D2, D3, D4, D5

**RED** (estendi `deploy_workflow_test.exs` o nuovo `deploy_doc_test.exs`):
- Test **D1 framing** — `docs/deploy.md` contiene la frase apertura "no manual action is needed" (o equivalente IT) e il riferimento a "previous release" + "still serving" per il caso smoke-test fail
- Test **D1 sub-headings** — il file contiene sia "Automatic" sia "Manual fallback" come heading sotto §Routine deploys
- Test **D1 manual parity** — il file mantiene il comando `git push gigalixir main` (regression pin: il manual fallback non viene cancellato)
- Test **D2 grouping** — §Common failure modes contiene un caption bold `**CD-specific failures**`
- Test **D2 CD failures** — la tabella contiene almeno 4 righe nuove con tokens: `workflow_run`, `Authenticate`, `smoke test`, `lock` (per il migrate concurrent fail)
- Test **D2 smoke-test interpretation** — il file contiene una frase con tokens: `previous release` AND `still serving` AND `150` (s di retry budget)
- Test **D3 secrets** — `docs/deploy.md` contiene tutti e quattro i nomi: `GIGALIXIR_EMAIL`, `GIGALIXIR_API_KEY`, `GIGALIXIR_APP_NAME`, `PHX_HOST`, e contiene il path `Settings → Secrets and variables → Actions`
- Test **D3 ordering constraint** — il file contiene la frase "before merging" nel contesto secrets (regex: `(before merging|prima del merge)`)
- Test **D4 first-time activation** — il file contiene un heading "First-time activation" e i tokens `workflow_dispatch` AND (`bootstrap` o `first deploy`)
- Test **D5 migration safety** — il file contiene una nota con tokens: `additive` AND (`breaking` OR `drop colonna` OR `rename`)

**GREEN**:
- Apri §Routine deploys con la frase di framing "Sotto condizioni normali nessuna azione manuale è necessaria; in caso di smoke-test failure il release precedente sta ancora servendo — vedi §Common failure modes."
- Sotto-sezione "Automatic (default)": descrive il flusso CD post-merge.
- Sotto-sezione "Manual fallback": preserva `git push gigalixir main` + `gigalixir run -- bin/ideajar eval "Ideajar.Release.migrate"` come oggi.
- §Common failure modes: caption bold `**CD-specific failures**` + 4 righe nuove (workflow_run no-fire, Authenticate fail, push fail su SHA stale, smoke test in retry-loop con interpretazione "150s window, previous release likely still serving", advisory lock fail su migrate manuale concurrent).
- Nuova §"GitHub Actions secrets": lista 4 secrets, path UI, ordering constraint "Set before merging slice 13".
- Nuova §"First-time activation": il merge di deploy.yml NON triggera il primo deploy; lanciare `workflow_dispatch` manuale subito dopo per bootstrap + validazione.
- Nuova nota "Migration safety": pipeline applica ogni migration pendente; per il database schema attuale (additive) safe; per future migration breaking (drop colonna, rename) richiesto pause CD o downtime.

**REFACTOR**: heading hierarchy consistente con lo stile esistente del file; no markdown linter.

**Files**: `docs/deploy.md`, `test/ideajar/deploy_workflow_test.exs` (estensione, no file separato per evitare duplicazione setup).

**Commit (draft)**: `Document the auto-deploy path, the secrets, the first-time activation, and the migration safety boundary`

---

### Step 7 — Pre-PR gate (incluso `actionlint`) + verifica suite

**Complexity**: trivial
**Scenarios**: tutti
**Spec mapping**: W1, O1, O2, O3

**RED**:
- `mix test` deve restare verde (oltre ai nuovi test deploy).
- `actionlint .github/workflows/deploy.yml` deve uscire 0 (W1).

**GREEN**: esegui in sequenza:
```bash
mix compile --warnings-as-errors
mix format --check-formatted
mix credo
mix deps.audit
mix test
actionlint .github/workflows/deploy.yml   # se actionlint manca: brew install actionlint OR go install github.com/rhysd/actionlint/cmd/actionlint@latest
```
Tutto verde.

**REFACTOR**: nessuno.

**Files**: nessuno (gate passive).

**Commit**: nessun commit aggiuntivo se i precedenti hanno coperto tutto. Se il gate scopre una regressione (es. actionlint segnala un'invalidità), fix mirato + commit dedicato che riprende lo step di provenienza.

---

## Complexity Classification

| Step | Rating | Justification |
|---|---|---|
| 1 | standard | Nuovo file workflow + nuovo file test, logica YAML semi-dichiarativa |
| 2 | standard | Estende workflow + test su auth + secrets handling |
| 3 | standard | Push + migrate sono i due step di delivery — il cuore del workflow |
| 4 | standard | Bash retry inline; logica condizionale con effetti netti su pass/fail |
| 5 | trivial | Test pin di assenza, no codice nuovo |
| 6 | standard | Doc edit ma con test pin esplicito su contenuto |
| 7 | trivial | Gate passivo |

## Pre-PR Quality Gate

- [ ] `mix compile --warnings-as-errors` passa
- [ ] `mix format --check-formatted` passa
- [ ] `mix credo` passa
- [ ] `mix deps.audit` passa
- [ ] `mix test` passa (incluso il nuovo `deploy_workflow_test.exs`)
- [ ] `actionlint .github/workflows/deploy.yml` esce 0
- [ ] `/code-review` su `.github/workflows/deploy.yml`, `docs/deploy.md`, `test/ideajar/deploy_workflow_test.exs`
- [ ] `docs/deploy.md` aggiornato e pin testati
- [ ] PR description elenca i 4 secrets da settare prima del merge **e** il fatto che subito dopo il merge va lanciato un `workflow_dispatch` manuale per bootstrap (R4 + O4a)

## Risks & Open Questions

- **R1 — Secrets non settati al merge.** Se i 4 secrets non sono in repo prima del merge, il primo `workflow_run` post-merge fallisce sul login step. *Mitigazione*: la PR description (e `docs/deploy.md` D3) elencano esplicitamente i secrets richiesti; il developer li imposta in `Settings → Secrets and variables → Actions` prima di mergiare. Risk basso (couple-of-2 ops, awareness alta).

- **R2 — `pipx install gigalixir` lentezza/flake.** Il package è piccolo, install ~10s. Se il PyPI ha un outage temporaneo, il job fallisce. *Mitigazione*: GH Actions retry built-in non c'è, ma il deploy non è on-call critico — manual `workflow_dispatch` rerun copre il caso. Documentato in §Common failure modes.

- **R3 — Cold-start oltre il retry budget.** Il free tier Gigalixir può occasionalmente impiegare più di un minuto a tornare healthy dopo un build pesante. *Mitigazione*: retry alzato in revisione a 10×15s = 150s (DD-S13-7), ampio margine sul cold-start tipico. Se in pratica vediamo flake oltre i 150s, ulteriore tuning in slice futura.

- **R4 — `workflow_run` non triggera al primo merge se `deploy.yml` non era ancora su main.** GH Actions richiede che il workflow esista sul branch default per essere triggerato da `workflow_run`. *Mitigazione*: O4a (manual `workflow_dispatch` post-merge) è acceptance criterion, non solo nota. Documentato anche nel runbook §"First-time activation" (D4) e nella PR description.

- **R5 — Token-based test assertions sono fragili al refactor del workflow.** Es. se in futuro qualcuno cambia `pipx install gigalixir` in `pip install --user gigalixir`, il test fallisce anche se la nuova forma è equivalente. *Mitigazione*: questo è il *purpose* dei test pin — forzano una decisione consapevole. Aggiornare il test in pari con il workflow è esattamente il workflow desiderato. `actionlint` (W1) chiude il gap "lessicale vs comportamentale" sui costrutti GH Actions invalidi.

- **R6 — `workflow_run` può deployare un SHA superato.** GH Actions non cancella i workflow_run derivati quando l'upstream `ci.yml` viene cancellato/superato. Combinato con `cancel-in-progress: false` sul deploy (DD-S13-3), una raffica di commit può accodare deploy di SHA non più tip-of-main. *Mitigazione*: il SHA che `workflow_run` passa al deploy è quello che CI ha effettivamente validato — anche se nel frattempo è arrivato un commit più nuovo, deployare un SHA validato è correct, non sbagliato. Il commit più nuovo triggera un proprio `workflow_run` quando la sua CI completa. Net effect: serializzazione corretta, latenza in burst (vedi R8). No fix necessario; documentato.

- **R7 — Race operatore manuale vs CD su migrate.** Se l'operatore lancia manualmente `gigalixir run -- bin/ideajar eval "Ideajar.Release.migrate"` mentre il job CD esegue lo stesso, il secondo migrator può fallire con "could not obtain lock" (Postgres advisory lock). *Mitigazione*: documentato in `docs/deploy.md` (D2) — gli operatori usano `workflow_dispatch` invece del manual `gigalixir run` quando la CD è attiva. Il fail è loud (errore esplicito), non silente.

- **R8 — Burst di N commit ravvicinati può stretchare la queue di deploy a N×durata.** `cancel-in-progress: false` serializza, non droppa. Per couple-of-2 user con commit infrequenti questo è un non-problema, ma vale annotarlo. *Mitigazione*: NESSUNA in questa slice. Se in futuro la frequenza di commit cresce, valutare logica di coalescing (cancel pending, keep running) come slice separata.

- **OQ1 — Quale email associata a `GIGALIXIR_EMAIL`?** Quella usata in `gigalixir signup` (slice 11b). User da settare in Actions secrets prima del merge. Nessuna decisione tecnica aperta — è solo onboarding.

- **OQ2 — Frequenza reale di "ho dimenticato di deployare"?** *Risolta dall'utente 2026-05-04*: la motivazione non è un dolore puntuale ma la scelta strategica di adottare un regime di **continuous delivery**. Il deploy automatico è il modello operativo desiderato, indipendente dalla frequenza pregressa di "ho dimenticato di deployare". Slice giustificata.

## Plan Review Summary

Quattro reviewer dispatchati in parallelo, due iterazioni. Verdict finale: **tutti approve**.

### Iteration 1 — needs-revision (4/4)

7 blocker totali consolidati:
- **Acceptance B1**: `if:` token tests non distinguevano AND da OR → exact-substring match della forma canonica + negative pin contro `||` su `head_branch`.
- **Acceptance B2**: P2/M2 step-ordering non asserito → nuovo P3 con offset comparison (`Push` < `Migrate` < `Smoke test`).
- **Acceptance B3**: smoke test exit codes non testati → S3 strutturale (`exit 0` in conditional, `exit 1` post-loop).
- **Design B2**: `workflow_dispatch` checkout → `refs/heads/main`, non `github.sha` (asimmetria pinnata in A1b).
- **UX B1**: smoke test silente → S4 con echo dei comandi di recovery (`gigalixir logs`, `gigalixir releases:rollback`).
- **UX B2**: first-time activation gotcha solo in R4 → nuovo D4 acceptance criterion + O4a/O4b split.
- **Strategic B6**: race migrate-vs-cutover non documentata → DD-S13-6 esteso con assunzione "additive only" + D5 per migration breaking.

10 warning ad alto valore applicate: bump retry 5×10s → 10×15s (Strategic W2), `actionlint` come gate W1 (Design W5/Acceptance O8), pin simmetrico `name: CI` in OS1c (Design W6), R6 staleness queue + R7 advisory lock + R8 burst latency (Design W1/W3/W4), heuristica OS3 più ampia (Acceptance W7), framing `docs/deploy.md` D1/D2/D3/D5 (UX W3/W4/W5), coverage gap A3 dichiarato esplicito (Acceptance W4), DD-S13-11 lock-in Gigalixir (Strategic O5).

### Iteration 2 — approve (4/4)

- **Acceptance**: approve. Tutti gli 8 punti previously-blocked risolti, nessun nuovo problema.
- **Design**: approve. 6 punti risolti. 3 observation residue applicate (allineamento R3, Gherkin scenario 10×15s, negative pin doppio su A1b per typo `github.sha`).
- **UX**: approve. 5 punti risolti. 1 observation applicata (R3 stale).
- **Strategic**: approve. 4 punti risolti. 1 observation applicata (riallineamento spec `docs/specs/ci-auto-deploy.md` su 10×15s).

### Open question per l'utente (non bloccante)

**OQ2** rimane aperta come domanda strategica per la review umana: la frequenza reale di "ho dimenticato di deployare" giustifica la slice ora, o è disciplina pre-emptive? Da confermare con l'utente prima dell'approvazione finale del plan.
