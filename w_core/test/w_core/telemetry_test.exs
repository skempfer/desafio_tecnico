defmodule WCore.TelemetryTest do
  use WCore.DataCase

  alias WCore.Telemetry
  alias WCore.Telemetry.NodeMetrics
  alias WCore.Telemetry.TelemetryEvent

  describe "nodes" do
    alias WCore.Telemetry.Node

    import WCore.AccountsFixtures, only: [user_scope_fixture: 0]
    import WCore.TelemetryFixtures

    @invalid_attrs %{location: nil, machine_identifier: nil}

    test "list_nodes/1 returns all scoped nodes" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      node = node_fixture(scope)
      other_node = node_fixture(other_scope)
      assert Telemetry.list_nodes(scope) == [node]
      assert Telemetry.list_nodes(other_scope) == [other_node]
    end

    test "get_node!/2 returns the node with given id" do
      scope = user_scope_fixture()
      node = node_fixture(scope)
      other_scope = user_scope_fixture()
      assert Telemetry.get_node!(scope, node.id) == node
      assert_raise Ecto.NoResultsError, fn -> Telemetry.get_node!(other_scope, node.id) end
    end

    test "create_node/2 with valid data creates a node" do
      valid_attrs = %{location: "some location", machine_identifier: "some machine_identifier"}
      scope = user_scope_fixture()

      assert {:ok, %Node{} = node} = Telemetry.create_node(scope, valid_attrs)
      assert node.location == "some location"
      assert node.machine_identifier == "some machine_identifier"
      assert node.user_id == scope.user.id
    end

    test "create_node/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Telemetry.create_node(scope, @invalid_attrs)
    end

    test "update_node/3 with valid data updates the node" do
      scope = user_scope_fixture()
      node = node_fixture(scope)

      update_attrs = %{
        location: "some updated location",
        machine_identifier: "some updated machine_identifier"
      }

      assert {:ok, %Node{} = node} = Telemetry.update_node(scope, node, update_attrs)
      assert node.location == "some updated location"
      assert node.machine_identifier == "some updated machine_identifier"
    end

    test "update_node/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      node = node_fixture(scope)

      assert_raise MatchError, fn ->
        Telemetry.update_node(other_scope, node, %{})
      end
    end

    test "update_node/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      node = node_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Telemetry.update_node(scope, node, @invalid_attrs)
      assert node == Telemetry.get_node!(scope, node.id)
    end

    test "delete_node/2 deletes the node" do
      scope = user_scope_fixture()
      node = node_fixture(scope)
      assert {:ok, %Node{}} = Telemetry.delete_node(scope, node)
      assert_raise Ecto.NoResultsError, fn -> Telemetry.get_node!(scope, node.id) end
    end

    test "delete_node/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      node = node_fixture(scope)
      assert_raise MatchError, fn -> Telemetry.delete_node(other_scope, node) end
    end

    test "change_node/2 returns a node changeset" do
      scope = user_scope_fixture()
      node = node_fixture(scope)
      assert %Ecto.Changeset{} = Telemetry.change_node(scope, node)
    end
  end

  describe "hot state" do
    import WCore.AccountsFixtures, only: [user_scope_fixture: 0]
    import WCore.TelemetryFixtures

    test "list_nodes_with_hot_state/1 returns fallback when ETS is empty" do
      scope = user_scope_fixture()
      node = node_fixture(scope, %{machine_identifier: "sensor-fallback"})

      [row] = Telemetry.list_nodes_with_hot_state(scope)
      assert row.machine_identifier == node.machine_identifier
      assert row.status == "unknown"
      assert row.total_events_processed == 0
      assert row.last_seen_at == nil
    end

    test "list_nodes_with_hot_state/1 returns ETS values when present" do
      scope = user_scope_fixture()
      node = node_fixture(scope, %{machine_identifier: "sensor-hot"})
      ts = ~U[2026-04-04 12:00:00Z]

      WCore.Telemetry.Cache.put(node.machine_identifier, "online", %{temp: 42}, ts)

      [row] = Telemetry.list_nodes_with_hot_state(scope)
      assert row.machine_identifier == "sensor-hot"
      assert row.status == "online"
      assert row.total_events_processed == 1
      assert row.last_seen_at == ts
    end

    test "list_nodes_with_hot_state_paginated/2 uses default page size and metadata" do
      scope = user_scope_fixture()

      Enum.each(1..25, fn i ->
        node_fixture(scope, %{
          machine_identifier: "node-#{String.pad_leading(Integer.to_string(i), 2, "0")}"
        })
      end)

      page = Telemetry.list_nodes_with_hot_state_paginated(scope)

      assert page.page == 1
      assert page.per_page == 20
      assert page.total_entries == 25
      assert page.total_pages == 2
      assert page.has_prev == false
      assert page.has_next == true
      assert length(page.entries) == 20
      assert Enum.at(page.entries, 0).machine_identifier == "node-01"
    end

    test "list_nodes_with_hot_state_paginated/2 returns second page with remaining items" do
      scope = user_scope_fixture()

      Enum.each(1..25, fn i ->
        node_fixture(scope, %{
          machine_identifier: "node-#{String.pad_leading(Integer.to_string(i), 2, "0")}"
        })
      end)

      page = Telemetry.list_nodes_with_hot_state_paginated(scope, page: 2, per_page: 20)

      assert page.page == 2
      assert page.per_page == 20
      assert page.total_entries == 25
      assert page.total_pages == 2
      assert page.has_prev == true
      assert page.has_next == false
      assert length(page.entries) == 5
      assert Enum.at(page.entries, 0).machine_identifier == "node-21"
    end

    test "list_nodes_with_hot_state_paginated/2 clamps invalid values and keeps ETS enrichment" do
      scope = user_scope_fixture()

      Enum.each(1..3, fn i ->
        node_fixture(scope, %{machine_identifier: "sensor-#{i}"})
      end)

      ts = ~U[2026-04-04 13:00:00Z]
      WCore.Telemetry.Cache.put("sensor-2", "degraded", %{load: 93}, ts)

      page = Telemetry.list_nodes_with_hot_state_paginated(scope, page: -10, per_page: 0)

      assert page.page == 1
      assert page.per_page == 20
      assert page.total_entries == 3
      assert length(page.entries) == 3

      enriched = Enum.find(page.entries, &(&1.machine_identifier == "sensor-2"))
      assert enriched.status == "degraded"
      assert enriched.total_events_processed == 1
      assert enriched.last_seen_at == ts
    end

    test "list_nodes_with_hot_state_paginated/2 filters by machine identifier and location" do
      scope = user_scope_fixture()

      node_fixture(scope, %{machine_identifier: "reactor-alpha", location: "North Wing"})
      node_fixture(scope, %{machine_identifier: "pump-beta", location: "South Bay"})
      node_fixture(scope, %{machine_identifier: "sensor-gamma", location: "Line A"})

      page_machine =
        Telemetry.list_nodes_with_hot_state_paginated(scope,
          page: 1,
          per_page: 20,
          search: "ReAcToR"
        )

      assert page_machine.total_entries == 1
      assert length(page_machine.entries) == 1
      assert hd(page_machine.entries).machine_identifier == "reactor-alpha"

      page_location =
        Telemetry.list_nodes_with_hot_state_paginated(scope,
          page: 1,
          per_page: 20,
          search: "south"
        )

      assert page_location.total_entries == 1
      assert length(page_location.entries) == 1
      assert hd(page_location.entries).location == "South Bay"
    end

    test "list_nodes_with_hot_state_paginated/2 filters by status and keeps counts" do
      scope = user_scope_fixture()

      node_fixture(scope, %{machine_identifier: "reactor-online", location: "A"})
      node_fixture(scope, %{machine_identifier: "reactor-offline", location: "B"})
      node_fixture(scope, %{machine_identifier: "reactor-unknown", location: "C"})

      ts = ~U[2026-04-04 15:00:00Z]
      WCore.Telemetry.Cache.put("reactor-online", "online", %{}, ts)
      WCore.Telemetry.Cache.put("reactor-offline", "offline", %{}, ts)

      page = Telemetry.list_nodes_with_hot_state_paginated(scope, status: "offline")

      assert page.total_entries == 1
      assert length(page.entries) == 1
      assert hd(page.entries).machine_identifier == "reactor-offline"
      assert page.status_counts.all == 3
      assert page.status_counts.online == 1
      assert page.status_counts.offline == 1
      assert page.status_counts.unknown == 1

      page_others = Telemetry.list_nodes_with_hot_state_paginated(scope, status: "others")
      assert page_others.total_entries == 1
      assert hd(page_others.entries).machine_identifier == "reactor-unknown"
    end

    test "list_nodes_with_hot_state_paginated/2 sorts by events and last_seen" do
      scope = user_scope_fixture()
      ts1 = ~U[2026-04-04 10:00:00Z]
      ts2 = ~U[2026-04-04 11:00:00Z]
      ts3 = ~U[2026-04-04 12:00:00Z]

      node_fixture(scope, %{machine_identifier: "node-a", location: "A"})
      node_fixture(scope, %{machine_identifier: "node-b", location: "B"})
      node_fixture(scope, %{machine_identifier: "node-c", location: "C"})

      WCore.Telemetry.Cache.put("node-a", "online", %{}, ts1)
      WCore.Telemetry.Cache.put("node-b", "online", %{}, ts2)
      WCore.Telemetry.Cache.put("node-c", "online", %{}, ts3)

      WCore.Telemetry.Cache.put("node-a", "online", %{}, ts1)
      WCore.Telemetry.Cache.put("node-b", "online", %{}, ts2)

      page_events_desc =
        Telemetry.list_nodes_with_hot_state_paginated(scope,
          sort_by: "events",
          sort_dir: "desc"
        )

      assert Enum.map(page_events_desc.entries, & &1.machine_identifier) == [
               "node-b",
               "node-a",
               "node-c"
             ]

      page_last_seen_desc =
        Telemetry.list_nodes_with_hot_state_paginated(scope,
          sort_by: "last_seen",
          sort_dir: "desc"
        )

      assert Enum.map(page_last_seen_desc.entries, & &1.machine_identifier) == [
               "node-c",
               "node-b",
               "node-a"
             ]
    end
  end

  describe "machine error history" do
    import WCore.AccountsFixtures, only: [user_scope_fixture: 0]
    import WCore.TelemetryFixtures

    test "record_telemetry_event/4 stores a structured error message fallback for problem states" do
      timestamp = ~U[2026-04-05 21:00:00Z]

      assert {:ok, %TelemetryEvent{} = event} =
               Telemetry.record_telemetry_event("sensor-error", "offline", %{}, timestamp)

      assert event.error_message == "Machine reported offline"
      assert event.resolved_at == nil
    end

    test "record_telemetry_event/4 prefers payload error text when available" do
      timestamp = ~U[2026-04-05 21:01:00Z]

      assert {:ok, %TelemetryEvent{} = event} =
               Telemetry.record_telemetry_event(
                 "sensor-error",
                 "degraded",
                 %{"message" => "Motor overheating"},
                 timestamp
               )

      assert event.error_message == "Motor overheating"
    end

    test "list_machine_error_events/3 paginates unresolved degraded and offline events" do
      scope = user_scope_fixture()
      node_fixture(scope, %{machine_identifier: "reactor-01", location: "Bay A"})

      Enum.each(1..12, fn i ->
        occurred_at = DateTime.add(~U[2026-04-05 10:00:00Z], i, :second)

        Telemetry.record_telemetry_event(
          "reactor-01",
          if(rem(i, 2) == 0, do: "offline", else: "degraded"),
          %{"message" => "Error #{i}"},
          occurred_at
        )
      end)

      Telemetry.record_telemetry_event(
        "reactor-01",
        "online",
        %{"message" => "Ignore online"},
        ~U[2026-04-05 11:00:00Z]
      )

      page_1 = Telemetry.list_machine_error_events(scope, "reactor-01")
      page_2 = Telemetry.list_machine_error_events(scope, "reactor-01", page: 2)

      assert page_1.total_entries == 12
      assert page_1.total_pages == 2
      assert page_1.page == 1
      assert page_1.has_next == true
      assert length(page_1.entries) == 10
      assert hd(page_1.entries).error_message == "Error 12"

      assert page_2.page == 2
      assert page_2.has_prev == true
      assert page_2.has_next == false
      assert length(page_2.entries) == 2
      assert Enum.at(page_2.entries, 1).error_message == "Error 1"
    end

    test "resolve_machine_error_events/3 marks only selected scoped events as resolved" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()

      node_fixture(scope, %{machine_identifier: "reactor-01", location: "Bay A"})
      node_fixture(other_scope, %{machine_identifier: "reactor-02", location: "Bay B"})

      {:ok, event_1} =
        Telemetry.record_telemetry_event(
          "reactor-01",
          "offline",
          %{"message" => "Power loss"},
          ~U[2026-04-05 12:00:00Z]
        )

      {:ok, event_2} =
        Telemetry.record_telemetry_event(
          "reactor-01",
          "degraded",
          %{"message" => "High vibration"},
          ~U[2026-04-05 12:01:00Z]
        )

      {:ok, _other_event} =
        Telemetry.record_telemetry_event(
          "reactor-02",
          "offline",
          %{"message" => "Foreign machine"},
          ~U[2026-04-05 12:02:00Z]
        )

      assert 1 = Telemetry.resolve_machine_error_events(scope, "reactor-01", [event_1.id])

      resolved_event = Repo.get!(TelemetryEvent, event_1.id)
      unresolved_event = Repo.get!(TelemetryEvent, event_2.id)

      assert resolved_event.resolved_at != nil
      assert unresolved_event.resolved_at == nil

      page = Telemetry.list_machine_error_events(scope, "reactor-01")
      assert Enum.map(page.entries, & &1.id) == [event_2.id]
      assert 0 = Telemetry.resolve_machine_error_events(other_scope, "reactor-01", [event_2.id])
    end

    test "resolve_machine_error_events/3 sets machine online and refreshes last_seen_at when no unresolved errors remain" do
      scope = user_scope_fixture()
      node = node_fixture(scope, %{machine_identifier: "reactor-03", location: "Bay C"})
      previous_last_seen = ~U[2026-04-05 12:30:00Z]
      payload = %{"message" => "Recovered"}

      assert {:ok, _metric} =
               Telemetry.upsert_node_metric(node, %{
                 status: "offline",
                 total_events_processed: 7,
                 last_payload: payload,
                 last_seen_at: previous_last_seen
               })

      WCore.Telemetry.Cache.put_snapshot("reactor-03", "offline", 7, payload, previous_last_seen)

      {:ok, event} =
        Telemetry.record_telemetry_event(
          "reactor-03",
          "offline",
          %{"message" => "Power issue"},
          ~U[2026-04-05 13:00:00Z]
        )

      assert 1 = Telemetry.resolve_machine_error_events(scope, "reactor-03", [event.id])

      metric = Repo.get_by!(NodeMetrics, node_id: node.id)
      assert metric.status == "online"
      assert DateTime.compare(metric.last_seen_at, previous_last_seen) == :gt

      row = Telemetry.get_node_with_hot_state(scope, "reactor-03")
      assert row.status == "online"
      assert row.last_seen_at == metric.last_seen_at
    end
  end
end
