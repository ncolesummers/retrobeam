# AI-native multiplayer work management: Phoenix vs. ElectricSQL

**Phoenix/Elixir is the stronger architectural foundation for an AI-native multiplayer work management platform**, particularly given AI agents as the core differentiator. The BEAM VM's process model maps directly onto the agent model that Python and TypeScript frameworks are independently reinventing, while Phoenix Channels, PubSub, and Presence provide the real-time multiplayer primitives out of the box. ElectricSQL's 2024 rewrite stripped it to a read-path-only sync engine — meaning you must build your own write path, conflict resolution, and presence layer regardless — which eliminates much of its theoretical advantage while adding substantial engineering complexity.

That said, the TypeScript ecosystem's advantages in talent pool (**38.5% of developers** vs. Elixir's ~1-2%), AI tooling (Vercel AI SDK at **20M+ monthly downloads**, LangChain.js, full MCP reference SDK), and end-to-end type safety are significant for a small team shipping an MVP in 6-9 months. The strongest architecture is actually a **hybrid**: Phoenix as the real-time/AI backbone with ElectricSQL as an optional read-path sync layer for instant UI responsiveness — the same server-authoritative-with-local-reads pattern that Linear and Figma have proven at scale.

The critical insight from studying both Linear (10,000+ paying companies) and Figma (13M+ MAU, $749M revenue) is that neither uses pure local-first architecture. Both are server-authoritative with per-property last-write-wins, using local data for instant reads and optimistic writes. Pure local-first for work management — with its unsolved problems in permissions, workflows, server-side integrations, and additive-only schema migrations — remains architecturally immature for production use.

---

## Dimension-by-dimension comparison matrix

| Dimension | Phoenix/Elixir (A) | ElectricSQL + PGLite (B) | Edge |
|---|---|---|---|
| **Real-time latency** | Sub-10ms LiveView diffs; 1-3s broadcast to 2M clients | 6ms Electric sync (optimized); client reads <0.3ms | **Draw** — different strengths |
| **Connection scalability** | 2M WebSocket connections/server (proven) | 1M+ HTTP clients via CDN (proven) | **A** — battle-tested at Discord scale |
| **Consistency model** | Server-authoritative (strong) | Eventual (DIY conflict resolution) | **A** — simpler correctness guarantees |
| **AI agent integration** | Native GenServer + PubSub + Presence | Agent writes to server PG; no peer model | **A** — dramatically better fit |
| **LLM streaming** | ~70 lines; LiveView auto-pushes diffs | SSE + external pub/sub for fan-out | **A** — built-in multi-client fan-out |
| **Offline support** | None (fundamental limitation) | Exceptional (PGLite + IndexedDB) | **B** — clear winner |
| **UI responsiveness** | Server round-trip required | Local PGLite queries <0.3ms | **B** — zero-latency reads |
| **Developer talent pool** | ~1-2% of developers; hiring is hard | 38.5% use TypeScript regularly | **B** — 20-30x larger pool |
| **AI library ecosystem** | Anubis MCP, Bumblebee; small | Vercel AI SDK, LangChain.js; massive | **B** — far more mature |
| **Type safety** | Dialyzer (gradual, opt-in) | TypeScript (structural, enforced) | **B** — more comprehensive |
| **Fault tolerance** | Runtime-level (supervision trees, per-process GC) | Application-level (try/catch, retry) | **A** — unfair advantage |
| **Operational complexity** | Phoenix + Postgres (2 services) | Electric + Postgres + presence sidecar + write API (4-5) | **A** — dramatically simpler |
| **Maturity/risk** | 10+ years production (Discord, WhatsApp) | Electric v1.0 (March 2025), PGLite v0.3.x | **A** — proven at massive scale |
| **Background jobs** | Oban (Postgres-only, ACID) | BullMQ (requires Redis) or Trigger.dev | **A** — no additional infrastructure |
| **Schema evolution** | Standard Postgres migrations | Additive-only for synced tables | **A** — no restrictions |
| **Presence** | Phoenix.Presence (built-in, CRDT-based) | Must build or buy separately | **A** — zero-effort |
| **Ecosystem size** | ~15K hex.pm packages | 2M+ npm packages | **B** — 130x larger |

**Summary: Architecture A wins 10 dimensions, Architecture B wins 5, 1 draw.** Architecture A's advantages concentrate in the platform's core differentiators (AI, real-time, reliability), while Architecture B's advantages center on developer experience and offline capability.

---

## Real-time multiplayer under the hood

