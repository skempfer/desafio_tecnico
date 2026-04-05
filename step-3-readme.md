# W Core - Step 3: Control Room, LiveView & Anti-Bottleneck PubSub

This phase extends **W Core** with a real-time authenticated dashboard built on Phoenix LiveView, a pure HEEx component library, and a lightweight PubSub strategy designed to avoid message broadcast bottlenecks at scale.

The goal of this step is to expose live telemetry data through an interactive, authenticated UI that reacts instantly to sensor events without flooding connected clients with full payloads.

## What's Included

- Authenticated Control Room (`/control-room`):
  - `WCoreWeb.TelemetryLive.Dashboard` (LiveView with coalescence-based refresh)
  - Scoped to the current user — each user sees only their own nodes
  - Requires authentication via `on_mount: :require_authenticated_user`
- Hot-State API:
  - `WCore.Telemetry.list_nodes_with_hot_state/1` (merges DB nodes with live ETS values)
  - Fallback to `"unknown"` status for nodes not yet seen in ETS
- Lightweight PubSub strategy (anti-bottleneck):
  - `WCore.Telemetry.subscribe_dashboard_updates/0`
  - `WCore.Telemetry.broadcast_dashboard_node_changed/3`
  - Broadcasts only `{:node_changed, machine_identifier, event_count, timestamp}` — no full payload
  - `WCore.Telemetry.Ingester` extended to emit dashboard signals after each ingestion
- Coalescence window (50ms):
  - Incoming PubSub signals accumulate node IDs in a `MapSet` (`pending_node_ids`)
  - A single `Process.send_after/3` triggers one batch refresh per window
  - Prevents redundant re-renders when multiple events arrive in quick succession
- Pure HEEx component library:
  - `WCoreWeb.TelemetryComponents.status_badge/1` (online → green, offline → red, degraded → yellow, unknown → gray)
  - No external UI frameworks — fully server-rendered
- Quality hardening:
  - `make quality` passing (format, credo, dialyzer, tests, sobelow)

## Prerequisites

- Elixir 1.15+
- Phoenix 1.8+
- SQLite3

## Setup

From the project root:

```bash
cd w_core
mix deps.get
mix ecto.create
mix ecto.migrate
```

## Running the Server

```bash
mix phx.server
```

Visit http://localhost:4000.

To interact with the running system via IEx:

```bash
iex -S mix phx.server
```

## Creating Nodes (IEx)

```elixir
import Ecto.Query
user = WCore.Repo.one(from u in WCore.Accounts.User)
scope = WCore.Accounts.Scope.for_user(user)

Enum.each(1..3, fn i ->
  WCore.Telemetry.create_node(scope, %{
    "machine_identifier" => "reactor_#{i}",
    "location" => "Planta 42 - Zone #{i}"
  })
end)
```

## Simulating Sensor Events (IEx)

```elixir
# Ingest events to populate ETS and trigger real-time dashboard updates
Enum.each(1..3, fn i ->
  WCore.Telemetry.Ingester.ingest_event(
    "reactor_#{i}",
    "online",
    %{"temperature" => 40 + i, "cpu" => 60 + i},
    DateTime.utc_now()
  )
end)

# Simulate degraded and offline nodes
WCore.Telemetry.Ingester.ingest_event("reactor_2", "degraded", %{}, DateTime.utc_now())
WCore.Telemetry.Ingester.ingest_event("reactor_3", "offline", %{}, DateTime.utc_now())
```

## Running Quality Checks

```bash
make quality
```

## Key Files & Directories

- `lib/w_core_web/live/telemetry_live/dashboard.ex` — authenticated LiveView with MapSet coalescence
- `lib/w_core_web/components/telemetry_components.ex` — pure HEEx `status_badge/1` component
- `lib/w_core/telemetry.ex` — hot-state API and lightweight PubSub broadcast functions
- `lib/w_core/telemetry/ingester.ex` — extended to broadcast dashboard signals after ingestion
- `lib/w_core_web/router.ex` — `/control-room` route added to authenticated live session
- `test/w_core_web/live/telemetry_live/dashboard_test.exs` — auth redirect, render, and real-time update tests
- `docs/drafts/step-3-liveview-ds.md` — detailed technical documentation including PubSub bottleneck analysis and diagrams

## Next Steps

- Step 4 - Chaos Simulation (Rigorous Tests):
  Add resilience tests, including an integration test that injects 10,000 concurrent events, proving through assertions that ETS counts are preserved, no race condition occurs, and SQLite state is synchronized correctly. Deliverable: `docs/drafts/step-4-tests.md`.
- Step 5 - Edge Packaging (Infrastructure):
  Finalize Docker infrastructure with an optimized Mix release and persistent SQLite volume strategy. Deliverable: `docs/drafts/step-5-infra-arch.md` (including a final architecture diagram of the end-to-end flow).
