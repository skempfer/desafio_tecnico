# Step 2 - OTP, ETS, Durability & Write-Behind

## Runtime Components

- `WCore.Telemetry.Cache` owns ETS table `:w_core_telemetry_cache`
- `WCore.Telemetry.Ingester` receives ingestion requests and persists raw events first
- `WCore.Telemetry.Worker` recovers pending events on boot and flushes cache to SQLite every 5 seconds
- `WCore.Telemetry.TelemetryEvent` stores the durable raw event log in `telemetry_events`
- Components run under the application supervisor together with `WCore.Repo`, `Ecto.Migrator`, `Phoenix.PubSub`, `WCoreWeb.Endpoint`, `WCoreWeb.Telemetry`, and `DNSCluster`

## Architectural Decisions

- Ingestion is handled through `GenServer.call/2` to guarantee request/response semantics.
- The ingester writes to `telemetry_events` before touching ETS, so raw events are durable even if the node crashes before flush.
- ETS remains the fast in-memory state used for real-time latest value and per-node counter.
- Flush persistence uses batch upsert (`Repo.insert_all` with conflict handling) into `node_metrics`, avoiding one write operation per row.
- Event completion is tracked by `processed_at` in `telemetry_events`.
- Worker startup performs replay of unprocessed events to recover state after restart.

## ETS Record Format

### `:w_core_telemetry_cache`

| Position | Field       | Description                                           |
| -------- | ----------- | ----------------------------------------------------- |
| 1        | `node_id`   | Cache key, matched against `nodes.machine_identifier` |
| 2        | `status`    | Latest node status                                    |
| 3        | `count`     | Monotonic in-memory event counter for that node       |
| 4        | `payload`   | Latest raw payload                                    |
| 5        | `timestamp` | Latest event timestamp                                |

Stored tuple shape:

```elixir
{node_id, status, count, payload, timestamp}
```

## Durable Event Schema (`telemetry_events`)

- `machine_identifier` (`:string`, required)
- `status` (`:string`, required)
- `payload` (`:map`)
- `occurred_at` (`:utc_datetime`, required)
- `processed_at` (`:utc_datetime`, nullable)

This table is the source of truth for events that must survive crashes and restarts.

## Execution Flow

### 1. Ingestion Path

- `WCore.Telemetry.Ingester.ingest_event/4` sends a synchronous `{:ingest, ...}` message via `GenServer.call/2`
- `handle_call/3` persists raw event through `WCore.Telemetry.record_telemetry_event/4`
- If persistence succeeds, the ingester updates ETS with `WCore.Telemetry.Cache.put/4`
- Then it broadcasts `{:metric_update, node_id, status, event_count, payload, timestamp}` to topic `"telemetry: #{node_id}"`
- Return value is `{:ok, event_count}` or `{:error, reason}`

### 2. Worker Boot Recovery

- `WCore.Telemetry.Worker.init/1` calls `recover_unprocessed_events/0`
- Recovery reads pending events using `WCore.Telemetry.get_unprocessed_telemetry_events/0`
- Pending events are ordered by `occurred_at` and `id` for deterministic replay
- For each recoverable event, worker upserts `node_metrics` and marks event processed via `mark_telemetry_event_processed/2`
- Worker schedules periodic flush with `Process.send_after/3`

### 3. Periodic Flush

- `handle_info(:flush, state)` reads all ETS rows via `Cache.get_all/0`
- Records are persisted through `WCore.Telemetry.upsert_node_metrics_batch/1`
- Batch function resolves node IDs from machine identifiers and executes a single `insert_all` with upsert conflict strategy on `node_id`
- Worker marks related durable events as processed with `mark_unprocessed_events_as_processed/3`
- Next flush tick is scheduled at the end of the cycle

## Write-Behind Mapping

| ETS field   | `node_metrics` column    |
| ----------- | ------------------------ |
| `status`    | `status`                 |
| `count`     | `total_events_processed` |
| `payload`   | `last_payload`           |
| `timestamp` | `last_seen_at`           |

## Reliability Characteristics

- Raw event durability exists before cache update (`telemetry_events`).
- Restart safety exists through replay of events with `processed_at IS NULL`.
- `node_metrics` remains an idempotent latest-state projection keyed by `node_id`.
- If `Worker` crashes, ETS survives (owned by `Cache`) and flush resumes on restart.
- If `Cache` crashes, ETS state is lost, but raw event history is still in `telemetry_events`.
