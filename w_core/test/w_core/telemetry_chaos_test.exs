defmodule WCore.TelemetryChaosTest do
  use WCore.DataCase, async: false

  import Ecto.Query

  alias WCore.Telemetry
  alias WCore.Telemetry.Cache
  alias WCore.Telemetry.Ingester
  alias WCore.Telemetry.Node
  alias WCore.Telemetry.NodeMetrics
  alias WCore.Telemetry.TelemetryEvent

  import WCore.AccountsFixtures, only: [user_scope_fixture: 0]
  import WCore.TelemetryFixtures, only: [node_fixture: 2]

  @machines 10
  @events_per_machine 1_000
  @total_expected @machines * @events_per_machine

  setup do
    Cache.clear()
    :ok
  end

  test "chaos: 10,000 concurrent events without loss and with synchronized SQLite state" do
    scope = user_scope_fixture()
    unique = System.unique_integer([:positive])

    machines =
      for i <- 1..@machines do
        machine_identifier = "chaos-node-#{unique}-#{i}"
        node_fixture(scope, %{machine_identifier: machine_identifier, location: "chaos-zone-#{i}"})
        machine_identifier
      end

    workload =
      for machine_identifier <- machines,
          seq <- 1..@events_per_machine do
        {machine_identifier, seq}
      end

    results =
      workload
      |> Task.async_stream(
        fn {machine_identifier, seq} ->
          timestamp = DateTime.add(~U[2026-04-06 00:00:00Z], seq, :second)

          Ingester.ingest_event(
            machine_identifier,
            "online",
            %{"seq" => seq},
            timestamp
          )
        end,
        max_concurrency: System.schedulers_online() * 4,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.to_list()

    assert length(results) == @total_expected

    assert Enum.all?(results, fn
             {:ok, {:ok, _count}} -> true
             _ -> false
           end)

    ets_rows = :ets.tab2list(:w_core_telemetry_cache)
    assert length(ets_rows) == @machines

    ets_counts_by_machine =
      ets_rows
      |> Enum.map(fn {machine_identifier, _status, count, _payload, _timestamp} ->
        {machine_identifier, count}
      end)
      |> Map.new()

    assert Enum.all?(machines, fn machine_identifier ->
             Map.get(ets_counts_by_machine, machine_identifier) == @events_per_machine
           end)

    assert Enum.reduce(ets_counts_by_machine, 0, fn {_machine, count}, acc -> acc + count end) ==
             @total_expected

    flush_cache_to_sqlite()

    db_counts_by_machine =
      from(n in Node,
        join: m in NodeMetrics,
        on: m.node_id == n.id,
        where: n.machine_identifier in ^machines,
        select: {n.machine_identifier, m.total_events_processed}
      )
      |> Repo.all()
      |> Map.new()

    assert map_size(db_counts_by_machine) == @machines

    assert Enum.all?(machines, fn machine_identifier ->
             Map.get(db_counts_by_machine, machine_identifier) == @events_per_machine
           end)

    assert Enum.reduce(db_counts_by_machine, 0, fn {_machine, count}, acc -> acc + count end) ==
             @total_expected

    total_events_persisted =
      from(e in TelemetryEvent,
        where: e.machine_identifier in ^machines,
        select: count(e.id)
      )
      |> Repo.one()

    assert total_events_persisted == @total_expected

    assert db_counts_by_machine == ets_counts_by_machine
  end

  defp flush_cache_to_sqlite do
    records = Cache.get_all()
    persisted_keys = Telemetry.upsert_node_metrics_batch(records)
    processed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.each(persisted_keys, fn {machine_identifier, occurred_at} ->
      Telemetry.mark_unprocessed_events_as_processed(machine_identifier, occurred_at, processed_at)
    end)

    :ok
  end
end
