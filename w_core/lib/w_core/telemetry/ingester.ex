defmodule WCore.Telemetry.Ingester do
  @moduledoc """
  GenServer responsible for ingesting telemetry events and broadcasting updates.

  Incoming events are stored in `WCore.Telemetry.Cache`, which keeps the latest
  value per node and an update counter. After persistence, the ingester
  publishes a `:metric_update` message to PubSub so subscribers can react in
  real time.
  """

  use GenServer

  alias WCore.Telemetry.Cache

  @doc """
  Starts the ingester process.

  The process is registered under the module name.
  """
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Enqueues a telemetry event for asynchronous ingestion.

  The event is processed via `handle_cast/2`, stored in cache and then
  broadcast to `"telemetry: \#{node_id}"`.
  """
  @spec ingest_event(term(), term(), term(), term()) :: :ok
  def ingest_event(node_id, status, payload, timestamp) do
    GenServer.cast(__MODULE__, {:ingest, node_id, status, payload, timestamp})
  end

  @impl true
  @spec init(map()) :: {:ok, map()}
  def init(state) do
    Cache.start_link([])
    {:ok, state}
  end

  @impl true
  @spec handle_cast({:ingest, term(), term(), term(), term()}, map()) :: {:noreply, map()}
  def handle_cast({:ingest, node_id, status, payload, timestamp}, state) do
    event_count = Cache.put(node_id, status, payload, timestamp)

    Phoenix.PubSub.broadcast(
      WCore.PubSub,
      "telemetry: #{node_id}",
      {:metric_update, node_id, status, event_count, payload, timestamp}
    )

    {:noreply, state}
  end

end
