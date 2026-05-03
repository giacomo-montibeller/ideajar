# Production deploy — Gigalixir

> Slice 11b runbook. Manual deploy: there is no CI auto-push. Run these
> steps the first time, then `git push gigalixir main` for every
> subsequent release.

## Prerequisites

- Local clone is on `main` with the slice 11b code committed.
- `gigalixir` CLI installed: `pip install gigalixir` (or `brew install gigalixir`). Login: `gigalixir login`.
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
gigalixir create -n ideajar
```

If `ideajar` is already taken, fall back to `ideajar-app` or `ideajar-prod`. The `gigalixir create` command also adds the `gigalixir` git remote; verify with `git remote -v`.

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

## Routine deploys

```bash
git push gigalixir main
gigalixir run -- bin/ideajar eval "Ideajar.Release.migrate"  # only if new migrations landed
```

That's it. No release notes, no manifest bumps — Gigalixir handles versioning internally.

## Rollback

### Application rollback

Gigalixir keeps the last N releases. List them:

```bash
gigalixir releases
```

Roll the running container back to a previous release version:

```bash
gigalixir releases:rollback -n <version>
```

### Database rollback

If a deploy shipped a destructive migration that needs to be rolled back, target a specific version:

```bash
# E.g. roll back everything newer than 20260503000001
gigalixir run -- bin/ideajar eval "Ideajar.Release.rollback(Ideajar.Repo, 20260503000001)"
```

The `Ideajar.Release.rollback/2` function is defined in `lib/ideajar/release.ex`.

## Logs

Stream container logs (Ctrl-C to stop):

```bash
gigalixir logs --tail
```

For Postgres logs:

```bash
gigalixir pg:logs
```

## Backups & restore

Gigalixir's free tier ships one nightly snapshot. List + restore:

```bash
gigalixir pg:backups
gigalixir pg:backups:restore <backup-id>
```

For a fresh manual snapshot before risky changes:

```bash
gigalixir pg:backups:capture
```

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

## Cost (free tier)

- 1 single-instance container, sleeps after 30 min of inactivity (cold start ~5-10s)
- 1 Postgres instance, 10 MB storage, no SSL configurability beyond defaults
- Plenty for a couple-2-user app

If usage grows past the free tier (rare for this audience), upgrade via `gigalixir ps:scale` and `gigalixir pg:plans`.
