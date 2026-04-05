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
  @nodes_per_page 20

  @impl true
  @doc """
  Initializes dashboard assigns for the current user scope.

  Loads nodes visible to the authenticated user with their current hot
  telemetry state. When the LiveView is connected, it also subscribes to
  lightweight dashboard invalidation events and initializes coalescing state
  used to batch row refreshes.
  """

  def mount(params, _session, socket) do
    if connected?(socket), do: Telemetry.subscribe_dashboard_updates()

    page = parse_page(Map.get(params, "page"))

    socket =
      socket
      |> assign(:page_title, "Control Room")
      |> assign(:rows, [])
      |> assign(:pending_node_ids, MapSet.new())
      |> assign(:refresh_timer_ref, nil)
      |> assign(:page, 1)
      |> assign(:per_page, @nodes_per_page)
      |> assign(:total_entries, 0)
      |> assign(:total_pages, 1)
      |> assign(:has_prev, false)
      |> assign(:has_next, false)
      |> assign(:visible_node_ids, MapSet.new())
      |> load_page(page)

    {:ok,
     socket}
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
          <p class="mt-2 text-2xl font-semibold text-zinc-900 dark:text-zinc-100">{@total_entries}</p>
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

      <div class="mt-5 flex justify-center">
        <div class="inline-flex items-center rounded-full border border-zinc-200 bg-white p-1 shadow-sm dark:border-zinc-700 dark:bg-zinc-900">
          <button
            type="button"
            phx-click="prev_page"
            disabled={!@has_prev}
            aria-label="Go to previous page"
            class="inline-flex size-9 items-center justify-center rounded-full text-zinc-700 transition enabled:hover:bg-zinc-100 enabled:hover:text-zinc-900 disabled:cursor-not-allowed disabled:text-zinc-400 dark:text-zinc-300 dark:enabled:hover:bg-zinc-800 dark:enabled:hover:text-white dark:disabled:text-zinc-600"
          >
            <.icon name="hero-chevron-left" class="size-4" />
          </button>

          <div class="min-w-20 px-2 text-center text-xs font-semibold uppercase tracking-wide text-zinc-500 dark:text-zinc-400">
            {@page} / {@total_pages}
          </div>

          <button
            type="button"
            phx-click="next_page"
            disabled={!@has_next}
            aria-label="Go to next page"
            class="inline-flex size-9 items-center justify-center rounded-full text-zinc-700 transition enabled:hover:bg-zinc-100 enabled:hover:text-zinc-900 disabled:cursor-not-allowed disabled:text-zinc-400 dark:text-zinc-300 dark:enabled:hover:bg-zinc-800 dark:enabled:hover:text-white dark:disabled:text-zinc-600"
          >
            <.icon name="hero-chevron-right" class="size-4" />
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    {:noreply, load_page(socket, socket.assigns.page - 1)}
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    {:noreply, load_page(socket, socket.assigns.page + 1)}
  end

  @impl true
  def handle_info({:node_changed, machine_identifier, _event_count, _timestamp}, socket) do
    if MapSet.member?(socket.assigns.visible_node_ids, machine_identifier) do
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
    else
      {:noreply, socket}
    end
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

  defp parse_page(nil), do: 1

  defp parse_page(page_param) when is_binary(page_param) do
    case Integer.parse(page_param) do
      {value, ""} when value > 0 -> value
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  defp load_page(socket, requested_page) do
    scope = socket.assigns.current_scope

    page_data =
      Telemetry.list_nodes_with_hot_state_paginated(
        scope,
        page: requested_page,
        per_page: @nodes_per_page
      )

    if socket.assigns.refresh_timer_ref do
      Process.cancel_timer(socket.assigns.refresh_timer_ref)
    end

    visible_node_ids =
      page_data.entries
      |> Enum.map(& &1.machine_identifier)
      |> MapSet.new()

    socket
    |> assign(:rows, page_data.entries)
    |> assign(:page, page_data.page)
    |> assign(:per_page, page_data.per_page)
    |> assign(:total_entries, page_data.total_entries)
    |> assign(:total_pages, page_data.total_pages)
    |> assign(:has_prev, page_data.has_prev)
    |> assign(:has_next, page_data.has_next)
    |> assign(:visible_node_ids, visible_node_ids)
    |> assign(:pending_node_ids, MapSet.new())
    |> assign(:refresh_timer_ref, nil)
  end

  defp count_by_status(rows, status) do
    Enum.count(rows, &(&1.status == status))
  end
end
