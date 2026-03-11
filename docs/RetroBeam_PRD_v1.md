# RetroBeam: Product Requirements Document

**Real-Time Multiplayer Retrospectives on Phoenix/Elixir**

Version 1.0 | March 2026 | Demo Application
Author: Nate Summers | University of Idaho

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Technology Stack](#2-technology-stack)
3. [Feature Breakdown by Module](#3-feature-breakdown-by-module)
4. [Data Model](#4-data-model)
5. [Real-Time Architecture](#5-real-time-architecture)
6. [Test Plan (80% Coverage Target)](#6-test-plan-80-coverage-target)
7. [Backlog: Epics and User Stories](#7-backlog-epics-and-user-stories)
8. [Module Dependency Graph](#8-module-dependency-graph)
9. [Deployment & Operations](#9-deployment--operations)
10. [Future Considerations](#10-future-considerations)

---

## 1. Executive Summary

RetroBeam is a focused demo application that showcases real-time multiplayer collaboration using Phoenix/Elixir and the BEAM VM. The application implements a single agile ceremony (the Sprint Retrospective) with full multiplayer presence, real-time voting, AI-suggested card grouping, per-topic discussion timers, and AI-powered post-retro action item reports via the Anthropic API.

This demo validates the architectural thesis from our research: Phoenix Channels, PubSub, and Presence provide multiplayer primitives out of the box that other stacks require multiple external services to replicate. By constraining scope to retrospectives only, we can deliver a polished, production-quality experience that demonstrates these capabilities without the complexity of a full work management platform.

### 1.1 Goals

- Demonstrate real-time multiplayer collaboration with Phoenix Channels and Presence
- Showcase AI-native integration patterns using GenServer-based agents and Anthropic Claude
- Validate the Pure LiveView approach for interactive board-style UIs
- Deploy to Fly.io as a publicly accessible demo with basic authentication
- Produce a codebase structured for AI coding agent development workflows

### 1.2 Non-Goals

- Full work management features (sprints, backlogs, epics, roadmaps)
- Offline support or local-first architecture
- ElectricSQL integration (deferred to Phase 2 per research roadmap)
- Rich text editing with CRDTs (cards are plain text for the demo)
- Enterprise features (SSO, SCIM, audit logs, RBAC beyond facilitator/participant)

---

## 2. Technology Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| **Runtime** | Elixir 1.17+ / OTP 27 | BEAM VM process model maps directly to agent and connection model |
| **Web Framework** | Phoenix 1.7+ / LiveView 1.0+ | Built-in Channels, PubSub, Presence; LiveView diffs for real-time UI |
| **Database** | PostgreSQL 16+ | Ecto integration, future ElectricSQL compatibility, Oban job queue |
| **Background Jobs** | Oban 2.18+ | Postgres-only, ACID-compliant job processing for AI report generation |
| **AI Integration** | Anthropic API (Claude) | Post-retro summary generation, card grouping suggestions |
| **HTTP Client** | Req 0.5+ | Elixir-native HTTP client for Anthropic API calls |
| **Authentication** | phx_gen_auth (magic links + optional password) | Phoenix 1.8 generator with magic-link registration and bcrypt password hashing |
| **Deployment** | Fly.io + Docker | Global edge deployment, built-in Postgres, easy clustering |
| **CSS / UI** | Tailwind CSS 4.0 + DaisyUI 4.x | Utility-first styling with DaisyUI component library; both ship with Phoenix generators by default |
| **Testing** | ExUnit + Wallaby | Unit/integration with ExUnit, browser testing with Wallaby |
| **LiveView Testing** | Phoenix.LiveViewTest | First-party testing for LiveView interactions and PubSub events |

### 2.1 Key Architecture Decisions

**Pure LiveView (no SPA):** For a board-style retro UI, LiveView provides real-time updates for free via server-pushed diffs. Drag-and-drop for card grouping uses LiveView hooks (`phx-hook`) with the SortableJS library. This eliminates the need for a separate frontend build pipeline, API layer, or WebSocket client code.

**Server-Authoritative State:** All retro state (cards, groups, votes, timer) lives on the server in a GenServer process per active retro session. Clients receive diffs via LiveView. This matches the Linear/Figma pattern validated in our research: server-authoritative with instant UI updates.

**GenServer Per Retro Session:** Each active retrospective runs as a supervised GenServer process holding the session state (phase, cards, groups, votes, timer). This provides fault isolation (one retro crashing does not affect others), natural lifecycle management via OTP supervisors, and sub-millisecond in-process state reads.

**AI Agent as GenServer:** The AI agent for card grouping and report generation runs as a separate supervised GenServer. It subscribes to retro events via PubSub, processes card text through the Anthropic API, and broadcasts suggestions back through the same Channel infrastructure as human interactions.

**DaisyUI for Component Primitives:** DaisyUI ships as a Tailwind plugin in the default Phoenix 1.7+ generator. Rather than hand-rolling utility classes for every UI element, stories should leverage DaisyUI's semantic component classes where they map cleanly to the UI. Key mappings for this project include: `card` for retro cards, `badge` for vote counts and facilitator indicators, `btn` variants for actions, `steps` for the phase indicator bar, `modal` for confirmation dialogs, `drawer` for the presence sidebar, `countdown` for the discussion timer, `tabs` for column navigation on smaller screens, `alert` for timer expiration and AI status notifications, and `skeleton` for loading states during AI generation. Custom Tailwind utilities should only be used where DaisyUI does not provide a suitable primitive. DaisyUI themes can be configured in `tailwind.config.js` for consistent branding.

---

## 3. Feature Breakdown by Module

The application is organized into six modules, each representing a cohesive area of functionality. Modules are designed to be developed and tested independently by an AI coding agent.

### 3.1 Module: Authentication & User Management

Handles user registration, login, and session management. Provides the identity layer that Presence and card authorship depend on.

- User registration with email and magic-link authentication
- Session-based authentication via phx_gen_auth (optional password via settings)
- User profile with display name and avatar color (auto-assigned)
- Protected routes requiring authentication

### 3.2 Module: Retro Session Lifecycle

Manages the creation, configuration, and phase progression of retrospective sessions. A retro moves through defined phases: Setup, Card Collection, Grouping, Voting, Discussion, and Summary.

- Create a new retro with a selected template (Start/Stop/Continue, Mad/Sad/Glad, 4Ls, Sailboat, custom)
- Generate a shareable join code or link
- Facilitator controls phase transitions
- GenServer process per active retro holding all session state
- Retro state persisted to Postgres on phase transitions and at configurable intervals
- Automatic cleanup of stale retro sessions via Oban scheduled job

#### 3.2.1 Retro Phases

| Phase | Description | Facilitator Actions |
|-------|-------------|-------------------|
| **Setup** | Configure template, invite participants, set options (anonymous cards, vote count) | Select template, set vote limit, open/close joining |
| **Collect** | All participants submit cards to columns. Cards are hidden or visible per facilitator setting | Toggle card visibility, advance to Grouping |
| **Group** | AI suggests card groupings. Facilitator reviews, adjusts, and confirms groups | Accept/reject AI suggestions, manually drag cards between groups, label groups |
| **Vote** | Participants allocate a fixed number of votes across cards/groups | Set vote limit, advance to Discussion when voting closes |
| **Discuss** | Facilitator walks through cards/groups in vote-rank order with per-topic timer | Start/stop timer per topic, record notes, advance topics |
| **Summary** | AI generates action item report from discussion notes and card content | Trigger report generation, review and export report |

### 3.3 Module: Card Management

Handles creation, editing, and real-time synchronization of retrospective cards across all connected participants.

- Create cards assigned to a specific column (defined by template)
- Edit and delete own cards during the Collect phase
- Optional anonymous mode where card authors are hidden
- Real-time broadcast of card creation/edit/delete to all participants via PubSub
- Card grouping: drag a card onto another to form a group, or into an existing group
- Group labeling by facilitator
- All grouping operations broadcast in real-time; every participant sees the same board state

### 3.4 Module: Voting System

Implements real-time dot-voting on cards and groups. Vote tallies update live for all participants as votes are cast.

- Each participant receives a configurable number of votes (default: 5)
- Votes can be placed on individual cards or groups
- Multiple votes on the same item allowed (configurable)
- Real-time vote count updates broadcast to all participants via PubSub
- Remaining vote count displayed per participant
- Facilitator can see vote distribution; participants see only totals (configurable)
- Vote results determine discussion order (highest votes first)

### 3.5 Module: Discussion & Timer

Manages the facilitated discussion phase with per-topic timing, note-taking, and topic progression.

- Topics presented in descending vote order
- Per-topic countdown timer visible to all participants in real-time
- Configurable default timebox per topic (e.g., 5 minutes)
- Timer start/stop/reset controlled by facilitator
- Visual and optional audio alert when timebox expires
- Discussion notes field per topic (facilitator-editable, visible to all)
- Action item capture during discussion (assignee, description, due date)
- Elapsed time per topic recorded for the summary report

### 3.6 Module: AI Report Generation

Integrates with the Anthropic API to provide two AI-powered capabilities: card grouping suggestions during the Group phase, and a structured post-retro summary report.

#### 3.6.1 Card Grouping Suggestions

- During the Group phase, the AI agent analyzes all card text and suggests logical groupings
- Suggestions appear as a facilitator-only overlay with Accept/Reject per suggestion
- AI agent runs as a supervised GenServer, subscribing to retro events via PubSub
- Grouping request sent to Anthropic API as a structured tool-use call
- Facilitator can re-trigger suggestions after manual adjustments

#### 3.6.2 Post-Retro Summary Report

- Triggered by facilitator at the end of the Summary phase
- Inputs: all cards, groups, vote counts, discussion notes, action items, timing data
- AI generates: executive summary, key themes, action items with owners and dates, metrics (participation, time spent)
- Report rendered as a LiveView page and exportable as Markdown
- Generation runs as an Oban job to handle API latency without blocking the LiveView process
- Progress indicator shown to all participants during generation

---

## 4. Data Model

The following Ecto schemas define the persistence layer. Runtime state for active retros is held in GenServer processes and synced to Postgres periodically.

| Schema | Key Fields | Relationships |
|--------|-----------|---------------|
| **User** | id, email, hashed_password, display_name, avatar_color | has_many :retro_participations, has_many :cards |
| **RetroSession** | id, title, template, phase, join_code, vote_limit, anonymous, facilitator_id, started_at, ended_at | belongs_to :facilitator (User), has_many :participations, has_many :columns |
| **RetroColumn** | id, name, position, retro_session_id | belongs_to :retro_session, has_many :cards |
| **Card** | id, body, author_id, retro_column_id, card_group_id, position | belongs_to :author (User), belongs_to :column, belongs_to :card_group (optional) |
| **CardGroup** | id, label, retro_session_id, position | belongs_to :retro_session, has_many :cards |
| **Vote** | id, user_id, card_id, card_group_id | belongs_to :user, belongs_to :card or :card_group (polymorphic) |
| **RetroParticipation** | id, user_id, retro_session_id, role (facilitator/participant), joined_at | belongs_to :user, belongs_to :retro_session |
| **DiscussionTopic** | id, retro_session_id, card_id, card_group_id, position, notes, elapsed_seconds | belongs_to :retro_session, belongs_to :card or :card_group |
| **ActionItem** | id, description, assignee_id, discussion_topic_id, due_date, status | belongs_to :assignee (User), belongs_to :discussion_topic |
| **RetroReport** | id, retro_session_id, content_markdown, generated_at, model_used, prompt_tokens, completion_tokens | belongs_to :retro_session |

---

## 5. Real-Time Architecture

### 5.1 Channel Topics

All real-time communication flows through Phoenix Channels on a single WebSocket connection per participant. The LiveView process subscribes to PubSub topics and pushes diffs to the client.

| Topic Pattern | Purpose | Events |
|--------------|---------|--------|
| `retro:{retro_id}` | Main retro channel | phase_changed, card_created, card_updated, card_deleted, group_created, group_updated, card_moved |
| `retro:{retro_id}:votes` | Vote updates | vote_cast, vote_removed, vote_totals_updated |
| `retro:{retro_id}:timer` | Discussion timer | timer_started, timer_stopped, timer_tick, timer_expired |
| `retro:{retro_id}:presence` | Presence tracking | presence_state, presence_diff (join, leave, meta updates) |
| `retro:{retro_id}:ai` | AI agent events | grouping_suggested, report_generating, report_complete |

### 5.2 Presence Tracking

Phoenix.Presence tracks all participants in a retro session. Presence metadata includes display name, avatar color, current phase view, and idle status. Presence diffs are broadcast automatically when participants join, leave, or update metadata. The participant list sidebar updates in real-time for all connected users.

### 5.3 GenServer Session Process

Each active retro runs as a supervised GenServer under a DynamicSupervisor. The process holds the canonical session state and serializes all mutations. The flow for any state change is:

1. LiveView receives user event
2. Sends message to session GenServer
3. GenServer validates and applies mutation
4. GenServer broadcasts update via PubSub
5. All subscribed LiveView processes receive the broadcast and push diffs to their clients

---

## 6. Test Plan (80% Coverage Target)

The test strategy prioritizes unit tests for business logic and GenServer state machines, integration tests for LiveView interactions and PubSub event flows, and end-to-end browser tests for critical multiplayer scenarios. The 80% coverage target is measured by module.

### 6.1 Unit Tests

| Module | Test Focus | Key Scenarios |
|--------|-----------|---------------|
| RetroSession GenServer | State machine transitions, phase validation | Valid/invalid phase transitions, concurrent mutations, state recovery after crash |
| Card Management | CRUD operations, validation, grouping logic | Card creation in correct column, group merge/split, position reordering |
| Voting Logic | Vote allocation, limits, tallying | Vote limit enforcement, duplicate vote rules, tally computation, edge cases (0 votes, max votes) |
| Timer | Countdown logic, expiration | Timer start/stop/reset, tick accuracy, expiration callback, concurrent timer operations |
| AI Agent | Prompt construction, response parsing | Grouping suggestion parsing, report generation prompt assembly, API error handling, token counting |
| Auth | Registration, login, session | Valid/invalid registration, password hashing, session creation/expiry |
| Templates | Template definitions, column generation | Each template produces correct columns, custom template validation |

### 6.2 Integration Tests

| Test Area | Approach | Key Scenarios |
|-----------|----------|---------------|
| LiveView Card Board | Phoenix.LiveViewTest | Card appears after creation, card removed after deletion, group updates reflected, phase transitions update UI |
| Real-Time Voting | Multi-process LiveViewTest | Vote cast by User A appears for User B, vote count updates atomically, remaining votes decremented |
| Presence | LiveViewTest with multiple connections | New participant appears in sidebar, disconnected participant removed, metadata updates propagate |
| Phase Transitions | LiveViewTest + GenServer assertions | Facilitator advances phase, non-facilitator cannot advance, state persisted on transition |
| Timer Broadcast | PubSub subscription in test | Timer tick events received by all subscribers, expiration event fires correctly |
| AI Integration | Mox-based API mocking | Grouping suggestions rendered correctly, report generation shows progress, API errors handled gracefully |
| Oban Jobs | Oban.Testing | Report job enqueued on trigger, job processes successfully, failed job retries correctly |

### 6.3 End-to-End Tests

| Scenario | Tool | Description |
|----------|------|-------------|
| Two-Player Retro Flow | Wallaby | Two browser sessions: create retro, join, add cards, group, vote, discuss, generate report |
| Facilitator Controls | Wallaby | Verify only facilitator can advance phases, start timer, trigger AI |
| Vote Real-Time Sync | Wallaby | One user votes, second user sees count update without refresh |
| Card Grouping Drag | Wallaby + JS | Drag card onto another, verify group forms for both users |
| Disconnect/Reconnect | Wallaby | Kill one connection, verify presence updates, reconnect and verify state recovery |

### 6.4 Coverage Targets by Module

| Module | Unit | Integration | E2E | Overall Target |
|--------|------|-------------|-----|---------------|
| Auth & Users | 90% | 80% | 1 flow | 85% |
| Retro Session Lifecycle | 90% | 85% | 2 flows | 88% |
| Card Management | 85% | 85% | 2 flows | 85% |
| Voting System | 90% | 90% | 1 flow | 90% |
| Discussion & Timer | 85% | 80% | 1 flow | 82% |
| AI Report Generation | 80% | 75% | 1 flow | 78% |

---

## 7. Backlog: Epics and User Stories

Stories are written to be completed by an AI coding agent. Each story is self-contained with clear acceptance criteria, explicit file paths where relevant, and testable outcomes. Stories within an epic should be completed in order, as later stories may depend on earlier ones.

---

### Epic 1: Project Scaffolding & Auth

Foundation setup including Phoenix project generation, database configuration, authentication, and Fly.io deployment pipeline.

#### E1-S1: Phoenix Project Bootstrap

**As a developer**, I need a new Phoenix project with LiveView, Tailwind, and Ecto configured so that all subsequent work has a consistent foundation.

**Acceptance Criteria:**

1. Running `mix phx.new retrobeam --live` generates the project skeleton
2. PostgreSQL database creates and migrates successfully with `mix ecto.setup`
3. `mix phx.server` starts and serves the default Phoenix landing page at localhost:4000
4. Tailwind CSS compiles and hot-reloads on file changes
5. ExUnit test suite runs with `mix test` and all generated tests pass
6. `mix.exs` includes dependencies: phoenix, phoenix_live_view, ecto_sql, postgrex, oban, req, bcrypt_elixir
7. `.formatter.exs` is configured for the project

---

#### E1-S2: User Authentication

**As a user**, I need to register and log in so that my identity is tracked across retro sessions.

**Acceptance Criteria:**

1. `mix phx.gen.auth Accounts User users` generates auth scaffolding (Phoenix 1.8 magic-link default)
2. User schema includes additional fields: `display_name` (string, required) and `avatar_color` (string, auto-assigned from a preset palette)
3. Registration form collects email and display_name; user receives a magic-link email to complete login
4. After clicking the magic link, user is redirected to `/retros` (the retro dashboard, can be a placeholder page)
5. All routes under `/retros/*` require authentication via the generated plug pipeline
6. Unauthenticated access to protected routes redirects to `/users/log_in`
7. Users can optionally set a password via the settings page for password-based login
8. Tests: registration with valid/invalid data, login/logout flow, protected route redirect

---

#### E1-S3: Fly.io Deployment Configuration

**As a developer**, I need the project deployable to Fly.io so that the demo is publicly accessible.

**Acceptance Criteria:**

1. `fly.toml` is configured for the retrobeam application with appropriate VM size
2. Dockerfile builds the Elixir release with `mix release`
3. `DATABASE_URL` and `SECRET_KEY_BASE` are configured as Fly secrets
4. `fly deploy` succeeds and the application serves the login page at the assigned URL
5. Fly Postgres addon is provisioned and migrations run on deploy via a release migration module
6. Health check endpoint at `/healthz` returns 200

---

### Epic 2: Retro Session Lifecycle

Core session management including creation, joining, phase management, and the GenServer process model.

#### E2-S1: Retro Template Definitions

**As a facilitator**, I need predefined retro templates so that I can quickly start a retro without manual column setup.

**Acceptance Criteria:**

1. A `RetroTemplate` module defines templates as data: Start/Stop/Continue (3 columns), Mad/Sad/Glad (3 columns), 4Ls (Liked/Learned/Lacked/Longed For, 4 columns), Sailboat (Wind/Anchor/Rocks/Island, 4 columns), Custom (user-defined column names and count)
2. Each template returns a list of column definitions with name, position, and optional description
3. Templates are tested: each named template returns the correct column count and names
4. Custom template accepts a list of 2-6 column names

---

#### E2-S2: Create Retro Session

**As a facilitator**, I need to create a new retrospective session by selecting a template so that my team can participate.

**Acceptance Criteria:**

1. LiveView at `/retros/new` displays template selection with visual preview of each template layout
2. Creating a retro generates a unique 6-character alphanumeric join code
3. `RetroSession` record is persisted with facilitator_id, template, join_code, `phase: :setup`, and vote_limit defaulting to 5
4. `RetroColumn` records are created based on the selected template
5. `RetroParticipation` record is created for the facilitator with `role: :facilitator`
6. After creation, facilitator is redirected to `/retros/:id`
7. Tests: session creation with each template type, join code uniqueness, database records created correctly

---

#### E2-S3: Join Retro Session

**As a participant**, I need to join an existing retro via a join code or link so that I can participate in the retrospective.

**Acceptance Criteria:**

1. LiveView at `/retros/join` displays a form accepting a 6-character join code
2. Direct link `/retros/join/:code` auto-fills the code
3. Submitting a valid code creates a `RetroParticipation` record with `role: :participant` and redirects to `/retros/:id`
4. Submitting an invalid code displays an error message without navigation
5. Joining a retro that has ended (phase: :summary and report generated) displays a read-only view
6. Duplicate join attempts (same user, same retro) redirect to the retro without creating a duplicate record
7. Tests: valid join, invalid code, duplicate join, ended retro join

---

#### E2-S4: Retro Session GenServer

**As the system**, I need a GenServer process per active retro to hold session state in memory so that real-time interactions have sub-millisecond state access.

**Acceptance Criteria:**

1. `RetroServer` GenServer starts under a DynamicSupervisor when the first participant connects to a retro LiveView
2. GenServer state includes: retro_id, phase, cards (map), groups (map), votes (map), timer state, connected participants
3. GenServer loads initial state from Postgres on startup
4. GenServer provides synchronous call API: `get_state/1`, `add_card/2`, `update_card/2`, `delete_card/2`, `create_group/2`, `move_card_to_group/2`, `cast_vote/2`, `remove_vote/2`, `advance_phase/2`
5. State mutations are validated (e.g., cannot add cards outside Collect phase, cannot vote outside Vote phase)
6. GenServer persists state to Postgres on every phase transition and every 30 seconds via `Process.send_after`
7. GenServer terminates gracefully after 30 minutes of no connected participants, persisting final state
8. Tests: GenServer start/stop, state loading, each mutation with valid/invalid inputs, persistence timing, timeout cleanup

---

#### E2-S5: Phase Transitions with Facilitator Controls

**As a facilitator**, I need to control the retro phase progression so that the retrospective follows a structured flow.

**Acceptance Criteria:**

1. The retro LiveView displays a phase indicator bar showing all phases with the current phase highlighted
2. Only the facilitator sees a "Next Phase" button
3. Clicking "Next Phase" sends an `advance_phase` message to the RetroServer GenServer
4. GenServer validates the transition: Setup -> Collect -> Group -> Vote -> Discuss -> Summary (no skipping, no going back)
5. Phase change is broadcast via PubSub to topic `retro:{id}`; all connected LiveViews update their UI
6. Non-facilitator participants see the phase change reflected immediately without manual refresh
7. GenServer persists the new phase to Postgres immediately on transition
8. Phase indicator bar uses DaisyUI `steps` component with active/completed/upcoming states styled via step-primary/step-neutral classes
9. Tests: valid transitions through all phases, invalid transition attempts, PubSub broadcast verification, facilitator-only enforcement

---

### Epic 3: Card Board & Real-Time Sync

Card creation, display, and real-time synchronization across all connected participants.

#### E3-S1: Card Creation and Display

**As a participant**, I need to create cards in the appropriate columns during the Collect phase so that I can share my retrospective feedback.

**Acceptance Criteria:**

1. During the Collect phase, each column displays an "Add Card" button and text input area
2. Submitting a card sends an `add_card` message to the RetroServer GenServer with column_id, body, and author_id
3. The card appears in the correct column immediately for the author (optimistic update via LiveView)
4. GenServer broadcasts `card_created` event via PubSub; the card appears for all other participants
5. Cards render using the DaisyUI `card` component with `card-compact` variant; author avatar uses a `badge` with the user's assigned color
6. Cards display the author name and avatar color (unless anonymous mode is enabled)
6. Author can edit their own card body by clicking on it (inline edit, saves on blur or Enter)
7. Author can delete their own card via a delete button (with confirmation)
8. Edit and delete events broadcast in real-time to all participants
9. Cards are only editable during the Collect phase; in later phases, cards are read-only
10. Tests: card creation, real-time broadcast, edit, delete, phase restriction, anonymous mode

---

#### E3-S2: Card Grouping with Drag-and-Drop

**As a facilitator**, I need to drag cards onto each other to form groups during the Group phase so that related feedback is organized for discussion.

**Acceptance Criteria:**

1. During the Group phase, a LiveView hook initializes SortableJS on the card board
2. Dragging a card onto another card creates a new `CardGroup` containing both cards
3. Dragging a card onto an existing group adds it to that group
4. Dragging a card out of a group removes it; empty groups are auto-deleted
5. Each drag operation sends a `move_card_to_group` message to the RetroServer GenServer
6. GenServer broadcasts `group_created`, `card_moved`, or `group_deleted` events via PubSub
7. All participants see group changes in real-time without refresh
8. Facilitator can label groups by clicking on the group header and typing a label
9. Group label updates broadcast in real-time
10. Only the facilitator can drag cards and modify groups; participants see a read-only view during Group phase
11. Tests: group creation, card move to group, card remove from group, label update, facilitator-only enforcement, real-time sync

---

#### E3-S3: Presence Sidebar

**As a participant**, I need to see who is currently in the retro session so that I know my team is present.

**Acceptance Criteria:**

1. A collapsible sidebar displays all connected participants with their display name and avatar color
2. Phoenix.Presence tracks joins and leaves on the `retro:{id}:presence` topic
3. When a new participant joins, all existing participants see them appear in the sidebar in real-time
4. When a participant disconnects, they are removed from the sidebar within 2 seconds (Presence heartbeat)
5. The facilitator is marked with a distinct badge or icon
6. Participant count is displayed in the header bar
7. Sidebar uses DaisyUI `drawer` component; participant list items use `avatar` placeholder with the user's color and a `badge badge-primary` for the facilitator role
8. Tests: presence join, presence leave, facilitator badge, count accuracy, multiple simultaneous joins

---

### Epic 4: Voting System

#### E4-S1: Vote Casting and Real-Time Tallies

**As a participant**, I need to vote on cards or groups during the Vote phase so that the team can prioritize discussion topics.

**Acceptance Criteria:**

1. During the Vote phase, each card and group displays a DaisyUI `btn btn-sm` Vote button with the current vote count shown in an adjacent `badge badge-secondary`
2. Clicking Vote sends a `cast_vote` message to the RetroServer GenServer with user_id and target (card_id or group_id)
3. GenServer validates: user has remaining votes, target exists, and phase is Vote
4. GenServer increments vote count and broadcasts `vote_totals_updated` via PubSub
5. All participants see the updated vote count in real-time without refresh
6. A "remaining votes" indicator shows each participant how many votes they have left
7. Clicking Vote again on the same item adds another vote (if the retro allows multi-voting, configurable by facilitator)
8. A "Remove Vote" button appears on items the user has voted on
9. Tests: vote casting, limit enforcement, real-time tally broadcast, vote removal, multi-vote toggle

---

#### E4-S2: Vote Results and Discussion Ordering

**As a facilitator**, I need to see vote results and have discussion topics auto-ordered by votes so that the team discusses the most important topics first.

**Acceptance Criteria:**

1. When the facilitator advances to the Discuss phase, the GenServer computes discussion order by descending vote count
2. `DiscussionTopic` records are created for each card/group with votes > 0, ordered by vote count
3. Cards/groups with 0 votes are excluded from discussion (but remain visible on the board)
4. Ties are broken by card/group creation time (earliest first)
5. The discussion view displays topics in rank order with vote counts visible
6. Tests: ordering by vote count, tie breaking, zero-vote exclusion, DiscussionTopic record creation

---

### Epic 5: Discussion & Timer

#### E5-S1: Per-Topic Discussion Timer

**As a facilitator**, I need a timer for each discussion topic so that the team manages their time effectively and I can record discussion duration for the report.

**Acceptance Criteria:**

1. The discussion view shows the current topic prominently with a large countdown timer using the DaisyUI `countdown` component for the digit display
2. Facilitator can set the default timebox (1-15 minutes, default 5) before starting discussion
3. Facilitator clicks Start to begin the countdown for the current topic
4. Timer ticks broadcast every second via PubSub to topic `retro:{id}:timer`
5. All participants see the same timer value in real-time (server-authoritative time)
6. When the timer reaches 0, a visual pulse alert appears and an optional browser notification fires
7. Facilitator can Stop (pause), Reset (to timebox value), or Skip (mark topic done, move to next)
8. Elapsed time for each topic is recorded on the `DiscussionTopic` record when the facilitator advances
9. Tests: timer start/stop/reset/skip, tick broadcast accuracy, elapsed time recording, timebox configuration

---

#### E5-S2: Discussion Notes and Action Items

**As a facilitator**, I need to record discussion notes and action items for each topic so that the AI report has rich context.

**Acceptance Criteria:**

1. Each discussion topic displays a notes textarea (facilitator-editable)
2. Notes auto-save to the GenServer state on blur and on a 3-second debounce during typing
3. An "Add Action Item" button below the notes opens an inline form: description, assignee (dropdown of participants), optional due date
4. Action items are saved to the `ActionItem` schema via the GenServer
5. Action items appear in a list below the topic, visible to all participants
6. Facilitator can edit or delete action items during the Discussion phase
7. Notes and action items are broadcast to all participants in real-time
8. Tests: note auto-save, action item CRUD, assignee validation, real-time broadcast of notes and action items

---

### Epic 6: AI Integration

#### E6-S1: AI Card Grouping Suggestions

**As a facilitator**, I need AI-suggested card groupings during the Group phase so that similar cards are identified without manual review of every card.

**Acceptance Criteria:**

1. When the Group phase begins, the retro GenServer sends a message to the AI agent GenServer with all card texts and their column assignments
2. The AI agent constructs a prompt asking Claude to suggest logical groupings with group labels, using Anthropic `tool_use` for structured output
3. The AI agent sends the request to the Anthropic API via Req and parses the structured response
4. Suggestions are broadcast to the retro channel as a `grouping_suggested` event
5. The facilitator sees an "AI Suggestions" panel with proposed groups; each suggestion shows the group label and member card previews
6. Facilitator can Accept (applies the grouping), Reject (dismisses the suggestion), or Accept All
7. Accepting a suggestion sends the appropriate group creation and card move messages to the retro GenServer
8. A "Re-analyze" button lets the facilitator trigger a new AI analysis after manual adjustments
9. Non-facilitator participants do not see the suggestion panel; they only see groups after facilitator accepts
10. Tests: prompt construction, API response parsing, suggestion rendering, accept/reject flow, re-analysis, error handling for API failures

---

#### E6-S2: Post-Retro Summary Report

**As a facilitator**, I need an AI-generated summary report after the retrospective so that the team has a structured record of outcomes and action items.

**Acceptance Criteria:**

1. In the Summary phase, a "Generate Report" button is visible to the facilitator
2. Clicking it enqueues an Oban job (`RetroReportWorker`) with the retro_id
3. The worker collects all retro data: template, cards, groups, vote counts, discussion notes, action items, timing data, participant names
4. The worker constructs a prompt for Claude requesting a structured report with: executive summary, key themes identified, action items table (description, assignee, due date, priority), participation metrics, discussion time breakdown
5. The worker sends the request to the Anthropic API and stores the Markdown response in the `RetroReport` schema along with token usage metadata
6. A `report_generating` event is broadcast via PubSub; all participants see a DaisyUI `skeleton` loading state with a `progress` bar indicator
7. A `report_complete` event is broadcast when done; all participants can view the report
8. The report renders as a formatted LiveView page at `/retros/:id/report`
9. A "Copy Markdown" button allows copying the raw Markdown to clipboard
10. Tests: Oban job enqueue/execute, prompt assembly with all data types, report storage, broadcast events, error handling for API timeout/failure, retry behavior

---

#### E6-S3: AI Agent GenServer and Anthropic Client

**As the system**, I need a supervised AI agent GenServer and Anthropic API client module so that AI capabilities are fault-tolerant and testable.

**Acceptance Criteria:**

1. An `AnthropicClient` module wraps Req for API calls with: configurable base URL and API key via application config, structured `tool_use` request formatting, response parsing with error handling, token usage tracking, configurable timeout (default 30s) and retry (3 attempts with exponential backoff)
2. An `AIAgent` GenServer starts under the application supervision tree (singleton)
3. The AIAgent exposes `suggest_groupings/2` (retro_id, cards) and `generate_report/2` (retro_id, retro_data) API
4. The AIAgent uses `Task.Supervisor` to spawn API calls asynchronously, preventing the GenServer from blocking
5. Results are delivered back via PubSub broadcast to the appropriate retro topic
6. The `AnthropicClient` is behind a behaviour so that tests can use Mox to mock API responses
7. Application config supports `ANTHROPIC_API_KEY` and `ANTHROPIC_MODEL` environment variables
8. Tests: client request formatting, response parsing, error scenarios (timeout, rate limit, invalid response), GenServer lifecycle, Mox-based integration tests

---

## 8. Module Dependency Graph

Modules should be developed in the following order based on their dependencies. This ordering also maps to the Epic sequence in the backlog.

| Order | Module | Depends On | Enables |
|-------|--------|-----------|---------|
| 1 | Auth & Users | None (Phoenix scaffolding) | All other modules |
| 2 | Retro Session Lifecycle | Auth & Users | Card Management, Voting, Discussion |
| 3 | Card Management | Retro Session Lifecycle | Voting, AI Grouping |
| 4 | Voting System | Card Management | Discussion ordering |
| 5 | Discussion & Timer | Voting System | AI Report |
| 6 | AI Integration | Card Management, Discussion & Timer | Summary Report |

### 8.1 AI Agent Development Notes

Each story is written to be completable by an AI coding agent (such as Claude Code or Cursor Agent) with the following conventions:

- Stories reference specific modules, schemas, and function signatures to reduce ambiguity
- Acceptance criteria are testable assertions, not subjective quality judgments
- Stories within an epic are ordered by dependency; an agent can work through them sequentially
- Test requirements are explicit in every story to ensure the agent writes tests alongside implementation
- The Mox-based testing pattern for the Anthropic client ensures AI integration stories are testable without live API calls

---

## 9. Deployment & Operations

### 9.1 Fly.io Configuration

- Single Fly machine with 1GB RAM (sufficient for demo scale: ~50 concurrent users)
- Fly Postgres single-node for the demo (no HA needed)
- Fly secrets: `SECRET_KEY_BASE`, `DATABASE_URL`, `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`
- Auto-stop enabled with `min_machines_running: 1` for cost efficiency
- Health check at `/healthz` (returns 200 when Ecto repo is connected)

### 9.2 Environment Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | Yes | N/A | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Yes | N/A | Phoenix secret for signing cookies and tokens |
| `ANTHROPIC_API_KEY` | Yes | N/A | API key for Anthropic Claude |
| `ANTHROPIC_MODEL` | No | claude-sonnet-4-20250514 | Model to use for AI features |
| `PHX_HOST` | No | localhost | Hostname for URL generation |
| `PORT` | No | 4000 | HTTP listen port |
| `POOL_SIZE` | No | 10 | Ecto database pool size |

---

## 10. Future Considerations

These items are explicitly out of scope for the demo but inform architectural decisions to avoid painting ourselves into a corner.

- ElectricSQL read-path sync for instant UI responsiveness (Phase 2 per research roadmap)
- Live AI copilot streaming during discussion phase (real-time suggestions as teams talk)
- Rich text card bodies with Yjs CRDTs via y_ex
- OAuth/SSO authentication (replace phx_gen_auth with Ueberauth)
- Multi-node clustering for horizontal scaling (BEAM distribution + libcluster)
- Export to PDF or integration with Jira/Linear/GitHub Issues for action item tracking
- Mobile-responsive or native mobile experience
- Persistent retro analytics dashboard across multiple retros
