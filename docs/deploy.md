# Production deploy — Gigalixir

> Slice 11b + 13 runbook. CD is active: every green CI run on `main`
> deploys automatically via `.github/workflows/deploy.yml`. The manual
> `git push gigalixir main` remains a fallback — see §Routine deploys
> → Manual fallback.

## Prerequisites

- Local clone is on `main` with the slice 11b code committed.
- `gigalixir` CLI installed. On macOS: `brew install gigalixir`. On Debian/Ubuntu (PEP 668-managed Python): `pip install --user --break-system-packages gigalixir` or `pipx install gigalixir`. Verify: `gigalixir --help`.
- Docker (optional, for a local image smoke test before pushing).
- A working credit card on the Gigalixir account — required even for the free tier (no charge unless you exceed the threshold).

## One-time setup

### 1. Sign up

```bash
gigalixir signup    # follow prompts (email, payment method)
gigalixir login
```

### 2. Create the app

```bash
gigalixir apps:create -n ideajar
```

If `ideajar` is already taken, fall back to `ideajar-app` or `ideajar-prod`.

Add the `gigalixir` git remote (the `apps:create` command does **not** add it automatically):

```bash
gigalixir git:remote ideajar    # use the app name you just claimed
git remote -v                   # verify "gigalixir" remote points to git.gigalixir.com
```

### 3. Provision the Postgres free-tier addon

```bash
gigalixir pg:create --free
```

This sets the `DATABASE_URL` env var on the app automatically. Verify:

```bash
gigalixir config | grep DATABASE_URL
```

### 4. Set the remaining env vars

```bash
# Generate a fresh 64-byte secret base — never reuse the dev one.
gigalixir config:set SECRET_KEY_BASE="$(mix phx.gen.secret)"

# Workspace password — pick something memorable for the couple.
# Min 16 chars enforced by Ideajar.Config.validate!.
gigalixir config:set WORKSPACE_PASSWORD="<your-shared-password>"

# Default subdomain. If you claimed a different app name above, use
# <app-name>.gigalixirapp.com instead.
gigalixir config:set PHX_HOST="ideajar.gigalixirapp.com"
```

Confirm everything is in place:

```bash
gigalixir config
# Expected keys: DATABASE_URL, PHX_HOST, SECRET_KEY_BASE, WORKSPACE_PASSWORD
```

### 5. First push

```bash
git push gigalixir main
```

Gigalixir reads `Dockerfile` at the repo root, builds the multi-stage image, and starts a container. Watch the build:

```bash
gigalixir logs
```

Build typically takes 3-5 minutes the first time (deps + assets + release). Subsequent pushes hit the Docker layer cache and finish in 1-2 minutes.

### 6. Run migrations

The release does not auto-migrate on container start. Trigger it manually after the first deploy and after any deploy that ships a new migration:

```bash
gigalixir run -- bin/ideajar eval "Ideajar.Release.migrate"
```

This loads the application without booting the supervision tree, runs every pending migration via `Ecto.Migrator`, and exits.

### 7. Verify

```bash
# Health probe
curl -i https://ideajar.gigalixirapp.com/health
# → HTTP/2 200 + {"status":"ok"}

# Login flow
open https://ideajar.gigalixirapp.com/
# → /login form, submit WORKSPACE_PASSWORD, land on the idea list
```

## GitHub Actions secrets

The CD pipeline (`.github/workflows/deploy.yml`) authenticates to Gigalixir using four repository secrets. **Set them before merging slice 13**, otherwise the first `workflow_dispatch` will fail at the Authenticate step.

Path: `Settings → Secrets and variables → Actions → New repository secret`.

| Secret | Value | Notes |
|---|---|---|
| `GIGALIXIR_EMAIL` | The email used at `gigalixir signup` | |
| `GIGALIXIR_API_KEY` | API key from `gigalixir api_key` (or the dashboard) | The Gigalixir CLI picks it up automatically via the `GIGALIXIR_*` env-var prefix |
| `GIGALIXIR_APP_NAME` | The app name claimed in step 2 (e.g. `ideajar`) | Lets `deploy.yml` parameterize without hardcoding |
| `PHX_HOST` | `<app>.gigalixirapp.com` | Used by the smoke-test step to curl `/health` |

