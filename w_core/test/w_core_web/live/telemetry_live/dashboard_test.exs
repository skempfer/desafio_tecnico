defmodule WCoreWeb.TelemetryLive.DashboardTest do
  @moduledoc """
  Integration tests for the telemetry Control Room LiveView.

  Verifies access control for unauthenticated users and baseline rendering for
  authenticated users.
  """

  use WCoreWeb.ConnCase

  import Phoenix.LiveViewTest
  import WCore.AccountsFixtures

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
end
