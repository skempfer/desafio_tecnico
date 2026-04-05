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
    assert html =~ "<td>1</td>"
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

    assert html =~ "Page 1 of 2"
    assert html =~ "sensor-01"
    refute html =~ "sensor-21"

    html =
      lv
      |> element("button", "Next")
      |> render_click()

    assert html =~ "Page 2 of 2"
    assert html =~ "sensor-21"
    refute html =~ "sensor-01"
  end
end
