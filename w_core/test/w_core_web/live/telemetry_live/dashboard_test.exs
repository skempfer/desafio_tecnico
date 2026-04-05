defmodule WCoreWeb.TelemetryLive.DashboardTest do
  @moduledoc """
  Integration tests for the telemetry Control Room LiveView.

  Verifies access control for unauthenticated users and baseline rendering for
  authenticated users.
  """

  use WCoreWeb.ConnCase

  import Phoenix.LiveViewTest
  import WCore.AccountsFixtures

  alias WCore.Accounts.Scope
  alias WCore.Telemetry
  alias WCore.Telemetry.Ingester

  test "redirects unauthenticated user", %{conn: conn} do
    assert {:error, {:redirect, %{to: path, flash: flash}}} = live(conn, ~p"/control-room")
    assert path == ~p"/users/log-in"
    assert %{"error" => "You must log in to access this page."} = flash
  end

  test "render control room for authenticated user", %{conn: conn} do
    {:ok, _lv, html} =
      conn
      |> log_in_user(user_fixture())
      |> live(~p"/control-room")

    assert html =~ "Control Room"
    assert html =~ "Real-time machine heartbeat overview"
    assert html =~ "Machine"
  end

  test "updates node status and counter after ingest event", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)

    assert {:ok, _node} =
             Telemetry.create_node(scope, %{machine_identifier: "sensor-live", location: "lab"})

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/control-room")

    timestamp = ~U[2024-06-05 12:00:00Z]
    assert {:ok, 1} = Ingester.ingest_event("sensor-live", "degraded", %{temp: 31}, timestamp)

    Process.sleep(80)

    html = render(lv)
    assert html =~ "DEGRADED"
    assert html =~ "tabular-nums\">1</td>"
  end

  test "paginates nodes with 20 rows per page", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)

    Enum.each(1..25, fn i ->
      machine_identifier = "sensor-#{String.pad_leading(Integer.to_string(i), 2, "0")}"
      Telemetry.create_node(scope, %{machine_identifier: machine_identifier, location: "lab"})
    end)

    {:ok, lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/control-room")

    assert html =~ "1 / 2"
    assert html =~ "Showing 20 of 25 machines"
    assert html =~ "sensor-01"
    refute html =~ "sensor-21"

    html =
      lv
      |> element("button[aria-label='Go to next page']")
      |> render_click()

    assert html =~ "2 / 2"
    assert html =~ "Showing 5 of 25 machines"
    assert html =~ "sensor-21"
    refute html =~ "sensor-01"
  end

  test "filters by machine and location and resets to first page", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)

    Enum.each(1..25, fn i ->
      machine_identifier = "sensor-#{String.pad_leading(Integer.to_string(i), 2, "0")}"
      location = if i == 21, do: "South Bay", else: "lab"
      Telemetry.create_node(scope, %{machine_identifier: machine_identifier, location: location})
    end)

    {:ok, lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/control-room")

    assert html =~ "1 / 2"

    html =
      lv
      |> element("button[aria-label='Go to next page']")
      |> render_click()

    assert html =~ "2 / 2"
    assert html =~ "sensor-21"

    html =
      lv
      |> form("#dashboard-search", search: %{query: "sensor-01"})
      |> render_change()

    assert html =~ "1 / 1"
    assert html =~ "Showing 1 of 1 machines"
    assert html =~ "sensor-01"
    refute html =~ "sensor-21"

    html =
      lv
      |> form("#dashboard-search", search: %{query: "south"})
      |> render_change()

    assert html =~ "1 / 1"
    assert html =~ "Showing 1 of 1 machines"
    assert html =~ "South Bay"
    assert html =~ "sensor-21"
  end

  test "status cards filter rows and total card restores full list", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)

    Telemetry.create_node(scope, %{machine_identifier: "reactor-online", location: "A"})
    Telemetry.create_node(scope, %{machine_identifier: "reactor-offline", location: "B"})
    Telemetry.create_node(scope, %{machine_identifier: "reactor-unknown", location: "C"})

    ts = ~U[2026-04-04 16:00:00Z]
    Ingester.ingest_event("reactor-online", "online", %{}, ts)
    Ingester.ingest_event("reactor-offline", "offline", %{}, ts)

    Process.sleep(80)

    {:ok, lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/control-room")

    assert html =~ "Showing 3 of 3 machines"

    html =
      lv
      |> element("button[phx-value-status='offline']")
      |> render_click()

    assert html =~ "Showing 1 of 1 machines"
    assert html =~ "reactor-offline"
    refute html =~ "reactor-online"

    html =
      lv
      |> element("button[phx-value-status='unknown']")
      |> render_click()

    assert html =~ "Showing 1 of 1 machines"
    assert html =~ "reactor-unknown"
    refute html =~ "reactor-online"
    refute html =~ "reactor-offline"

    html =
      lv
      |> element("button[phx-value-status='all']")
      |> render_click()

    assert html =~ "Showing 3 of 3 machines"
    assert html =~ "reactor-online"
    assert html =~ "reactor-offline"
    assert html =~ "reactor-unknown"
  end

  test "sorts by events and toggles direction from table header", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)
    ts = ~U[2026-04-04 17:00:00Z]

    Telemetry.create_node(scope, %{machine_identifier: "node-a", location: "A"})
    Telemetry.create_node(scope, %{machine_identifier: "node-b", location: "B"})

    Ingester.ingest_event("node-a", "online", %{}, ts)
    Ingester.ingest_event("node-b", "online", %{}, ts)
    Ingester.ingest_event("node-b", "online", %{}, ts)

    Process.sleep(80)

    {:ok, lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/control-room")

    refute html =~ "Events ↑"
    refute html =~ "Events ↓"

    html =
      lv
      |> element("button[phx-value-by='events']")
      |> render_click()

    assert html =~ "Events ↑"

    html =
      lv
      |> element("button[phx-value-by='events']")
      |> render_click()

    assert html =~ "Events ↓"
  end

  test "syncs pagination, filter and search with URL params", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)

    Enum.each(1..25, fn i ->
      machine_identifier = "sensor-#{String.pad_leading(Integer.to_string(i), 2, "0")}"
      Telemetry.create_node(scope, %{machine_identifier: machine_identifier, location: "lab"})
    end)

    ts = ~U[2026-04-05 10:00:00Z]
    Ingester.ingest_event("sensor-21", "offline", %{}, ts)
    Process.sleep(80)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/control-room")

    lv
    |> element("button[aria-label='Go to next page']")
    |> render_click()

    assert_patch(lv, ~p"/control-room?page=2")

    lv
    |> element("button[phx-value-status='offline']")
    |> render_click()

    assert_patch(lv, ~p"/control-room?page=1&status=offline")

    lv
    |> form("#dashboard-search", search: %{query: "sensor-21"})
    |> render_change()

    assert_patch(lv, ~p"/control-room?page=1&q=sensor-21&status=offline")
  end

  test "loads dashboard state from URL params", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)

    Telemetry.create_node(scope, %{machine_identifier: "node-a", location: "A"})
    Telemetry.create_node(scope, %{machine_identifier: "node-b", location: "B"})

    ts = ~U[2026-04-05 11:00:00Z]
    Ingester.ingest_event("node-b", "offline", %{}, ts)
    Process.sleep(80)

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/control-room?status=offline&q=node-b&sort_by=events&sort_dir=desc")

    assert html =~ "Showing 1 of 1 machines"
    assert html =~ "node-b"
    refute html =~ "node-a"
    assert html =~ "Events ↓"
  end

  test "exposes accessibility state for selected filter and sorted column", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)
    ts = ~U[2026-04-05 12:00:00Z]

    Telemetry.create_node(scope, %{machine_identifier: "node-a", location: "A"})
    Telemetry.create_node(scope, %{machine_identifier: "node-b", location: "B"})
    Ingester.ingest_event("node-b", "offline", %{}, ts)

    Process.sleep(80)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/control-room")

    assert has_element?(lv, "button[phx-value-status='all'][aria-pressed='true']")
    assert has_element?(lv, "th[aria-sort='ascending'] button[phx-value-by='machine']")

    lv
    |> element("button[phx-value-status='offline']")
    |> render_click()

    assert has_element?(lv, "button[phx-value-status='offline'][aria-pressed='true']")
    assert has_element?(lv, "button[phx-value-status='all'][aria-pressed='false']")

    lv
    |> element("button[phx-value-by='events']")
    |> render_click()

    assert has_element?(lv, "th[aria-sort='ascending'] button[phx-value-by='events']")

    lv
    |> element("button[phx-value-by='events']")
    |> render_click()

    assert has_element?(lv, "th[aria-sort='descending'] button[phx-value-by='events']")
  end
end
