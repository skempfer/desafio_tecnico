defmodule WCore.Telemetry.Worker do
  @moduledoc """
  Periodic GenServer that flushes in-memory telemetry data from
  `WCore.Telemetry.Cache` to the database every `#{div(5_000, 1_000)}` seconds.

  ## Flush cycle

  On startup, `init/1` schedules a `:flush` message via `Process.send_after/3`.
  When `handle_info(:flush, state)` fires it:

  1. Reads **all** entries from the ETS cache with `Cache.get_all/0`.
  2. For each entry, looks up the corresponding `Node` by `machine_identifier`.
  3. Calls `WCore.Telemetry.upsert_node_metric/2` to persist (insert or update)
     the aggregated metric row in the database.
  4. Re-schedules itself for the next cycle — this guarantees exactly one
     pending `:flush` message at a time and avoids timer accumulation if a
     cycle takes longer than the interval.

  ## Idempotency and restart safety

  The ETS table is **owned by `WCore.Telemetry.Cache`**, a separate supervised
  process. This means:

  - If the **Worker crashes**, the cached data survives. On restart, `init/1`
    calls `schedule_work/0` again and the next flush picks up all data that
    accumulated while the Worker was down — no gaps.
  - If the **Cache crashes**, the ETS table is destroyed with its owner process.
    Events ingested between the last successful flush and the crash are lost.
    This is an accepted trade-off: the cache is a best-effort buffer, not a
    durable log.

  **No duplicate rows** are produced because `upsert_node_metric/2` is an
  upsert: it always overwrites the existing metric row for a node rather than
  inserting a second one. Flushing the same cache entry twice writes the same
  value to the database, so repeated flushes are idempotent.

  The `total_events_processed` field stores the cumulative counter that the
  cache has kept since the last Cache restart. If the Cache is restarted (ETS
  wiped), the counter resets to `1` on the first new event, and the next flush
  overwrites the DB value accordingly. This is by design: the counter reflects
  events seen *since boot*, not a global lifetime total.
  """

  use GenServer

  alias WCore.Telemetry
  alias WCore.Telemetry.Cache

  @interval 5_000

  @type state :: map()
  @type processed_key :: {Cache.node_id(), Cache.event_timestamp()}

  @doc """
  Starts the Worker process and registers it under the module name.
  """
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initialises state and schedules the first `:flush` tick.
  """
  @impl true
  @spec init(term()) :: {:ok, state()}
  def init(_opts) do
    recover_unprocessed_events()
    schedule_work()
    {:ok, %{}}
  end

  @spec recover_unprocessed_events() :: :ok
  defp recover_unprocessed_events do
    unprocessed = Telemetry.get_unprocessed_telemetry_events()

    Enum.each(unprocessed, &recover_event/1)

    :ok
  end

  @spec recover_event(WCore.Telemetry.TelemetryEvent.t()) :: :ok
  defp recover_event(event) do
    case Telemetry.get_node_by_machine_identifier(event.machine_identifier) do
      nil ->
        :ok

      node ->
        total_events_processed =
          case Telemetry.get_last_metric_by_node(node.id) do
            nil -> 1
            metric -> metric.total_events_processed + 1
          end

        Telemetry.upsert_node_metric(node, %{
          status: event.status,
          total_events_processed: total_events_processed,
          last_payload: event.payload,
          last_seen_at: event.occurred_at
        })

        Telemetry.mark_telemetry_event_processed(event.id, DateTime.utc_now())

        :ok
    end
  end

  @doc """
  Handles the periodic `:flush` message.

  Reads all entries from ETS cache and persists metrics in batch via
  `WCore.Telemetry.upsert_node_metrics_batch/1`, then re-schedules the next
  tick.
  """
  @impl true
  @spec handle_info(:flush, state()) :: {:noreply, state()}
  def handle_info(:flush, state) do
    records = Cache.get_all()
    processed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    records
    |> Telemetry.upsert_node_metrics_batch()
    |> Enum.each(&mark_processed_key(&1, processed_at))

    schedule_work()
    {:noreply, state}
  end

  @spec mark_processed_key(processed_key(), DateTime.t()) :: non_neg_integer()
  defp mark_processed_key({machine_identifier, occurred_at}, processed_at) do
    Telemetry.mark_unprocessed_events_as_processed(machine_identifier, occurred_at, processed_at)
  end

  # Schedules a single :flush message after @interval milliseconds.
  # Called both from init/1 and at the end of each handle_info/2 cycle,
  # ensuring there is always exactly one pending timer.
  @spec schedule_work() :: reference()
  defp schedule_work do
    Process.send_after(self(), :flush, @interval)
  end
end
