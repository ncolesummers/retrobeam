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

## Design Context

### Users
Software development teams running sprint retrospectives. Two primary roles: **facilitators** (create and guide retros) and **team members** (contribute cards, vote, discuss). Users arrive in a work context but need the interface to feel like a safe, encouraging space for honest feedback — not another corporate tool. Key upcoming UI patterns: card boards with columns, presence indicators, timers, and voting.

### Brand Personality
**Collaborative, Encouraging, Forward-looking.** Professional but warm — the tone of a good facilitator who makes space for honest reflection while keeping energy positive. Never preachy, never cold, never frivolous.

### Aesthetic Direction
**Bold & Vibrant** with an **indigo/blue primary** palette. Inspired by **Linear** (clean task management, confident UI, strong information hierarchy) and **Vercel** (bold typography, decisive spacing, dark mode done right). The design should feel modern, confident, and purposeful — like a tool built by people who care about craft.

**Anti-references:**
- No childish/toy-like aesthetics (no cartoonish illustrations, excessive emojis, kindergarten colors)
- No generic SaaS template feel (no cookie-cutter Bootstrap, no stock photo hero sections)
- No over-designed/flashy elements (no gratuitous animations, glassmorphism trends, style over substance)

### Design Principles
1. **Clarity over decoration** — Every element earns its place. Strong hierarchy, purposeful color, no visual noise.
2. **Confidence through craft** — Bold typography, decisive spacing, polished details. The UI should feel intentional, not tentative.
3. **Warmth without whimsy** — Friendly enough for honest conversation, professional enough for work. Rounded corners and warm accents, but no cute gimmicks.
4. **Accessible by default** — WCAG AAA target (7:1 contrast ratios). Design for keyboard navigation, screen readers, reduced motion, and color blindness from the start.
5. **Dark mode as a first-class citizen** — Both themes should feel designed, not derived. Dark mode isn't just inverted colors.

### Design Tokens (daisyUI)
- **Primary**: Indigo/blue — the core action color for buttons, links, focus states
- **Secondary**: Warm amber/gold — for interactive accents, highlights, facilitator badges
- **Accent**: Violet/purple — for special highlights, votes, notifications
- **Base**: Warm neutrals with slight warmth — approachable without being beige
- **Semantic**: Info (blue), Success (green), Warning (amber), Error (red) — harmonized with palette
- **Radius**: `--radius-box: 0.75rem` for friendlier card feel; `--radius-field: 0.375rem` for inputs
- **Typography**: System font stack, strong size hierarchy, generous line-height for readability
