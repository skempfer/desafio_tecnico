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
  @auto_refresh_seconds 10
  @countdown_tick_ms 1_000
  @countdown_circumference 100.53
  @query_param_keys ~w(page q status sort_by sort_dir)

  @impl true
  @doc """
  Initializes dashboard assigns for the current user scope.

  Loads nodes visible to the authenticated user with their current hot
  telemetry state. When the LiveView is connected, it also subscribes to
  lightweight dashboard invalidation events and initializes coalescing state
  used to batch row refreshes.
  """

  def mount(params, _session, socket) do
    if connected?(socket) do
      Telemetry.subscribe_dashboard_updates()
      schedule_auto_refresh()
      schedule_countdown_tick()
    end

    page = parse_page(Map.get(params, "page"))
    search_query = parse_search_query(Map.get(params, "q"))

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
      |> assign(:search_query, search_query)
      |> assign(:status_filter, "all")
      |> assign(:status_counts, %{all: 0, online: 0, degraded: 0, offline: 0, unknown: 0})
      |> assign(:sort_by, "machine")
      |> assign(:sort_dir, "asc")
      |> assign(:countdown_circumference, @countdown_circumference)
      |> assign(:seconds_until_refresh, @auto_refresh_seconds)
      |> load_page(page)

    {:ok,
     socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = parse_page(Map.get(params, "page"))
    search_query = parse_search_query(Map.get(params, "q"))
    status_filter = normalize_status_filter(Map.get(params, "status"))
    sort_by = normalize_sort_by(Map.get(params, "sort_by"))
    sort_dir = normalize_sort_dir(Map.get(params, "sort_dir"))

    socket =
      if page == socket.assigns.page and
           search_query == socket.assigns.search_query and
           status_filter == socket.assigns.status_filter and
           sort_by == socket.assigns.sort_by and
           sort_dir == socket.assigns.sort_dir do
        socket
      else
        socket
        |> assign(:search_query, search_query)
        |> assign(:status_filter, status_filter)
        |> assign(:sort_by, sort_by)
        |> assign(:sort_dir, sort_dir)
        |> load_page(page)
      end

    incoming_query_params =
      params
      |> Map.take(@query_param_keys)
      |> normalize_query_params()

    canonical_query_params =
      socket
      |> current_query_params()
      |> normalize_query_params()

    if incoming_query_params == canonical_query_params do
      {:noreply, socket}
    else
      {:noreply, push_patch(socket, to: ~p"/control-room?#{canonical_query_params}", replace: true)}
    end
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
        <:actions>
          <div class="flex flex-wrap items-center justify-end gap-3">
            <div
              id="dashboard-connection-status"
              phx-hook="ConnectionStatus"
              data-state="disconnected"
              class="group inline-flex min-w-28 flex-col items-end rounded-xl border border-zinc-200 bg-white px-3 py-2 shadow-sm dark:border-zinc-800 dark:bg-zinc-900"
            >
              <div class="text-xs leading-5 text-right">
                <p class="font-semibold uppercase tracking-wide text-zinc-600 dark:text-zinc-300">Connection</p>
                <p data-role="connection-label" role="status" aria-live="polite" class="inline-flex items-center justify-end gap-2 font-medium text-zinc-800 dark:text-zinc-100">
                  <span
                    class="size-2.5 rounded-full bg-emerald-500 shadow-[0_0_0_4px_rgba(16,185,129,0.15)] transition-colors duration-300 group-data-[state=disconnected]:bg-amber-500 group-data-[state=disconnected]:shadow-[0_0_0_4px_rgba(245,158,11,0.18)]"
                  />
                  Live
                </p>
              </div>
            </div>

            <div class="inline-flex items-center gap-3 rounded-xl border border-zinc-200 bg-white px-3 py-2 shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
              <div class="text-xs leading-5">
                <p class="font-semibold uppercase tracking-wide text-zinc-600 dark:text-zinc-300">Next update in</p>
              </div>

              <div class="relative size-10">
                <svg viewBox="0 0 40 40" class="size-10 -rotate-90" role="img" aria-label="Auto refresh countdown">
                  <circle cx="20" cy="20" r="16" class="fill-none stroke-zinc-200 dark:stroke-zinc-700" stroke-width="4" />
                  <circle
                    cx="20"
                    cy="20"
                    r="16"
                    class="fill-none stroke-indigo-500 transition-all duration-700 ease-linear"
                    stroke-width="4"
                    stroke-linecap="round"
                    stroke-dasharray={@countdown_circumference}
                    stroke-dashoffset={countdown_offset(@seconds_until_refresh)}
                  />
                </svg>
                <div id="dashboard-refresh-seconds" class="absolute inset-0 flex items-center justify-center text-[11px] font-semibold text-zinc-700 dark:text-zinc-200">
                  {@seconds_until_refresh}
                </div>
              </div>
            </div>
          </div>
        </:actions>
      </.header>

      <section class="mb-5">
        <form id="dashboard-search" phx-change="search" phx-submit="search" class="flex items-center gap-2">
          <label for="dashboard-search-query" class="sr-only">Search machines</label>
          <div class="relative w-full">
            <.icon
              name="hero-magnifying-glass"
              class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-zinc-400 dark:text-zinc-500"
            />
            <input
              id="dashboard-search-query"
              type="text"
              name="search[query]"
              value={@search_query}
              phx-debounce="300"
              placeholder="Search by machine or location"
              autocomplete="off"
              class="w-full rounded-lg border border-zinc-300 bg-white py-2 pl-10 pr-3 text-sm text-zinc-900 placeholder:text-zinc-400 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-100 dark:placeholder:text-zinc-500"
            />
          </div>
          <button
            :if={@search_query != ""}
            type="button"
            phx-click="clear_search"
            class="rounded-lg border border-rose-300 bg-rose-50 px-3 py-2 text-sm font-medium text-rose-700 hover:bg-rose-100 dark:border-rose-800/70 dark:bg-rose-900/30 dark:text-rose-300 dark:hover:bg-rose-900/40"
          >
            Clear
          </button>
        </form>
      </section>

      <section class="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
        <button
          type="button"
          phx-click="set_status_filter"
          phx-value-status="all"
          aria-pressed={@status_filter == "all"}
          class={summary_card_class(@status_filter == "all", "zinc")}
        >
          <p class="text-xs font-medium uppercase tracking-wide text-zinc-500 dark:text-zinc-400">Total Nodes</p>
          <p class="mt-2 text-2xl font-semibold text-zinc-900 dark:text-zinc-100">{@status_counts.all}</p>
        </button>
        <button
          type="button"
          phx-click="set_status_filter"
          phx-value-status="online"
          aria-pressed={@status_filter == "online"}
          class={summary_card_class(@status_filter == "online", "emerald")}
        >
          <p class="text-xs font-medium uppercase tracking-wide text-emerald-700 dark:text-emerald-300">Online</p>
          <p class="mt-2 text-2xl font-semibold text-emerald-900 dark:text-emerald-200">{@status_counts.online}</p>
        </button>
        <button
          type="button"
          phx-click="set_status_filter"
          phx-value-status="degraded"
          aria-pressed={@status_filter == "degraded"}
          class={summary_card_class(@status_filter == "degraded", "amber")}
        >
          <p class="text-xs font-medium uppercase tracking-wide text-amber-700 dark:text-amber-300">Degraded</p>
          <p class="mt-2 text-2xl font-semibold text-amber-900 dark:text-amber-200">{@status_counts.degraded}</p>
        </button>
        <button
          type="button"
          phx-click="set_status_filter"
          phx-value-status="offline"
          aria-pressed={@status_filter == "offline"}
          class={summary_card_class(@status_filter == "offline", "rose")}
        >
          <p class="text-xs font-medium uppercase tracking-wide text-rose-700 dark:text-rose-300">Offline</p>
          <p class="mt-2 text-2xl font-semibold text-rose-900 dark:text-rose-200">{@status_counts.offline}</p>
        </button>
        <button
          type="button"
          phx-click="set_status_filter"
          phx-value-status="unknown"
          aria-pressed={@status_filter == "unknown"}
          class={summary_card_class(@status_filter == "unknown", "indigo")}
        >
          <p class="text-xs font-medium uppercase tracking-wide text-indigo-700 dark:text-indigo-300">Others</p>
          <p class="mt-2 text-2xl font-semibold text-indigo-900 dark:text-indigo-200">{@status_counts.unknown}</p>
        </button>
      </section>

      <div
        id="dashboard-results"
        phx-hook="DashboardLoading"
        data-loading="false"
        class="group relative overflow-x-auto rounded-xl border border-zinc-200 bg-white shadow-sm dark:border-zinc-800 dark:bg-zinc-900"
      >
        <table class="w-full border-collapse text-left text-sm transition-opacity duration-150 group-data-[loading=true]:opacity-55">
          <thead class="border-b border-zinc-200 text-zinc-600 dark:border-zinc-700 dark:text-zinc-300">
            <tr>
              <th aria-sort={aria_sort("machine", @sort_by, @sort_dir)} class="px-5 py-3.5 font-semibold"><.sort_button by="machine" current_by={@sort_by} current_dir={@sort_dir}>Machine</.sort_button></th>
              <th aria-sort={aria_sort("location", @sort_by, @sort_dir)} class="px-5 py-3.5 font-semibold"><.sort_button by="location" current_by={@sort_by} current_dir={@sort_dir}>Location</.sort_button></th>
              <th aria-sort={aria_sort("status", @sort_by, @sort_dir)} class="px-5 py-3.5 font-semibold"><.sort_button by="status" current_by={@sort_by} current_dir={@sort_dir}>Status</.sort_button></th>
              <th aria-sort={aria_sort("events", @sort_by, @sort_dir)} class="px-5 py-3.5 font-semibold"><.sort_button by="events" current_by={@sort_by} current_dir={@sort_dir}>Events</.sort_button></th>
              <th aria-sort={aria_sort("last_seen", @sort_by, @sort_dir)} class="px-5 py-3.5 font-semibold"><.sort_button by="last_seen" current_by={@sort_by} current_dir={@sort_dir}>Last Seen</.sort_button></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-zinc-200 text-zinc-800 dark:divide-zinc-800 dark:text-zinc-200">
            <tr :if={Enum.empty?(@rows)}>
              <td colspan="5" class="px-5 py-10 text-center text-zinc-500 dark:text-zinc-400">
                <p>{empty_state_text(@search_query, @status_filter)}</p>
                <button
                  :if={has_active_filters?(@search_query, @status_filter)}
                  type="button"
                  phx-click="reset_filters"
                  class="mt-3 inline-flex items-center rounded-lg border border-indigo-300 bg-indigo-50 px-3 py-1.5 text-xs font-semibold uppercase tracking-wide text-indigo-700 transition hover:bg-indigo-100 dark:border-indigo-700/60 dark:bg-indigo-900/30 dark:text-indigo-300 dark:hover:bg-indigo-900/40"
                >
                  Reset filters
                </button>
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

        <div class="pointer-events-none absolute inset-0 z-10 flex items-center justify-center rounded-xl bg-white/60 opacity-0 transition-opacity duration-150 group-data-[loading=true]:opacity-100 dark:bg-zinc-900/60">
          <div class="inline-flex items-center gap-2 rounded-full border border-zinc-200 bg-white px-3 py-1.5 text-xs font-semibold uppercase tracking-wide text-zinc-700 shadow-sm dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-200">
            <span class="size-2 rounded-full bg-indigo-500 animate-pulse" />
            Updating
          </div>
        </div>
      </div>

      <div class="mt-5 grid items-center gap-3 sm:grid-cols-3">
        <div class="hidden sm:block" />

        <div class="flex justify-center">
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

        <p class="text-center text-sm font-medium text-zinc-500 sm:text-right dark:text-zinc-400">
          Showing {length(@rows)} of {@total_entries} machines
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    target_page = max(1, socket.assigns.page - 1)

    {:noreply, patch_to(socket, %{"page" => Integer.to_string(target_page)})}
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    target_page = socket.assigns.page + 1

    {:noreply, patch_to(socket, %{"page" => Integer.to_string(target_page)})}
  end

  @impl true
  def handle_event("set_status_filter", %{"status" => status}, socket) do
    normalized_status = normalize_status_filter(status)

    {:noreply,
     patch_to(socket, %{
       "status" => normalized_status,
       "page" => "1"
     })}
  end

  @impl true
  def handle_event("sort", %{"by" => by}, socket) do
    by = normalize_sort_by(by)

    {sort_by, sort_dir} =
      if socket.assigns.sort_by == by do
        {by, toggle_sort_dir(socket.assigns.sort_dir)}
      else
        {by, "asc"}
      end

    {:noreply,
     patch_to(socket, %{
       "sort_by" => sort_by,
       "sort_dir" => sort_dir,
       "page" => "1"
     })}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    query = parse_search_query(query)

    if query == socket.assigns.search_query do
      {:noreply, socket}
    else
      {:noreply, patch_to(socket, %{"q" => query, "page" => "1"})}
    end
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    {:noreply, patch_to(socket, %{"q" => "", "page" => "1"})}
  end

  @impl true
  def handle_event("reset_filters", _params, socket) do
    {:noreply,
     patch_to(socket, %{
       "q" => "",
       "status" => "all",
       "page" => "1"
     })}
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
     |> assign(:refresh_timer_ref, nil)
     |> mark_refreshed()}
  end

  @impl true
  def handle_info(:auto_refresh_page, socket) do
    schedule_auto_refresh()
    {:noreply, load_page(socket, socket.assigns.page)}
  end

  @impl true
  def handle_info(:countdown_tick, socket) do
    schedule_countdown_tick()

    seconds_until_refresh =
      socket.assigns.seconds_until_refresh
      |> Kernel.-(1)
      |> max(0)

    {:noreply,
     socket
     |> assign(:seconds_until_refresh, seconds_until_refresh)}
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

  defp parse_search_query(nil), do: ""

  defp parse_search_query(query) when is_binary(query) do
    query
    |> String.trim()
  end

  defp parse_search_query(_), do: ""

  defp normalize_status_filter(status) when is_binary(status) do
    case String.downcase(String.trim(status)) do
      "online" -> "online"
      "degraded" -> "degraded"
      "offline" -> "offline"
      "unknown" -> "unknown"
      "other" -> "unknown"
      "others" -> "unknown"
      _ -> "all"
    end
  end

  defp normalize_status_filter(_status), do: "all"

  defp normalize_sort_by(by) when is_binary(by) do
    case String.downcase(String.trim(by)) do
      "machine" -> "machine"
      "location" -> "location"
      "status" -> "status"
      "events" -> "events"
      "last_seen" -> "last_seen"
      _ -> "machine"
    end
  end

  defp normalize_sort_by(_by), do: "machine"

  defp normalize_sort_dir(dir) when is_binary(dir) do
    case String.downcase(String.trim(dir)) do
      "desc" -> "desc"
      _ -> "asc"
    end
  end

  defp normalize_sort_dir(_dir), do: "asc"

  defp toggle_sort_dir("asc"), do: "desc"
  defp toggle_sort_dir(_), do: "asc"

  defp patch_to(socket, overrides) do
    params =
      socket
      |> current_query_params()
      |> Map.merge(overrides)
      |> normalize_query_params()

    push_patch(socket, to: ~p"/control-room?#{params}")
  end

  defp current_query_params(socket) do
    %{
      "page" => Integer.to_string(socket.assigns.page),
      "q" => socket.assigns.search_query,
      "status" => socket.assigns.status_filter,
      "sort_by" => socket.assigns.sort_by,
      "sort_dir" => socket.assigns.sort_dir
    }
  end

  defp normalize_query_params(params) do
    params
    |> Enum.reduce(%{}, fn
      {"page", "1"}, acc -> acc
      {"q", ""}, acc -> acc
      {"status", "all"}, acc -> acc
      {"sort_by", "machine"}, acc -> acc
      {"sort_dir", "asc"}, acc -> acc
      {key, value}, acc when is_binary(value) -> Map.put(acc, key, value)
      {_key, _value}, acc -> acc
    end)
  end

  defp load_page(socket, requested_page) do
    scope = socket.assigns.current_scope

    page_data =
      Telemetry.list_nodes_with_hot_state_paginated(
        scope,
        page: requested_page,
        per_page: @nodes_per_page,
        search: socket.assigns.search_query,
        status: socket.assigns.status_filter,
        sort_by: socket.assigns.sort_by,
        sort_dir: socket.assigns.sort_dir
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
    |> assign(:status_counts, page_data.status_counts)
    |> assign(:visible_node_ids, visible_node_ids)
    |> assign(:pending_node_ids, MapSet.new())
    |> assign(:refresh_timer_ref, nil)
    |> mark_refreshed()
  end

  defp summary_card_class(true, color) do
    base =
      "rounded-xl border p-4 text-left shadow-sm transition duration-200 ease-out hover:-translate-y-0.5 hover:shadow-lg hover:ring-2 hover:ring-indigo-400/40 hover:brightness-110 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500/40"

    case color do
      "zinc" ->
        "#{base} border-zinc-300 bg-zinc-100 dark:border-zinc-700 dark:bg-zinc-800"

      "emerald" ->
        "#{base} border-emerald-300 bg-emerald-100 dark:border-emerald-700/60 dark:bg-emerald-900/35"

      "amber" ->
        "#{base} border-amber-300 bg-amber-100 dark:border-amber-700/60 dark:bg-amber-900/35"

      "rose" ->
        "#{base} border-rose-300 bg-rose-100 dark:border-rose-700/60 dark:bg-rose-900/35"

      _ ->
        "#{base} border-indigo-300 bg-indigo-100 dark:border-indigo-700/60 dark:bg-indigo-900/35"
    end
  end

  defp summary_card_class(false, color) do
    base =
      "rounded-xl border p-4 text-left shadow-sm transition duration-200 ease-out hover:-translate-y-0.5 hover:shadow-lg hover:ring-2 hover:ring-indigo-400/30 hover:brightness-110"

    case color do
      "zinc" ->
        "#{base} border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-900"

      "emerald" ->
        "#{base} border-emerald-200/70 bg-emerald-50/70 dark:border-emerald-800/50 dark:bg-emerald-900/20"

      "amber" ->
        "#{base} border-amber-200/70 bg-amber-50/70 dark:border-amber-800/50 dark:bg-amber-900/20"

      "rose" ->
        "#{base} border-rose-200/70 bg-rose-50/70 dark:border-rose-800/50 dark:bg-rose-900/20"

      _ ->
        "#{base} border-indigo-200/70 bg-indigo-50/70 dark:border-indigo-800/50 dark:bg-indigo-900/20"
    end
  end

  defp empty_state_text("", "all"), do: "No telemetry nodes found for this account yet."

  defp empty_state_text("", status_filter) do
    "No #{status_filter} machines match the current filters."
  end

  defp empty_state_text(_query, "all"), do: "No machines match your search."

  defp empty_state_text(_query, status_filter) do
    "No #{status_filter} machines match your search and filters."
  end

  defp has_active_filters?("", "all"), do: false
  defp has_active_filters?(_search_query, _status_filter), do: true

  defp mark_refreshed(socket) do
    socket
    |> assign(:seconds_until_refresh, @auto_refresh_seconds)
  end

  defp countdown_offset(seconds_until_refresh) do
    progress =
      seconds_until_refresh
      |> max(0)
      |> min(@auto_refresh_seconds)
      |> Kernel./(@auto_refresh_seconds)

    Float.round(@countdown_circumference * (1 - progress), 2)
  end

  defp aria_sort(by, current_by, current_dir) do
    cond do
      by != current_by -> "none"
      current_dir == "desc" -> "descending"
      true -> "ascending"
    end
  end

  attr :by, :string, required: true
  attr :current_by, :string, required: true
  attr :current_dir, :string, required: true
  slot :inner_block, required: true

  defp sort_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="sort"
      phx-value-by={@by}
      class="inline-flex items-center gap-1.5 font-semibold text-zinc-600 hover:text-zinc-900 dark:text-zinc-300 dark:hover:text-white"
    >
      {render_slot(@inner_block)}
      <span
        :if={@current_by == @by}
        class="inline-flex size-5 items-center justify-center rounded-full bg-zinc-200 text-[11px] font-bold leading-none text-zinc-800 dark:bg-zinc-700 dark:text-zinc-100"
      >
        {if @current_dir == "asc", do: "↑", else: "↓"}
      </span>
    </button>
    """
  end

  defp schedule_auto_refresh do
    Process.send_after(self(), :auto_refresh_page, @auto_refresh_seconds * @countdown_tick_ms)
  end

  defp schedule_countdown_tick do
    Process.send_after(self(), :countdown_tick, @countdown_tick_ms)
  end
end