## First-time activation

The merge that introduces `deploy.yml` does **not** trigger a deploy automatically. GitHub Actions requires the target workflow to already exist on the default branch when the upstream `workflow_run` event fires — the merge itself is the placement, so the upstream CI run that produced the merge cannot trigger it. To bootstrap the first deploy:

1. After the merge lands on `main`, open `Actions → Deploy to Gigalixir → Run workflow`.
2. Select the `main` branch and click `Run workflow`.
3. The job runs through push + migrate + smoke test. This is the first real deploy.
4. From the next commit onward, every green CI run on `main` triggers `deploy.yml` automatically.

If the bootstrap run fails, the most likely cause is a missing or wrong secret — see §Common failure modes.

## Migration safety

The CD pipeline applies every pending migration on every deploy via `Ideajar.Release.migrate`. For the **additive** schema changes used in slices 1-12 (new tables, new nullable columns) this is safe even while the rolling update of web containers is in flight: old code does not reference the new columns, new code does.

For **breaking** schema changes (drop column, rename, type narrowing) the same automatic application is unsafe — old containers can hit a column that no longer exists and crash. Before merging a breaking migration:

1. Either pause the CD pipeline (edit the `if:` on the deploy job to `if: false`, or temporarily revert `deploy.yml`) and apply the migration in a coordinated manual deploy with downtime, or
2. Split the change into two deploys: deploy 1 stops referencing the column (safe rolling change), then deploy 2 drops it.

The same advisory applies to migrations that add a NOT NULL column without a default: backfill in deploy 1, add the constraint in deploy 2.

## Routine deploys

Under normal conditions no manual action is needed: every green CI run on `main` triggers `.github/workflows/deploy.yml`, which pushes, migrates, and smoke-tests automatically. If `deploy.yml` reports a smoke-test failure in the Actions tab, the previous release is still serving traffic — see §Common failure modes for the recovery path.

### Automatic (default)

1. Merge into `main` via PR.
2. CI (`.github/workflows/ci.yml`) runs. If green, GitHub fires `workflow_run` against `deploy.yml`.
3. `deploy.yml` checks out the validated SHA, installs the Gigalixir CLI, authenticates with the repo secrets, runs `git push gigalixir HEAD:refs/heads/main`, applies pending migrations via `Ideajar.Release.migrate`, and polls `https://$PHX_HOST/health` (10×15s, 150s budget) before marking the run green.
4. On failure, GitHub sends the default failure-notification email to repo admins.

### Manual fallback

When the CD pipeline is intentionally paused (e.g., for a breaking schema migration — see §Migration safety) or when a redeploy is needed without a new commit:

```bash
git push gigalixir main
gigalixir run -- bin/ideajar eval "Ideajar.Release.migrate"  # only if new migrations landed
```

For redeploys without code changes, prefer running the `Deploy to Gigalixir` workflow via `Actions → Deploy to Gigalixir → Run workflow` (`workflow_dispatch`); it follows the same path as the automatic trigger and avoids drift between the two channels.

That's it. No release notes, no manifest bumps — Gigalixir handles versioning internally.

## Rollback

### Application rollback

Gigalixir keeps the last N releases. List them:

```bash
gigalixir releases
```

Roll the running container back to a previous release version:

```bash
gigalixir releases:rollback -r <version>
```

Omit `-r <version>` to roll back one release (the second-most-recent).

### Database rollback

If a deploy shipped a destructive migration that needs to be rolled back, target a specific version:

```bash
# E.g. roll back everything newer than 20260503000001
gigalixir run -- bin/ideajar eval "Ideajar.Release.rollback(Ideajar.Repo, 20260503000001)"
```

The `Ideajar.Release.rollback/2` function is defined in `lib/ideajar/release.ex`.

## Logs

Stream container logs (tail is the default; Ctrl-C to stop):

```bash
gigalixir logs
```

Pass `-t` / `--no_tail` for a one-shot dump instead of a live stream.

Gigalixir does not expose Postgres-specific log streaming on the free tier. App-level Postgres errors surface in `gigalixir logs` (the application prints the `Postgrex.Error` stacktrace).

