defmodule WCore.Telemetry.Ingester do
  @moduledoc """
  GenServer responsible for ingesting telemetry events and broadcasting updates.

  Incoming events are stored in `WCore.Telemetry.Cache`, which keeps the latest
  value per node and an update counter. After persistence, the ingester
  publishes a `:metric_update` message to PubSub so subscribers can react in
  real time.
  """

  use GenServer

  alias WCore.Telemetry
  alias WCore.Telemetry.Cache

  @type state :: map()
  @type ingest_message ::
          {:ingest, Cache.node_id(), Cache.node_status(), Cache.payload(), Cache.event_timestamp()}
  @type ingest_result :: {:ok, Cache.event_count()} | {:error, term()}

  @doc """
  Persists the raw event and then updates the in-memory cache.

  Returns `{:ok, count}` when persistence and cache update succeed, or
  `{:error, reason}` when persistence fails.
  """
  @spec ingest_event(
          Cache.node_id(),
          Cache.node_status(),
          Cache.payload(),
          Cache.event_timestamp()
        ) ::
          ingest_result()
  def ingest_event(node_id, status, payload, timestamp) do
    GenServer.call(__MODULE__, {:ingest, node_id, status, payload, timestamp})
  end

  @impl true
  @spec handle_call(ingest_message(), GenServer.from(), state()) ::
          {:reply, ingest_result(), state()}
  def handle_call({:ingest, node_id, status, payload, timestamp}, _from, state) do
    case Telemetry.record_telemetry_event(node_id, status, payload, timestamp) do
      {:ok, _event} ->
        event_count = Cache.put(node_id, status, payload, timestamp)
        Telemetry.broadcast_dashboard_node_changed(node_id, event_count, timestamp)

        Phoenix.PubSub.broadcast(
          WCore.PubSub,
          "telemetry: #{node_id}",
          {:metric_update, node_id, status, event_count, payload, timestamp}
        )

        {:reply, {:ok, event_count}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @doc """
  Starts the ingester process.

  The process is registered under the module name.
  """
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  @spec init(state()) :: {:ok, state()}
  def init(state) do
    Cache.start_link([])
    {:ok, state}
  end
end
