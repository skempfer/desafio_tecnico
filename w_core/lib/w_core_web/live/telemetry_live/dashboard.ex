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

      <section class="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <div class="rounded-xl border border-zinc-200 bg-white p-4 shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
          <p class="text-xs font-medium uppercase tracking-wide text-zinc-500 dark:text-zinc-400">Total Nodes</p>
          <p class="mt-2 text-2xl font-semibold text-zinc-900 dark:text-zinc-100">{length(@rows)}</p>
        </div>
        <div class="rounded-xl border border-emerald-200/70 bg-emerald-50/70 p-4 shadow-sm dark:border-emerald-800/50 dark:bg-emerald-900/20">
          <p class="text-xs font-medium uppercase tracking-wide text-emerald-700 dark:text-emerald-300">Online</p>
          <p class="mt-2 text-2xl font-semibold text-emerald-900 dark:text-emerald-200">{count_by_status(@rows, "online")}</p>
        </div>
        <div class="rounded-xl border border-amber-200/70 bg-amber-50/70 p-4 shadow-sm dark:border-amber-800/50 dark:bg-amber-900/20">
          <p class="text-xs font-medium uppercase tracking-wide text-amber-700 dark:text-amber-300">Degraded</p>
          <p class="mt-2 text-2xl font-semibold text-amber-900 dark:text-amber-200">{count_by_status(@rows, "degraded")}</p>
        </div>
        <div class="rounded-xl border border-rose-200/70 bg-rose-50/70 p-4 shadow-sm dark:border-rose-800/50 dark:bg-rose-900/20">
          <p class="text-xs font-medium uppercase tracking-wide text-rose-700 dark:text-rose-300">Offline</p>
          <p class="mt-2 text-2xl font-semibold text-rose-900 dark:text-rose-200">{count_by_status(@rows, "offline")}</p>
        </div>
      </section>

      <div class="overflow-x-auto rounded-xl border border-zinc-200 bg-white shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
        <table class="w-full border-collapse text-left text-sm">
          <thead class="border-b border-zinc-200 text-zinc-600 dark:border-zinc-700 dark:text-zinc-300">
            <tr>
              <th class="px-5 py-3.5 font-semibold">Machine</th>
              <th class="px-5 py-3.5 font-semibold">Location</th>
              <th class="px-5 py-3.5 font-semibold">Status</th>
              <th class="px-5 py-3.5 font-semibold">Events</th>
              <th class="px-5 py-3.5 font-semibold">Last Seen</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-zinc-200 text-zinc-800 dark:divide-zinc-800 dark:text-zinc-200">
            <tr :if={Enum.empty?(@rows)}>
              <td colspan="5" class="px-5 py-10 text-center text-zinc-500 dark:text-zinc-400">
                No telemetry nodes found for this account yet.
              </td>
            </tr>
            <tr
              :for={row <- @rows}
              id={"node-#{row.machine_identifier}"}
              class="transition-colors hover:bg-zinc-50 dark:hover:bg-zinc-800/50"
            >
              <td class="px-5 py-3.5 font-medium">{row.machine_identifier}</td>
              <td class="px-5 py-3.5 text-zinc-600 dark:text-zinc-300">{row.location}</td>
              <td class="px-5 py-3.5"><.status_badge status={row.status} /></td>
              <td class="px-5 py-3.5 tabular-nums">{row.total_events_processed}</td>
              <td class="px-5 py-3.5 tabular-nums text-zinc-600 dark:text-zinc-300">{format_ts(row.last_seen_at)}</td>
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

  defp format_ts(nil), do: "-"
  defp format_ts(ts), do: Calendar.strftime(ts, "%Y-%m-%d %H:%M:%S")

  defp count_by_status(rows, status) do
    Enum.count(rows, &(&1.status == status))
  end
end