## Backups & restore

Gigalixir's free tier ships one nightly snapshot. Find the database id first with `gigalixir pg`, then list and restore:

```bash
gigalixir pg                                              # → grab the database id
gigalixir pg:backups -d <database-id>
gigalixir pg:backups:restore -d <database-id> -b <backup-id>
```

The free tier does not expose an on-demand snapshot command — only the nightly snapshot is available. Before risky changes, either rely on the most recent nightly or take a manual `pg_dump` via `gigalixir pg:psql` redirected to a local file.

## Slice 10 PWA manual gates (post-deploy)

Once the app is live on HTTPS, complete the gates that were deferred from slice 10:

1. **Lighthouse PWA audit** (Chrome DevTools → Lighthouse → PWA category):
   - "Installable" — green
   - "Has a registered service worker" — green
   - "Manifest has a maskable icon" — green
2. **Android install** — visit on Chrome, look for the install icon in the address bar. Tap → app icon appears on home screen with the maskable design. Open it: standalone display, no browser chrome.
3. **iOS Safari Add-to-Home-Screen** — visit on iOS Safari, Share → Add to Home Screen. Icon appears, tap opens in standalone.

Record the audit results in this file (or a follow-up note) so the gate is durably closed.

## Common failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Build fails at `mix deps.get` | Hex.pm transient outage | `gigalixir releases:rollback` to a known-good release, retry push later |
| Build fails at `mix release` | Compilation error you also have locally | Fix locally, `mix release` should pass, push again |
| App boots then crashes immediately | Missing env var | `gigalixir logs` will show the raise message. `gigalixir config:set <var>=...` |
| 503 from Gigalixir edge | App didn't start within startup timeout | Check logs for slow init; `gigalixir ps` to verify worker count |
| `/health` returns 200 but `/` redirects to `/login` even when authenticated | Cookie domain mismatch | Verify `PHX_HOST` matches the actual hostname (subdomain claimed at signup) |
| `Postgrex.Error: connection refused` post-deploy | DATABASE_URL not set or DB not provisioned | `gigalixir config | grep DATABASE_URL`; if empty, `gigalixir pg:create --free` |

**CD-specific failures**

| Symptom | Cause | Fix |
|---|---|---|
| `workflow_run` never fires after a merge | CI failed, or push was on a non-`main` branch — `deploy.yml` requires `conclusion == 'success'` AND `head_branch == 'main'` | Re-run CI; if main really is green, run the `Deploy to Gigalixir` workflow manually (`workflow_dispatch`) |
| `deploy.yml` job fails on Authenticate step | One of `GIGALIXIR_EMAIL` / `GIGALIXIR_API_KEY` / `GIGALIXIR_APP_NAME` is missing or wrong on the repo | `Settings → Secrets and variables → Actions` → re-add the secret; rerun the workflow |
| `deploy.yml` job fails on Push step | Gigalixir build error (Dockerfile, dep, asset) | `gigalixir logs` — fix locally, push a new commit; previous release is still serving |
| `deploy.yml` smoke test loops 10 times then fails | Build OK, migrate OK, but `/health` did not return 200 within the 150s window — likely cold-start exceeded budget OR the new release crash-looped | Check `gigalixir logs`; the **previous release is still serving** traffic. If the new release is hard-broken, `gigalixir releases:rollback` |
| Migrate step fails with `could not obtain lock` | Operator ran `gigalixir run -- bin/ideajar eval "Ideajar.Release.migrate"` manually while CD was running it | Use `workflow_dispatch` instead of manual `gigalixir run` while the CD pipeline is active |

## Cost (free tier)

- 1 single-instance container, sleeps after 30 min of inactivity (cold start ~5-10s)
- 1 Postgres instance, 10 MB storage, no SSL configurability beyond defaults
- Plenty for a couple-2-user app

If usage grows past the free tier (rare for this audience), upgrade the app via `gigalixir ps:scale` and the database via `gigalixir pg:scale -s <size>` (sizes: 0.6, 1.7, 4, 8, 16, 32, 48, 64, 96).
