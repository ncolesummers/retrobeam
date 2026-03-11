# RetroBeam — AI Agent Guidelines

## Project Overview

RetroBeam is a real-time multiplayer retrospective app built with Phoenix LiveView.
See `docs/RetroBeam_PRD_v1.md` for the full product requirements document.

## Tech Stack

- **Elixir 1.19** / **OTP 28** / **Phoenix 1.8.5** / **LiveView 1.1**
- **PostgreSQL 18** (via Postgres.app, port 5432)
- **Oban** for background jobs (ai_reports queue)
- **Req** for HTTP client (Anthropic API calls)
- **bcrypt_elixir** for password hashing
- **Tailwind CSS 4** (via standalone CLI)
- **esbuild** for JS bundling

## Commands

```bash
mix setup              # Install deps, create DB, migrate, setup assets
mix test               # Run tests (creates + migrates test DB automatically)
mix test path/to/test  # Run a specific test file
mix phx.server         # Start dev server at localhost:4000
iex -S mix phx.server  # Start dev server with IEx shell
mix format             # Format all files
mix ecto.migrate       # Run pending migrations
mix ecto.rollback      # Rollback last migration
mix precommit          # Compile (warnings-as-errors), unlock unused deps, format, test
```

## Code Conventions

- Follow standard Phoenix 1.8 project structure
- Context modules in `lib/retrobeam/` (e.g., `Retrobeam.Boards`, `Retrobeam.Accounts`)
- Web modules in `lib/retrobeam_web/`
- Use `mix format` before committing — the formatter config includes `:oban` import_deps
- Migrations use `utc_datetime` timestamps (configured in generators)
- Oban workers go in `lib/retrobeam/workers/`
- Tests mirror `lib/` structure under `test/`

## Architecture Notes

- Real-time features use Phoenix PubSub + LiveView (no external message broker)
- Oban handles async AI report generation (ai_reports queue, concurrency: 2)
- Anthropic API calls go through Req
- Authentication uses `phx.gen.auth` with magic-link registration and bcrypt password hashing
- `@current_scope` (not `@current_user`) is available in assigns — wraps the user via `Accounts.Scope`
- LiveViews use `on_mount` hooks in `RetrobeamWeb.UserAuth` for auth (`:ensure_authenticated`, `:mount_current_scope`)
- Authenticated LiveViews go in `live_session :authenticated` in the router

## Testing

- Target: 80% code coverage
- Oban runs inline in test env (`testing: :inline`)
- Use `Ecto.Adapters.SQL.Sandbox` for DB isolation
- `DataCase` for context tests, `ConnCase` for controller/LiveView tests
