# Step 4 - Chaos Simulation (Rigorous Tests)

## Mission

Prove the telemetry pipeline resilience under extreme concurrency.

Critical checks:

1. ETS does not lose event counts under high concurrency.
2. No race condition is observable in per-machine aggregates.
3. SQLite receives synchronized state that matches memory.

## Implemented Solution

- Test created in `test/w_core/telemetry_chaos_test.exs`.
- Automated scenario with 10 machines and 1,000 events per machine (10,000 total).
- Concurrent ingestion via `Task.async_stream/3` using `max_concurrency: System.schedulers_online() * 4`.
- SQLite synchronization performed through a manual flush path in the test (`Cache.get_all/0` + `Telemetry.upsert_node_metrics_batch/1`) because `WCore.Telemetry.Worker` is disabled in `MIX_ENV=test`.
- Implemented validations:
  - all 10,000 events are ingested successfully;
  - ETS ends with 10 keys and `1_000` events per machine;
  - ETS total count is `10_000`;
  - `node_metrics` in SQLite has 10 rows and `1_000` per machine;
  - total in `node_metrics` is `10_000`;
  - `telemetry_events` persists 10,000 events from the batch;
  - per-machine count map in SQLite matches the ETS map (explicit anti-race assertion).

---

## Step-by-Step Execution

1. Open the project and confirm the Step 4 branch.

```bash
cd /c/Users/shana/desafio_tecnico
git checkout step-4-tests
cd w_core
```

2. Ensure compatible runtime on Windows (OTP/Elixir aligned with this project).

```bash
export PATH="/c/Users/shana/AppData/Local/mise/installs/erlang/27.3.4.9/bin:/c/Users/shana/AppData/Local/mise/installs/elixir/1.18.4-otp-27/bin:$PATH"
elixir --version
```

3. Prepare the local test environment.

```bash
mix deps.get
MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate
```

4. Use the already-implemented chaos integration test in `test/w_core/telemetry_chaos_test.exs`.

5. In the test setup:
   - clear ETS (`:ets.delete_all_objects(:w_core_telemetry_cache)`);
   - create machines in DB (`nodes`) so flush can persist to `node_metrics`;
   - define deterministic load parameters:
     - `machines = 10`
     - `events_per_machine = 1_000`
     - `total_expected = 10_000`

6. Inject 10,000 concurrent events.
   - Generate a balanced workload list across machines.
   - Use `Task.async_stream/3` to parallelize calls to `WCore.Telemetry.Ingester.ingest_event/4`.
   - Keep high concurrency and a safe timeout:
     - `max_concurrency: System.schedulers_online() * 4`
     - `ordered: false`
     - `timeout: :infinity`

7. Assert concurrent ingestion result.
   - Every return should match `{:ok, count}`.
   - Total number of results must be exactly 10,000.

8. Prove ETS integrity after the event storm.
   - Read `:ets.tab2list(:w_core_telemetry_cache)`.
   - Required assertions:
     - exactly 10 records (one per machine);
     - sum of all `count` values equals `10_000`;
     - each machine ends at `count == 1_000`.

9. Force synchronization to SQLite (flush).
   - If `WCore.Telemetry.Worker` is active in test, send `:flush` and wait briefly.
   - If not active in test, run the same persistence path manually:
     - `records = WCore.Telemetry.Cache.get_all()`
     - `persisted_keys = WCore.Telemetry.upsert_node_metrics_batch(records)`
     - for each persisted key, mark events as processed with `mark_unprocessed_events_as_processed/3`.

10. Prove SQLite synchronization.
    - In `node_metrics`:
      - there are 10 rows (one per machine);
      - sum of `total_events_processed` is `10_000`;
      - each machine has `total_events_processed == 1_000`.
    - In `telemetry_events`:
      - there are 10,000 persisted events;
      - all events from this batch are marked as processed after flush.

11. Add an explicit anti-race verification.
    - Re-read ETS and SQLite at the end of the test.
    - Compare per-machine counters (`machine_identifier => count`) between memory and DB.
    - Final assertion: maps are identical and totals are consistent.

12. Run tests and capture evidence.

```bash
mix test test/w_core/telemetry_chaos_test.exs --seed 0 --max-cases 1
mix test
```

Current chaos test execution result:

- `1 test, 0 failures`

## How To Run With 10,000 Machines

The implemented test in `test/w_core/telemetry_chaos_test.exs` uses fixed module attributes.

To run the 10,000-machine scenario, temporarily change:

- `@machines 10_000`
- `@events_per_machine 1`

Important note:

- With this setup, total events remain 10,000 (`10_000 x 1`), preserving the Step 4 objective.
- If you set `@events_per_machine 1_000` together with `@machines 10_000`, the test sends 10 million events and may be impractical on a standard local machine.

Command to run only the chaos test:

```bash
mix test test/w_core/telemetry_chaos_test.exs --seed 0 --max-cases 1
```

After validation, restore original test parameters (or keep a separate commit for this load profile).

## How To Run All Tests

To run the entire test suite:

```bash
mix test
```

Optional (full quality pipeline):

```bash
make quality
```

---

## Test Structure Example (Reference)

```elixir
test "chaos: 10,000 concurrent events without loss and synchronized SQLite state" do
  machines = for i <- 1..10, do: "chaos-node-#{i}"
  events_per_machine = 1_000
  total_expected = 10_000

  # 1) Build workload
  workload =
    for machine <- machines,
        idx <- 1..events_per_machine do
      {machine, idx}
    end

  # 2) Concurrent injection
  results =
    workload
    |> Task.async_stream(
      fn {machine, idx} ->
        ts = DateTime.add(~U[2026-04-06 00:00:00Z], idx, :second)
        WCore.Telemetry.Ingester.ingest_event(machine, "online", %{"seq" => idx}, ts)
      end,
      max_concurrency: System.schedulers_online() * 4,
      ordered: false,
      timeout: :infinity
    )
    |> Enum.to_list()

  assert length(results) == total_expected
  assert Enum.all?(results, fn
           {:ok, {:ok, _count}} -> true
           _ -> false
         end)

  # 3) Validate ETS
  ets_rows = :ets.tab2list(:w_core_telemetry_cache)
  assert length(ets_rows) == 10

  total_in_ets = Enum.reduce(ets_rows, 0, fn {_id, _s, c, _p, _t}, acc -> acc + c end)
  assert total_in_ets == total_expected

  # 4) Flush to SQLite (worker or manual path)
  # ...

  # 5) Validate SQLite
  # assert sum(node_metrics.total_events_processed) == 10_000
  # assert telemetry_events processed == 10_000
end
```

---

## Step 4 Acceptance Criteria

Step 4 is complete when the chaos test proves, through automated assertions, that:

1. Total ETS counter matches exactly 10,000 events.
2. ETS per-machine counters are correct (1,000 per machine).
3. Projected state in SQLite `node_metrics` matches ETS.
4. No batch event remains with `processed_at = nil` after synchronization.
5. The test passes consistently across repeated runs.
