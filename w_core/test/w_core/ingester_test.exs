defmodule WCore.Telemetry.IngesterTest do
  use WCore.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias WCore.Telemetry.{Ingester, Node, NodeMetrics, Worker}

  setup do
    :ets.delete_all_objects(:w_core_telemetry_cache)

    if worker_pid = Process.whereis(Worker) do
      Sandbox.allow(WCore.Repo, self(), worker_pid)
    end

    :ok
  end

  test "ingest_event updates ETS correctly" do
    Ingester.ingest_event("sensor-1", "online", %{temp: 25}, ~U[2024-06-05 12:00:00Z])

    Process.sleep(50)

    assert [{"sensor-1", status, count, payload, _ts}] =
             :ets.lookup(:w_core_telemetry_cache, "sensor-1")

    assert status == "online"
    assert count == 1
    assert payload == %{temp: 25}
  end

  test "event_count increments" do
    Ingester.ingest_event("sensor-1", "online", %{}, ~U[2024-06-05 12:00:00Z])
    Ingester.ingest_event("sensor-1", "online", %{}, ~U[2024-06-05 12:01:00Z])

    Process.sleep(50)

    assert [{"sensor-1", "online", count, %{}, _ts}] =
             :ets.lookup(:w_core_telemetry_cache, "sensor-1")

    assert count == 2
  end

  test "worker flushes ETS to SQLite" do
    {:ok, node} =
      %Node{machine_identifier: "sensor-1", location: "lab"}
      |> Repo.insert()

    Ingester.ingest_event("sensor-1", "online", %{a: 1}, DateTime.utc_now())
    Ingester.ingest_event("sensor-1", "degraded", %{a: 2}, DateTime.utc_now())

    Process.sleep(50)
    send(worker_pid(), :flush)
    Process.sleep(50)

    metric = Repo.get_by(NodeMetrics, node_id: node.id)

    assert metric.status == "degraded"
    assert metric.total_events_processed == 2
  end

  defp worker_pid do
    Process.whereis(Worker)
  end

  test "ingest_event persists the raw event before updating ETS" do
    timestamp = ~U[2024-06-05 12:00:00Z]

    assert {:ok, 1} =
            Ingester.ingest_event("sensor-1", "online", %{temp: 25}, timestamp)

    assert [{"sensor-1", "online", 1, %{temp: 25}, ^timestamp}] =
            :ets.lookup(:w_core_telemetry_cache, "sensor-1")

    event =
      Repo.get_by!(WCore.Telemetry.TelemetryEvent,
        machine_identifier: "sensor-1",
        occurred_at: timestamp
      )

    assert event.status == "online"
    assert event.payload == %{"temp" => 25}
    assert event.processed_at == nil
  end
end
