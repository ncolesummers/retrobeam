# RetroBeam Design System

## Brand Identity

**Personality**: Collaborative, Encouraging, Forward-looking
**Aesthetic**: Bold & Vibrant — inspired by Linear and Vercel
**Tone**: Professional but warm — safe space for honest feedback, not corporate

## Color Palette

RetroBeam uses [oklch](https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/oklch) color values via daisyUI theme tokens. All colors are defined in `assets/css/app.css`.

### Semantic Roles

| Token | Role | Light | Dark |
|-------|------|-------|------|
| `primary` | Core actions — buttons, links, focus rings | Indigo `oklch(45% 0.200 265)` | Bright indigo `oklch(65% 0.190 265)` |
| `secondary` | Interactive accents — facilitator badges, highlights | Warm amber `oklch(58% 0.170 60)` | Light amber `oklch(75% 0.140 70)` |
| `accent` | Special highlights — votes, notifications | Violet `oklch(50% 0.200 300)` | Light violet `oklch(72% 0.170 300)` |
| `neutral` | Subdued UI — borders, disabled states | Dark slate `oklch(38% 0.015 265)` | Mid slate `oklch(32% 0.020 265)` |
| `base-100` | Page background | Near-white `oklch(98.5% 0.004 270)` | Dark blue-grey `oklch(22% 0.015 265)` |
| `base-200` | Card/section background | Light grey `oklch(95% 0.006 270)` | Darker `oklch(18% 0.012 265)` |
| `base-300` | Borders, dividers | Mid grey `oklch(90% 0.008 270)` | Darkest `oklch(15% 0.010 265)` |
| `base-content` | Primary text | Near-black `oklch(20% 0.015 265)` | Near-white `oklch(95% 0.008 265)` |

### Semantic Status Colors

| Token | Purpose | Light | Dark |
|-------|---------|-------|------|
| `info` | Informational alerts | Blue `oklch(50% 0.180 245)` | `oklch(62% 0.160 245)` |
| `success` | Success states | Green `oklch(48% 0.160 155)` | `oklch(68% 0.150 155)` |
| `warning` | Warning states | Amber `oklch(62% 0.170 75)` | `oklch(78% 0.155 75)` |
| `error` | Error states | Red `oklch(50% 0.230 25)` | `oklch(65% 0.210 25)` |

## Typography

- **Font stack**: System fonts (Tailwind default) — fast loading, native feel
- **Headings**: `font-bold tracking-tight` — confident, decisive
- **Body**: Default weight, `leading-7` for comfortable reading
- **Small text**: `text-sm leading-6 text-base-content/60` for secondary content

## Component Inventory

Built on daisyUI components with Tailwind utility classes:

| Component | daisyUI Class | Usage |
|-----------|--------------|-------|
| Button (primary) | `btn btn-primary` | Main CTAs |
| Button (soft) | `btn btn-primary btn-soft` | Secondary actions |
| Button (ghost) | `btn btn-ghost` | Tertiary/nav actions |
| Input | `input` | Text fields, with `input-error` state |
| Select | `select` | Dropdowns, with `select-error` state |
| Textarea | `textarea` | Multi-line input |
| Alert | `alert alert-info/error` | Flash messages, notifications |
| Table | `table table-zebra` | Data display |
| Navbar | `navbar` | App header |
| Badge | `badge` | Status indicators |
| Divider | `divider` | Section separation |

## Theme Switching

Three-way toggle: System / Light / Dark

- Implemented via `data-theme` attribute on `<html>`
- Persisted to `localStorage` under `phx:theme`
- System mode removes the attribute, letting `prefers-color-scheme` drive selection
- Toggle component in `RetrobeamWeb.Layouts.theme_toggle/1`
- CSS variant: `@custom-variant dark (&:where([data-theme=dark], [data-theme=dark] *))`

## Layout Tokens

| Token | Value | Purpose |
|-------|-------|---------|
| `--radius-box` | `0.75rem` | Card and container corners |
| `--radius-field` | `0.375rem` | Input and button corners |
| `--radius-selector` | `0.375rem` | Checkbox/radio corners |
| `--border` | `1.5px` | Default border width |

## Accessibility Standards

- **Target**: WCAG AAA (7:1 contrast for normal text, 4.5:1 for large text)
- **Keyboard**: All interactive elements focusable and operable
- **Screen readers**: Proper ARIA labels, roles, and live regions
- **Motion**: `motion-safe:` prefix for animations (spinner, transitions)
- **Color blindness**: Don't rely on color alone — use icons + text alongside color indicators

## Layout Patterns

- **App layout**: Navbar + centered content (`max-w-2xl`)
- **Auth pages**: Centered card layout (`max-w-sm`)
- **Landing page**: Full-width hero + feature grid (`max-w-2xl`)

### Future Patterns (planned)

- **Retro board**: Multi-column card layout with drag-and-drop
- **Presence bar**: Horizontal avatar strip with online indicators
- **Timer**: Countdown with visual progress ring
- **Vote indicators**: Dot clusters on cards