### Phoenix achieves sub-second broadcast to millions of connections

The landmark **2 million concurrent WebSocket connections** benchmark (October 2015, Chris McCord) used a single Rackspace server with **40 cores and 128GB RAM**. Messages broadcast to all 2M clients completed in **1-3 seconds**, and the system wasn't memory-maxed — the limit was the OS ulimit, not machine resources. On commodity hardware (4 cores, 15GB RAM), Phoenix sustained **330,000 connections** with 40% memory remaining. A community reproduction on DigitalOcean reached **2.3 million connections** on a 64GB/20-core droplet.

Each LiveView connection consumes approximately **~40KB baseline memory** (Chris McCord, InfoQ 2024), yielding ~25,000 concurrent LiveViews per GB of RAM. LiveView sends only diffs of changed dynamic content — static template parts are sent once and tracked via fingerprint trees. Production users consistently report **sub-10ms server response times**, and Chris McCord's "rainbow demo" animated divs at 60fps between Poland and US East Coast without visible jitter.

Discord provides the definitive production validation: **11 million+ concurrent users** served by 400-500 Elixir machines, maintained by just **5 engineers** managing 20+ services. They open-sourced Manifold (batch message passing), FastGlobal (~0 cost reads vs ETS's ~7μs), and use Rust NIFs via Rustler for performance-critical data structures.

### ElectricSQL trades consistency for CDN-level fan-out

Electric's architecture after its July 2024 rewrite is fundamentally different from what most developers expect. It is a **read-path-only Postgres sync engine** using HTTP-based Shape sync — not WebSockets. This enables CDN caching and request collapsing, allowing **1 million+ concurrent clients** with a single Electric service, where both memory usage and latency remain essentially flat. Live update latency for optimized WHERE clauses is **6ms end-to-end** (3ms Postgres + 3ms Electric) regardless of shape count, with write throughput of **~5,000 row changes/second**.

However, Shapes are currently **single-table only** — no include trees for related data. A work management platform (projects → tasks → comments → assignees) requires multiple shapes with client-side joins. Electric provides **no built-in conflict resolution, no write-path sync, and no presence**. The previous CRDT-based system was entirely abandoned. Developers must implement writes via their own API, using patterns ranging from simple online writes to complex shadow tables with triggers (as demonstrated in the Linearlite demo). This means adopting "Architecture B" actually requires building substantial server-side infrastructure regardless.

### Consistency matters more than latency for work management

For a ClickUp-style platform, the consistency model is critical. When User A marks a task "In Progress" and User B marks it "Done" simultaneously, the system must produce a predictable, correct result. Phoenix's server-authoritative model makes the server the single arbiter — **whoever's mutation arrives first wins**, and all clients see the same outcome. Electric's eventual consistency requires you to implement your own merge logic, and with the read-path-only architecture, that logic lives in your custom write API anyway.

Both Linear and Figma validate the server-authoritative approach at massive scale. Figma's CTO explicitly rejected full CRDTs as unnecessarily complex, using CRDT *ideas* (per-property LWW registers) within a server-authoritative architecture. Linear's CTO Tuomas Artman noted that conflicts are "actually not that common" — they only added CRDTs for rich text descriptions, using LWW for all structured fields (status, assignee, priority).

Phoenix.Presence provides distributed, CRDT-based presence tracking with no external dependencies — **no Redis, no database, no single point of failure**. It uses a heartbeat/gossip protocol to replicate across cluster nodes, with configurable broadcast periods (default 1500ms). In the Electric stack, presence requires an entirely separate service (PartyKit, Liveblocks, or a custom WebSocket server), adding both operational complexity and latency.

---

## How AI agents actually participate in each architecture

### Phoenix: agents are processes, and that's the whole point

In Phoenix, an AI agent is a **GenServer process** — a lightweight (~2KB) BEAM process with isolated state, its own heap, and independent garbage collection. The agent subscribes to PubSub topics, appears in Presence, sends mutations through Channels, and streams LLM responses — all using the same primitives as human users. The pattern is strikingly natural:

The agent subscribes to document events via `Phoenix.PubSub.subscribe(MyApp.PubSub, "document:#{doc_id}")` and reacts in `handle_info/2` with **sub-millisecond latency** within a node. No polling, no webhooks, no external message queues. For streaming LLM responses, a Task.async consumes the OpenAI stream and sends chunks to the LiveView process, which auto-pushes DOM diffs to all connected clients — Ben Reinhart documented this in **under 70 lines of code**. For multi-client fan-out, each token broadcasts via PubSub to all subscribed Channel clients with zero additional code.

The BEAM's **preemptive scheduling** (every ~4,000 reductions) means no single agent can starve others — unlike Node.js where a CPU-intensive LLM post-processing step blocks all connections. **Supervision trees** provide declarative recovery: when an agent crashes (and LLM interactions are inherently non-deterministic), the supervisor restarts it cleanly. No try/catch defensive programming needed. **Hot code swapping** enables deploying updated agent behavior (new prompts, tools, bug fixes) without dropping connections.

George Guimarães's widely-discussed February 2026 article crystallized the insight: **"The actor model that Erlang introduced in 1986 is the agent model AI is rediscovering in 2026."** LangGraph builds state machines, CrewAI chains task outputs, AutoGen v0.4 rebuilt as an "event-driven actor framework" — all independently converging on patterns native to OTP since 1998. Variant Systems estimates you "can get about 70% there with enough engineering" in other runtimes, but the remaining 30% (preemptive scheduling, per-process GC, hot code swapping, true fault isolation) requires runtime-level support.

For MCP hosting, Elixir has multiple active implementations: **Anubis MCP** (v0.17.1, full client+server, Phoenix router integration), EMCP (simpler, in production), and NexusMCP. Each MCP session maps to a supervised GenServer — the lifecycle semantics align perfectly.

### Electric: agents are external writers, not peers

In the ElectricSQL architecture, an AI agent participates by **writing directly to server Postgres**. Changes then sync outward to clients via Electric's read-path. This works but is architecturally different — the agent is not a peer in the sync mesh but a privileged server-side writer. There is no agent presence, no real-time event subscription from within the sync protocol, and no built-in mechanism for agents to react to user edits without polling the database or adding a separate WebSocket layer.

ElectricSQL has explored local-first AI (PGLite + pgvector for on-device RAG), and their December 2025 pivot toward "multi-agent" positioning is notable. But for a multiplayer platform where AI agents must appear alongside humans in real-time, the architecture requires bolting on most of what Phoenix provides natively: a WebSocket layer for presence, a pub/sub system for event-driven reactivity, streaming infrastructure for LLM output, and session management for agent lifecycle.

### The TypeScript AI ecosystem advantage is real but narrowing

The TypeScript ecosystem's AI tooling is undeniably richer: **Vercel AI SDK** (20M+ monthly downloads, v6 with DurableAgent), **LangChain.js** (used by LinkedIn, Uber, Klarna), and full MCP reference SDK. These provide higher-level abstractions — `streamText()`, `useChat()`, `ToolLoopAgent` — that accelerate development. However, they all run on a runtime that requires external infrastructure for the primitives Phoenix provides natively. Streaming to N clients requires Redis pub/sub. Agent lifecycle management requires application-level retry/recovery. Process isolation requires separate Node.js workers.

For a small team, the pragmatic path may be using Elixir for agent orchestration and real-time infrastructure while consuming TypeScript AI libraries via HTTP/MCP — agents don't need to run in the same process as the LLM SDK, they need to orchestrate calls to it.

---

## Developer experience: the TypeScript gravity well

### Talent asymmetry is the biggest practical concern

The numbers are stark. TypeScript is used by **38.5% of all developers** (Stack Overflow 2025); Elixir by approximately **1-2%**. The npm registry contains **2 million+ packages** versus hex.pm's **~15,000**. Hiring agencies describe experienced Elixir developers as "scarce," with one platform (Proxify) listing only 500 Elixir developers. Companies like Remote successfully use Elixir but acknowledge the hiring challenge, and onboarding developers from OOP backgrounds takes **3-6 months** of reduced productivity.

For a 3-8 person team with strong TypeScript skills and "growing Elixir interest," this is the decisive constraint for MVP timeline. Phoenix requires learning not just Elixir syntax but functional programming patterns, OTP concepts (GenServer, Supervisor, Application), the BEAM mental model, and Ecto's deliberate non-ORM approach. The team profile suggests at least 2-3 months before productive Elixir output.

### End-to-end type safety vs. battle-tested patterns

TypeScript's structural type system enforced at compile time is more comprehensive than Elixir's Dialyzer (gradual, opt-in success typing). The tRPC + Zod + Prisma/Drizzle stack provides a single source of truth from database schema through API contract to frontend component props. Elysia's Eden Treaty achieves similar end-to-end inference with **2.3x faster type checking than Hono**. This compile-time safety across the full stack catches entire classes of bugs that Elixir discovers only at runtime.

Elixir compensates with pattern matching (exhaustive case handling), immutable data structures (no accidental mutation), and Ecto changesets (data validation pipelines with compile-time query checking). Elixir v1.17+ introduced experimental set-theoretic types that may close the gap. In practice, Elixir's runtime safety model is different rather than worse — but it demands different discipline and catches errors at different stages.

### The ecosystem gap that matters most: rich text collaboration

For a "Figma meets ClickUp" product, collaborative rich text editing is table stakes. The TypeScript ecosystem is **dramatically stronger** here: **Tiptap** (ProseMirror-based, production-grade, first-class Yjs integration), **Hocuspocus** (open-source Yjs backend by the Tiptap team), and **Liveblocks** (commercial Yjs provider with React hooks). The entire Yjs ecosystem is JavaScript-native.

On the Elixir side, **y_ex** (v0.10.2, November 2025) wraps the Rust yrs library via NIF. It has good feature coverage but only **136 GitHub stars, a single maintainer, and 54,000 total downloads**. Sub-documents and weak links are marked "experimental." Slab, the most prominent Phoenix collaborative editor, uses **Operational Transform with a custom Delta library**, not CRDTs — and uses Channels, not LiveView, for the editing experience.

The pragmatic approach: use Tiptap + Yjs on the client with y_ex on the server for CRDT document synchronization via Phoenix Channels. This hybrid leverages both ecosystems' strengths.

---

## The hybrid architecture: best of both worlds

### Phoenix.Sync already exists as the integration layer

ElectricSQL and Phoenix have an **official integration library** (Phoenix.Sync, developed with José Valim's guidance). It maps Ecto queries to Electric Shapes, replaces `Phoenix.LiveView.stream/3` with `sync_stream/4` for auto-updating LiveViews, and provides a Writer module for ingesting client-side writes back into Postgres via `Ecto.Multi` transactions. The Writer returns Postgres **transaction IDs** so clients can tie optimistic state lifecycle to sync confirmation.

The architecture is clean: Electric handles read-path sync (Postgres → client via HTTP Shapes, CDN-cacheable), Phoenix handles write-path (client → Phoenix API → auth/validation/AI/business logic → Postgres), and shared PostgreSQL with `wal_level=logical` is the single source of truth. Electric reads from the WAL; Phoenix writes via Ecto.

This mirrors exactly what Linear and Figma have built — **server-authoritative with local-first reads** — but using off-the-shelf components instead of custom sync engines. The client gets instant UI from PGLite local queries (<0.3ms), the server maintains authority over mutations, AI agents participate naturally through Phoenix's real-time infrastructure, and Electric handles the complexity of efficiently syncing Postgres state to thousands of clients.

### The complexity cost is manageable but real

Running both BEAM and a JavaScript runtime adds operational surface area: **4-5 services minimum** (Postgres, Electric, Phoenix, CDN/cache, plus the frontend build). Schema changes require coordinating server migrations, Electric shape definitions, and client-side PGLite schema. The team needs competence in both Elixir and TypeScript.

However, the boundaries are clean. Elixir owns: AI agent orchestration, event-driven business logic, real-time presence, write-path validation, background jobs (Oban), and MCP server hosting. TypeScript owns: frontend UI, rich text editing (Tiptap/Yjs), client-side PGLite queries, and potentially AI SDK consumption for LLM interactions. The two runtimes communicate through Postgres and HTTP — no tight coupling.

For a team with strong TypeScript skills and growing Elixir interest, this hybrid lets them **ship the frontend fast** while incrementally building Elixir competence on the backend. The Electric sync layer means the frontend feels instant from day one, buying time for the team to master Phoenix's real-time patterns.

---

## Risk matrix

| Risk Factor | Phoenix/Elixir | ElectricSQL + PGLite |
|---|---|---|
| **Technology abandonment** | **Very low.** BEAM has 40+ year heritage. Phoenix backed by Dashbit (José Valim's company). Discord, WhatsApp, Discord validate at scale. | **Moderate.** ElectricSQL: $5M funding, ~11-person team, pivoting positioning (local-first → multi-agent). PGLite not yet v1.0. |
| **Bun/runtime stability** | N/A | **Moderate.** Acquired by Anthropic (Dec 2025) — reduces abandonment risk. But ~4.9k open issues, no LTS policy, segfaults reported across platforms. Node.js as fallback mitigates. |
| **Key library risk** | **Moderate.** y_ex: single maintainer, 136 stars. LiveSvelte: community-maintained. Oban, Ecto, Phoenix itself: very mature. | **Low for JS/TS libs.** Tiptap, Yjs, BullMQ all widely adopted. **Moderate for Electric-specific.** PGLite sync plugin, TanStack DB integration still evolving. |
| **Hiring risk** | **High.** Elixir talent pool is ~1-2% of developers. 3-6 month onboarding from OOP backgrounds. | **Low.** TypeScript is 38.5% of developers. Massive talent pool. |
| **Safari storage eviction** | N/A (server-side state) | **High.** Safari wipes IndexedDB after 7 days of site inactivity. Fatal for local-first if not handled. |
| **Schema evolution** | **Low.** Standard Postgres migrations, no restrictions. | **High.** Additive-only migrations for synced tables. Cannot remove columns or tighten constraints. |
| **Write-path complexity** | **Low.** Standard server-side mutations via Ecto. | **High.** Must build custom write-path, conflict resolution, shadow tables, change log sync. Linearlite demo is 1000+ lines of sync infrastructure. |
| **Scaling ceiling** | **Very high.** Discord proves 11M+ concurrent users. BEAM clustering is native. | **High for reads** (CDN fan-out). **Unknown for writes** (custom write-path is your bottleneck). |
| **Offline capability** | **None.** Fundamental limitation of LiveView. Must accept always-online requirement or add client-side layer. | **Excellent.** PGLite persists full Postgres to IndexedDB/OPFS. Full SQL queries offline. |

---

## The recommendation: Phoenix-first with strategic Electric integration

**For a small team (3-8 developers) building an AI-native multiplayer work management platform with a 6-9 month MVP timeline, start with Phoenix as the core architecture and add ElectricSQL as the read-path sync layer when instant UI responsiveness becomes a priority (likely post-MVP).**

The reasoning is structural: **your core differentiator is AI agents as first-class participants**, and no other mainstream runtime matches BEAM's architectural fitness for this. GenServer processes are agents. Supervision trees are agent lifecycle management. PubSub is event-driven reactivity. Presence is multiplayer awareness. These aren't libraries bolted onto a runtime — they're primitives of the runtime itself. Every dollar of engineering invested in Elixir's AI agent infrastructure compounds because you're building on the right abstraction level.

**Phase 1 (Months 1-6): Phoenix MVP.** Use Phoenix Channels for real-time multiplayer, Phoenix.Presence for awareness, Oban for background jobs, Ecto for data modeling. Build the frontend as a TypeScript SPA (React/Svelte) communicating via Channels and REST API — this lets the team leverage existing TypeScript skills immediately while learning Elixir on the backend. Use Tiptap + Yjs on the client with y_ex on the server for collaborative editing. AI agents run as supervised GenServers.

**Phase 2 (Months 6-12): Add Electric for read-path sync.** Once the data model stabilizes, introduce ElectricSQL to stream Postgres state to clients via Shapes. Replace REST polling with Electric sync for instant UI. Optionally add PGLite on the client for local caching and offline reads. Phoenix.Sync makes this integration straightforward. This gets you Linear-like responsiveness without rewriting the architecture.

**Phase 3 (Months 12+): Evaluate PGLite for offline.** If offline support proves to be a real user need (validate this — most work management happens online), add PGLite with IndexedDB persistence and implement the through-the-database write pattern for offline mutations.

**Conditions and caveats:**

- **If offline-first is truly non-negotiable for MVP** (e.g., field workers, unreliable connectivity), invert the recommendation: start with Architecture B and add a Phoenix WebSocket service for AI agents and presence. But verify this requirement rigorously — Linear and Figma proved you can build category-defining products without offline.
- **If hiring Elixir developers proves impossible**, the all-TypeScript path with Hono/Elysia + a WebSocket library + Redis pub/sub + LangGraph.js is viable. You'll spend more engineering effort recreating what Phoenix provides natively, but the talent pool advantage may outweigh this for some teams.
- **If your team's Elixir learning curve exceeds 3 months**, consider hiring one senior Elixir developer to architect the backend while the rest of the team focuses on the TypeScript frontend. One experienced Elixir developer can be extraordinarily productive — Discord runs their chat infrastructure with 5 engineers managing 20+ services.
- **y_ex is a real risk.** With a single maintainer and 136 stars, have a contingency plan: Hocuspocus (TypeScript Yjs server) as a sidecar, or running the Yjs CRDT logic in a Node.js service that communicates with Phoenix via PubSub.