# RetroBeam — Fly.io Deployment Guide

RetroBeam is deployed to [Fly.io](https://fly.io), a platform that runs your app as Docker containers on lightweight VMs ("machines"). Fly handles TLS termination, DNS, and provides managed Postgres.

## Prerequisites

1. **Install the Fly CLI** (`flyctl`):

   ```bash
   brew install flyctl
   ```

2. **Authenticate**:

   ```bash
   fly auth login
   ```

   This opens a browser for OAuth. Your credentials are saved to `~/.fly/config.yml`.

## Architecture Overview

```
Internet (HTTPS :443)
  └─▶ Fly Proxy (TLS termination)
        └─▶ RetroBeam machine (internal port 8080)
              └─▶ Fly Postgres (internal IPv6 network)
```

- **1 shared-CPU machine** with 1GB RAM (sufficient for ~50 concurrent users)
- **Fly Postgres** single-node (no HA) — runs as a separate Fly app
- **Secrets** (DATABASE_URL, SECRET_KEY_BASE, etc.) are encrypted and injected as env vars at runtime
- **Migrations** run automatically before each deploy via `release_command` in `fly.toml`

## First-Time Setup

If the app hasn't been created on Fly.io yet, follow these steps:

### 1. Create the Fly app

```bash
fly launch --no-deploy
```

- Pick the app name (`retrobeam`) and region (e.g., `ord` for Chicago)
- Skip the Postgres addon — we'll create it separately for more control
- This generates/updates `fly.toml`

### 2. Provision Fly Postgres

```bash
# Create a single-node Postgres cluster
fly postgres create \
  --name retrobeam-db \
  --region ord \
  --vm-size shared-cpu-1x \
  --initial-cluster-size 1 \
  --volume-size 1

# Attach it to your app (creates the database + sets DATABASE_URL secret)
fly postgres attach retrobeam-db --app retrobeam
```

> **What "attach" does:** Creates a database named `retrobeam` inside the Postgres
> cluster and automatically sets `DATABASE_URL` as an encrypted secret on your app.
> You do NOT need to set DATABASE_URL manually.

### 3. Set secrets

```bash
# Generate a secret key base
mix phx.gen.secret

# Set it (paste the output from above)
fly secrets set SECRET_KEY_BASE=<generated-value>

# Anthropic API credentials (for AI report generation)
fly secrets set ANTHROPIC_API_KEY=<your-key>
fly secrets set ANTHROPIC_MODEL=claude-sonnet-4-20250514
```

### 4. Deploy

```bash
fly deploy
```

## Deploying Updates

After pushing code to `main` and verifying CI passes:

```bash
fly deploy
```

**What happens behind the scenes:**

1. Fly builds the Docker image using the `Dockerfile` (on a remote builder)
2. Runs `release_command` — executes `/app/bin/migrate` (all pending Ecto migrations)
3. Starts the new machine
4. Runs health checks against `/healthz`
5. If healthy → routes traffic to the new machine
6. If unhealthy → rolls back to the previous version

## Common Operations

### Check app status

```bash
fly status
```

### Tail logs

```bash
fly logs
```

### Open the app in browser

```bash
fly open
```

### List secrets

```bash
fly secrets list
```

> Note: Secret values are never shown — only names and timestamps.

### Set or update a secret

```bash
fly secrets set KEY=value
```

Setting a secret automatically triggers a redeployment.

### Connect to the production database

```bash
fly postgres connect --app retrobeam-db
```

This opens a `psql` session against your production database. Use with caution.

### Run a one-off command in production

```bash
fly ssh console --command "/app/bin/retrobeam eval 'IO.puts(:hello)'"
```

For an interactive IEx shell:

```bash
fly ssh console --command "/app/bin/retrobeam remote"
```

### Run migrations manually

Migrations run automatically on deploy, but you can also run them manually:

```bash
fly ssh console --command "/app/bin/migrate"
```

### Rollback a migration

```bash
fly ssh console --command "/app/bin/retrobeam eval 'Retrobeam.Release.rollback(Retrobeam.Repo, 20260101000000)'"
```

Replace `20260101000000` with the migration version you want to roll back to.

### Rollback a deployment

Fly doesn't have a built-in rollback command. To rollback, deploy a previous version:

```bash
# Find the previous image
fly releases

# Deploy a specific image
fly deploy --image <registry/image:tag>
```

Or simply revert the code change and run `fly deploy` again.

## Environment Variables

| Variable | Secret? | Set By | Description |
|----------|---------|--------|-------------|
| `DATABASE_URL` | Yes | `fly postgres attach` | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Yes | `fly secrets set` | Phoenix secret for signing cookies/tokens |
| `ANTHROPIC_API_KEY` | Yes | `fly secrets set` | API key for Anthropic Claude |
| `ANTHROPIC_MODEL` | No | `fly secrets set` | Model for AI features (default: claude-sonnet-4-20250514) |
| `PHX_HOST` | No | `fly.toml` [env] | Hostname for URL generation |
| `PORT` | No | `fly.toml` [env] | HTTP listen port (8080 on Fly) |
| `ECTO_IPV6` | No | `fly.toml` [env] | Enable IPv6 for DB connections (required on Fly) |
| `PHX_SERVER` | No | `rel/overlays/bin/server` | Starts the HTTP server (set automatically) |

## Health Check

- **Endpoint:** `GET /healthz`
- **Success (200):** Database is connected — returns `ok`
- **Failure (503):** Database is unreachable — returns `unavailable`
- Fly checks this every 15 seconds with a 5-second timeout
- 30-second grace period after deploy to allow boot + migration

## Troubleshooting

### Deploy fails during Docker build

Check the build logs for errors. Common issues:
- **Docker image not found:** Verify the `ARG` lines in `Dockerfile` reference valid tags on [hexpm/elixir Docker Hub](https://hub.docker.com/r/hexpm/elixir/tags)
- **Asset compilation fails:** Run `mix assets.deploy` locally to reproduce

### Health check fails after deploy

```bash
fly logs  # Check for crash or startup errors
```

Common causes:
- `DATABASE_URL` not set — run `fly secrets list` to verify
- `ECTO_IPV6` not set — Fly uses IPv6 internally; DB connections will silently timeout without this
- Migration failed — check logs for Ecto migration errors

### App starts but pages don't load

- Verify `PHX_HOST` in `fly.toml` matches your actual Fly hostname
- Check that `PORT` matches `internal_port` in `fly.toml` (both should be 8080)
