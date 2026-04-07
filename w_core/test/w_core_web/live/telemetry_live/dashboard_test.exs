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
    assert has_element?(lv, "#node-sensor-live td:nth-child(4)", "1")
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

    html =
      lv
      |> element("button[aria-label='Go to next page']")
      |> render_click()

    assert html =~ "2 / 2"
    assert html =~ "Showing 5 of 25 machines"
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
    refute html =~ "sensor-01"

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

    assert html =~ "aria-sort=\"ascending\""

    html =
      lv
      |> element("button[phx-value-by='events']")
      |> render_click()

    assert html =~ "aria-sort=\"descending\""
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

    assert_patch(lv, ~p"/control-room?status=offline")

    lv
    |> form("#dashboard-search", search: %{query: "sensor-21"})
    |> render_change()

    assert_patch(lv, ~p"/control-room?q=sensor-21&status=offline")
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
    assert html =~ "aria-sort=\"descending\""
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
    assert has_element?(lv, "th[aria-sort='ascending'] button[phx-value-by='status']")

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

  test "canonicalizes invalid query params to clean URL", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: path}}} =
             conn
             |> log_in_user(user_fixture())
             |> live(~p"/control-room?page=0&q=%20%20&status=invalid&sort_by=invalid&sort_dir=invalid")

    assert path == "/control-room"
  end

  test "canonicalizes out-of-range page to last available page", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)

    Enum.each(1..25, fn i ->
      machine_identifier = "sensor-#{String.pad_leading(Integer.to_string(i), 2, "0")}"
      Telemetry.create_node(scope, %{machine_identifier: machine_identifier, location: "lab"})
    end)

    assert {:error, {:live_redirect, %{to: path}}} =
             conn
             |> log_in_user(user)
             |> live(~p"/control-room?page=999")

    assert path == "/control-room?page=2"
  end

  test "countdown decreases on tick and resets after auto refresh", %{conn: conn} do
    {:ok, lv, _html} =
      conn
      |> log_in_user(user_fixture())
      |> live(~p"/control-room")

    assert has_element?(lv, "#dashboard-refresh-seconds", "10")

    send(lv.pid, :countdown_tick)
    _ = render(lv)

    assert has_element?(lv, "#dashboard-refresh-seconds", "9")

    send(lv.pid, :auto_refresh_page)
    _ = render(lv)

    assert has_element?(lv, "#dashboard-refresh-seconds", "10")
  end

  test "uses configured auto refresh interval from app env", %{conn: conn} do
    previous_value = Application.get_env(:w_core, :dashboard_auto_refresh_seconds)
    Application.put_env(:w_core, :dashboard_auto_refresh_seconds, 3)

    on_exit(fn ->
      if is_nil(previous_value) do
        Application.delete_env(:w_core, :dashboard_auto_refresh_seconds)
      else
        Application.put_env(:w_core, :dashboard_auto_refresh_seconds, previous_value)
      end
    end)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user_fixture())
      |> live(~p"/control-room")

    assert has_element?(lv, "#dashboard-refresh-seconds", "3")

    send(lv.pid, :countdown_tick)
    _ = render(lv)

    assert has_element?(lv, "#dashboard-refresh-seconds", "2")

    send(lv.pid, :auto_refresh_page)
    _ = render(lv)

    assert has_element?(lv, "#dashboard-refresh-seconds", "3")
  end

  test "auto refresh keeps the current page", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)

    Enum.each(1..25, fn i ->
      machine_identifier = "sensor-#{String.pad_leading(Integer.to_string(i), 2, "0")}"
      Telemetry.create_node(scope, %{machine_identifier: machine_identifier, location: "lab"})
    end)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/control-room?page=2")

    assert has_element?(lv, "div", "2 / 2")

    send(lv.pid, :auto_refresh_page)
    _ = render(lv)

    assert has_element?(lv, "div", "2 / 2")
    assert has_element?(lv, "p", "Showing 5 of 25 machines")
    refute has_element?(lv, "td", "sensor-01")
  end

  test "bulk actions bar appears with row selection and clear hides it", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)

    Telemetry.create_node(scope, %{machine_identifier: "node-a", location: "A"})
    Telemetry.create_node(scope, %{machine_identifier: "node-b", location: "B"})

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/control-room")

    refute has_element?(lv, "#bulk-actions-bar[data-visible='true']")

    lv
    |> form("#row-select-node-a", %{"row_id" => "node-a", "selected" => "true"})
    |> render_change()

    assert has_element?(lv, "#bulk-actions-bar[data-visible='true']")
    assert has_element?(lv, "#bulk-actions-bar", "Selected: 1")

    lv
    |> element("button[phx-click='clear_selection']")
    |> render_click()

    refute has_element?(lv, "#bulk-actions-bar[data-visible='true']")
  end

  test "select all shows total filtered count in bulk actions bar", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)

    Enum.each(1..25, fn i ->
      machine_identifier = "sensor-#{String.pad_leading(Integer.to_string(i), 2, "0")}"
      Telemetry.create_node(scope, %{machine_identifier: machine_identifier, location: "lab"})
    end)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/control-room")

    lv
    |> form("#select-all-form", %{"select_all" => "true"})
    |> render_change()

    assert has_element?(lv, "#bulk-actions-bar[data-visible='true']")
    assert has_element?(lv, "#bulk-actions-bar", "Selected: 25")
  end

  test "export button stays available after selecting rows", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)

    Telemetry.create_node(scope, %{machine_identifier: "node-a", location: "A"})
    Telemetry.create_node(scope, %{machine_identifier: "node-b", location: "B"})

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/control-room")

    lv
    |> form("#row-select-node-a", %{"row_id" => "node-a", "selected" => "true"})
    |> render_change()

    html =
      lv
      |> element("button[phx-click='export_csv']")
      |> render_click()

    assert html =~ "Selected: 1"
    assert has_element?(lv, "button[phx-click='clear_selection']")
  end

  test "clicking a machine row expands paginated unresolved error history", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)
    base_ts = ~U[2026-04-05 18:00:00Z]

    Telemetry.create_node(scope, %{machine_identifier: "reactor-01", location: "Bay A"})

    Enum.each(1..12, fn i ->
      assert {:ok, _count} =
               Ingester.ingest_event(
                 "reactor-01",
                 if(rem(i, 2) == 0, do: "offline", else: "degraded"),
                 %{"message" => "Error #{i}"},
                 DateTime.add(base_ts, i, :second)
               )
    end)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/control-room")

    lv
    |> element("#node-reactor-01")
    |> render_click()

    assert has_element?(lv, "#node-errors-reactor-01")
    assert has_element?(lv, "#machine-error-history-panel", "Error history")
    assert has_element?(lv, "#machine-error-history-panel", "Error 12")
    refute has_element?(lv, "#machine-error-history-panel", "Error 2")

    lv
    |> element("button[aria-label='Go to next error page']")
    |> render_click()

    assert has_element?(lv, "#machine-error-history-panel", "Error 2")
    assert has_element?(lv, "#machine-error-history-panel", "Error 1")
    assert has_element?(lv, "#machine-error-history-panel", "Showing 2 of 12 errors")
  end

  test "resolving selected machine errors removes them from the expanded history", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)
    base_ts = ~U[2026-04-05 19:00:00Z]

    Telemetry.create_node(scope, %{machine_identifier: "reactor-02", location: "Bay B"})

    Enum.each(1..2, fn i ->
      assert {:ok, _count} =
               Ingester.ingest_event(
                 "reactor-02",
                 "offline",
                 %{"message" => "Fault #{i}"},
                 DateTime.add(base_ts, i, :second)
               )
    end)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/control-room")

    lv
    |> element("#node-reactor-02")
    |> render_click()

    lv
    |> form("#select-all-errors-form", %{"select_all_errors" => "true"})
    |> render_change()

    html =
      lv
      |> element("button[phx-click='resolve_selected_errors']")
      |> render_click()

    assert html =~ "No unresolved errors recorded for this machine."
    refute html =~ "Fault 1"
    refute html =~ "Fault 2"
  end

  test "keeps selected error checkboxes checked after auto refresh", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)
    base_ts = ~U[2026-04-05 20:00:00Z]

    Telemetry.create_node(scope, %{machine_identifier: "reactor-03", location: "Bay C"})

    Enum.each(1..2, fn i ->
      assert {:ok, _count} =
               Ingester.ingest_event(
                 "reactor-03",
                 "offline",
                 %{"message" => "Auto #{i}"},
                 DateTime.add(base_ts, i, :second)
               )
    end)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/control-room")

    lv
    |> element("#node-reactor-03")
    |> render_click()

    [first_error | _rest] =
      Telemetry.list_machine_error_events(scope, "reactor-03", page: 1, per_page: 10).entries

    lv
    |> form("#error-select-#{first_error.id}", %{"error_id" => "#{first_error.id}", "selected" => "true"})
    |> render_change()

    send(lv.pid, :auto_refresh_page)
    _ = render(lv)

    assert has_element?(lv, "#error-select-#{first_error.id} input[type='checkbox'][checked]")
  end

  test "shows contextual empty state and allows resetting filters", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)

    Telemetry.create_node(scope, %{machine_identifier: "node-a", location: "A"})

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/control-room")

    html =
      lv
      |> element("button[phx-value-status='offline']")
      |> render_click()

    assert html =~ "No offline machines match the current filters."
    assert has_element?(lv, "button[phx-click='reset_filters']")

    html =
      lv
      |> element("button[phx-click='reset_filters']")
      |> render_click()

    assert html =~ "Showing 1 of 1 machines"
    assert html =~ "node-a"
  end
end
