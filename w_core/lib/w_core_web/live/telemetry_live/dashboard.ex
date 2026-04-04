defmodule WCoreWeb.TelemetryLive.Dashboard do
  @moduledoc """
  Live dashboard that renders the Control Room telemetry overview.

  On mount, it loads known nodes for the current authenticated scope and builds
  an initial cold-state row model for presentation.
  """

  use WCoreWeb, :live_view

  alias WCore.Telemetry

  @impl true
  @doc """
  Initializes dashboard assigns for the current user scope.

  Loads nodes visible to the authenticated user and maps each node into a
  default row shape used by the dashboard table.
  """

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    rows = Telemetry.list_nodes(scope) |> Enum.map(&to_cold_row/1)

    {:ok,
      socket
      |> assign(:page_title, "Control Room")
      |> assign(:rows, rows)
    }
  end

  @impl true
  @doc """
  Renders the Control Room table with machine status information.
  """
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Control Room
        <:subtitle>Real-time machine heartbeat overview</:subtitle>
      </.header>

      <div class="overflow-x-auto">
        <table class="table w-full">
          <thead>
            <tr>
              <th>Machine</th>
              <th>Location</th>
              <th>Status</th>
              <th>Events</th>
              <th>Last Seen</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows} id={"node-#{row.machine_identifier}"}>
              <td>{row.machine_identifier}</td>
              <td>{row.location}</td>
              <td>{row.status}</td>
              <td>{row.total_events_processed}</td>
              <td>{format_ts(row.last_seen_at)}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end

  @doc """
  Builds a cold-state row from a node record.

  The returned map represents a node before any live telemetry updates are
  received by the interface.
  """
  def to_cold_row(node) do
    %{
      machine_identifier: node.machine_identifier,
      location: node.location,
      status: "unknown",
      total_events_processed: 0,
      last_seen_at: nil
    }
  end

  defp format_ts(nil), do: "-"
  defp format_ts(ts), do: Calendar.strftime(ts, "%Y-%m-%d %H:%M:%S")
end
