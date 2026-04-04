defmodule WCoreWeb.TelemetryLive.Dashboard do
  @moduledoc """
  Live dashboard that renders the Control Room telemetry overview.

  On mount, it loads known nodes for the current authenticated scope and builds
  an initial cold-state row model for presentation.
  """

  use WCoreWeb, :live_view

  alias WCore.Telemetry
  alias MapSet

  @refresh_delay_ms 50

  @impl true
  @doc """
  Initializes dashboard assigns for the current user scope.

  Loads nodes visible to the authenticated user with their current hot
  telemetry state. When the LiveView is connected, it also subscribes to
  lightweight dashboard invalidation events and initializes coalescing state
  used to batch row refreshes.
  """

  def mount(_params, _session, socket) do
    if connected?(socket), do: Telemetry.subscribe_dashboard_updates()

    scope = socket.assigns.current_scope
    rows = Telemetry.list_nodes_with_hot_state(scope)

    {:ok,
      socket
      |> assign(:page_title, "Control Room")
      |> assign(:rows, rows)
      |> assign(:pending_node_ids, MapSet.new())
      |> assign(:refresh_timer_ref, nil)
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
              <td><.status_badge status={row.status} /></td>
              <td>{row.total_events_processed}</td>
              <td>{format_ts(row.last_seen_at)}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info({:node_changed, machine_identifier, _event_count, _timestamp}, socket) do
    pending_node_ids = MapSet.put(socket.assigns.pending_node_ids, machine_identifier)

    socket =
      if socket.assigns.refresh_timer_ref do
        assign(socket, :pending_node_ids, pending_node_ids)
      else
        timer_ref = Process.send_after(self(), :refresh_pending_nodes, @refresh_delay_ms)

        socket
        |> assign(:pending_node_ids, pending_node_ids)
        |> assign(:refresh_timer_ref, timer_ref)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh_pending_nodes, socket) do
    scope = socket.assigns.current_scope

    refreshed_rows_by_machine_id =
      socket.assigns.pending_node_ids
      |> Enum.reduce(%{}, fn machine_identifier, acc ->
        case Telemetry.get_node_with_hot_state(scope, machine_identifier) do
          nil -> acc
          row -> Map.put(acc, machine_identifier, row)
        end
      end)

    rows =
      Enum.map(socket.assigns.rows, fn row ->
        Map.get(refreshed_rows_by_machine_id, row.machine_identifier, row)
      end)

    {:noreply,
     socket
     |> assign(:rows, rows)
     |> assign(:pending_node_ids, MapSet.new())
     |> assign(:refresh_timer_ref, nil)}
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
