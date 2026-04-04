defmodule WCore.Telemetry do
  @moduledoc """
  The Telemetry context.
  """

  import Ecto.Query, warn: false
  alias WCore.Accounts.Scope
  alias WCore.Repo
  alias WCore.Telemetry.Node
  alias WCore.Telemetry.NodeMetrics
  alias WCore.Telemetry.TelemetryEvent
  alias WCore.Telemetry.Cache

  @typedoc "Unique machine identifier used as the cache and routing key for telemetry nodes."
  @type node_id :: String.t()

  @typedoc "Node status label received from telemetry input, such as online/offline/fault."
  @type node_status :: String.t()

  @typedoc "Raw telemetry payload map received from the edge device."
  @type payload :: map()

  @typedoc "Monotonic count of events processed for a node."
  @type event_count :: non_neg_integer()

  @typedoc "Timestamp representing when a telemetry event occurred."
  @type event_timestamp :: DateTime.t()

  @typedoc "Normalized cache tuple used in batch upsert operations."
  @type cache_record :: {node_id(), node_status(), event_count(), payload(), event_timestamp()}

  @typedoc "Composite identifier used to mark persisted events as processed."
  @type processed_key :: {node_id(), event_timestamp()}

  @doc """
  Lists scoped nodes enriched with hot telemetry state from ETS.
  """
  @spec list_nodes_with_hot_state(Scope.t()) :: [map()]
  def list_nodes_with_hot_state(%Scope{} = scope) do
    list_nodes(scope)
    |> Enum.map(&to_hot_row/1)
  end

  @doc """
  Gets one scoped node enriched with hot telemetry state, by machine identifier.
  """
  @spec get_node_with_hot_state(Scope.t(), String.t()) :: map() | nil
  def get_node_with_hot_state(%Scope{} = scope, machine_identifier) do
    case Repo.get_by(Node, user_id: scope.user.id, machine_identifier: machine_identifier) do
      nil -> nil
      node -> to_hot_row(node)
    end
  end

  defp to_hot_row(node) do
    case Cache.get(node.machine_identifier) do
      {status, count, payload, timestamp} ->
        %{
          machine_identifier: node.machine_identifier,
          location: node.location,
          status: status,
          total_events_processed: count,
          last_payload: payload,
          last_seen_at: timestamp
        }

      nil ->
        %{
          machine_identifier: node.machine_identifier,
          location: node.location,
          status: "unknown",
          total_events_processed: 0,
          last_payload: %{},
          last_seen_at: nil
        }
    end

  end

  @doc """
  Persists a raw telemetry event before cache aggregation.
  """
  @spec record_telemetry_event(String.t(), String.t(), map(), DateTime.t()) ::
          {:ok, TelemetryEvent.t()} | {:error, Ecto.Changeset.t()}
  def record_telemetry_event(machine_identifier, status, payload, occurred_at) do
    %TelemetryEvent{}
    |> TelemetryEvent.changeset(%{
      machine_identifier: machine_identifier,
      status: status,
      payload: payload,
      occurred_at: occurred_at
    })
    |> Repo.insert()
  end

  @doc """
  Marks a telemetry event as processed.

  Updates `processed_at` to record when the event was consumed by the
  final persistence flow.
  """
  @spec mark_telemetry_event_processed(pos_integer(), DateTime.t()) ::
          {:ok, TelemetryEvent.t()} | {:error, Ecto.Changeset.t()}
  def mark_telemetry_event_processed(event_id, processed_at) do
    event = Repo.get!(TelemetryEvent, event_id)

    event
    |> TelemetryEvent.changeset(%{processed_at: processed_at})
    |> Repo.update()
  end

  @doc """
  Lists telemetry events that are still unprocessed.

  An event is considered pending when `processed_at` is `nil`.
  """
  @spec get_unprocessed_telemetry_events() :: [TelemetryEvent.t()]
  def get_unprocessed_telemetry_events do
    from(e in TelemetryEvent,
      where: is_nil(e.processed_at),
      order_by: [asc: e.occurred_at, asc: e.id]
    )
    |> Repo.all()
  end

  @doc """
  Marks pending events as processed for a machine at a given timestamp.

  Returns the number of updated events.
  """
  @spec mark_unprocessed_events_as_processed(
          String.t(),
          DateTime.t(),
          DateTime.t()
        ) :: non_neg_integer()
  def mark_unprocessed_events_as_processed(machine_identifier, occurred_at, processed_at) do
    from(e in TelemetryEvent,
      where:
        e.machine_identifier == ^machine_identifier and
          e.occurred_at == ^occurred_at and
          is_nil(e.processed_at)
    )
    |> Repo.update_all(set: [processed_at: processed_at])
    |> elem(0)
  end

  @doc """
  Subscribes to scoped notifications about any node changes.

  The broadcasted messages match the pattern:

    * {:created, %Node{}}
    * {:updated, %Node{}}
    * {:deleted, %Node{}}

  """
  @spec subscribe_nodes(term()) :: term()
  def subscribe_nodes(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(WCore.PubSub, "user:#{key}:nodes")
  end

  defp broadcast_node(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(WCore.PubSub, "user:#{key}:nodes", message)
  end

  @doc """
  Returns the list of nodes.

  ## Examples

      iex> list_nodes(scope)
      [%Node{}, ...]

  """
  @spec list_nodes(term()) :: term()
  def list_nodes(%Scope{} = scope) do
    Repo.all_by(Node, user_id: scope.user.id)
  end

  @doc """
  Gets a single node.

  Raises `Ecto.NoResultsError` if the Node does not exist.

  ## Examples

      iex> get_node!(scope, 123)
      %Node{}

      iex> get_node!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  @spec get_node!(term(), term()) :: term()
  def get_node!(%Scope{} = scope, id) do
    Repo.get_by!(Node, id: id, user_id: scope.user.id)
  end

  @doc """
  Creates a node.

  ## Examples

      iex> create_node(scope, %{field: value})
      {:ok, %Node{}}

      iex> create_node(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_node(term(), term()) :: term()
  def create_node(%Scope{} = scope, attrs) do
    with {:ok, node = %Node{}} <-
           %Node{}
           |> Node.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_node(scope, {:created, node})
      {:ok, node}
    end
  end

  @doc """
  Updates a node.

  ## Examples

      iex> update_node(scope, node, %{field: new_value})
      {:ok, %Node{}}

      iex> update_node(scope, node, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_node(term(), term(), term()) :: term()
  def update_node(%Scope{} = scope, %Node{} = node, attrs) do
    true = node.user_id == scope.user.id

    with {:ok, node = %Node{}} <-
           node
           |> Node.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_node(scope, {:updated, node})
      {:ok, node}
    end
  end

  @doc """
  Deletes a node.

  ## Examples

      iex> delete_node(scope, node)
      {:ok, %Node{}}

      iex> delete_node(scope, node)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_node(term(), term()) :: term()
  def delete_node(%Scope{} = scope, %Node{} = node) do
    true = node.user_id == scope.user.id

    with {:ok, node = %Node{}} <-
           Repo.delete(node) do
      broadcast_node(scope, {:deleted, node})
      {:ok, node}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking node changes.

  ## Examples

      iex> change_node(scope, node)
      %Ecto.Changeset{data: %Node{}}

  """
  @spec change_node(term(), term(), term()) :: term()
  def change_node(%Scope{} = scope, %Node{} = node, attrs \\ %{}) do
    true = node.user_id == scope.user.id

    Node.changeset(node, attrs, scope)
  end

  @doc """
  Gets a single node metric by ID.

  Raises `Ecto.NoResultsError` if the node metric does not exist.

  ## Examples

      iex> get_node_metric!(123)
      %NodeMetrics{}

      iex> get_node_metric!(456)
      ** (Ecto.NoResultsError)
  """
  @spec get_node_metric!(term()) :: term()
  def get_node_metric!(id), do: Repo.get!(NodeMetrics, id)

  @doc """
  Gets the last (most recent) metric for a node.

  Returns the most recent `NodeMetrics` sorted by `inserted_at` in descending order,
  or `nil` if no metrics exist for the node.

  ## Examples

      iex> get_last_metric_by_node(node_id)
      %NodeMetrics{}

      iex> get_last_metric_by_node(nonexistent_node_id)
      nil
  """
  @spec get_last_metric_by_node(term()) :: term()
  def get_last_metric_by_node(node_id) do
    query =
      from m in NodeMetrics,
        where: m.node_id == ^node_id,
        order_by: [desc: m.inserted_at],
        limit: 1

    Repo.one(query)
  end

  @doc """
  Inserts or updates a metric for a node.

  If no metric exists for the node, creates a new one. Otherwise, updates the
  most recent metric with the provided attributes.

  ## Examples

      iex> upsert_node_metric(node, %{value: 42})
      {:ok, %NodeMetrics{}}

      iex> upsert_node_metric(node, %{invalid_field: "value"})
      {:error, %Ecto.Changeset{}}
  """
  @spec upsert_node_metric(term(), term()) :: term()
  def upsert_node_metric(%Node{} = node, attrs) do
    case Repo.get_by(NodeMetrics, node_id: node.id) do
      nil ->
        %NodeMetrics{node_id: node.id}
        |> NodeMetrics.changeset(attrs)
        |> Repo.insert()

      metric ->
        metric
        |> NodeMetrics.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Performs a batch upsert of metrics coming from ETS cache records.

  Only records whose machine identifier matches an existing node are persisted.
  Returns the `{machine_identifier, occurred_at}` pairs that were persisted,
  so callers can mark corresponding telemetry events as processed.
  """
  @spec upsert_node_metrics_batch([cache_record()]) :: [processed_key()]
  def upsert_node_metrics_batch(records) when is_list(records) do
    machine_identifiers =
      records
      |> Enum.map(fn {machine_identifier, _status, _count, _payload, _occurred_at} ->
        machine_identifier
      end)
      |> Enum.uniq()

    node_ids_by_machine_identifier =
      from(n in Node,
        where: n.machine_identifier in ^machine_identifiers,
        select: {n.machine_identifier, n.id}
      )
      |> Repo.all()
      |> Map.new()

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    {rows, persisted_keys} =
      Enum.reduce(records, {[], []}, fn
        {machine_identifier, status, count, payload, occurred_at}, {rows_acc, keys_acc} ->
          case Map.fetch(node_ids_by_machine_identifier, machine_identifier) do
            {:ok, node_id} ->
              occurred_at = DateTime.truncate(occurred_at, :second)

              row = %{
                node_id: node_id,
                status: status,
                total_events_processed: count,
                last_payload: payload,
                last_seen_at: occurred_at,
                inserted_at: now,
                updated_at: now
              }

              {[row | rows_acc], [{machine_identifier, occurred_at} | keys_acc]}

            :error ->
              {rows_acc, keys_acc}
          end
      end)

    case rows do
      [] ->
        []

      _ ->
        Repo.insert_all(NodeMetrics, rows,
          on_conflict:
            {:replace,
             [
               :status,
               :total_events_processed,
               :last_payload,
               :last_seen_at,
               :updated_at
             ]},
          conflict_target: [:node_id]
        )

        persisted_keys
        |> Enum.reverse()
        |> Enum.uniq()
    end
  end

  @doc """
  Lists all nodes with their associated metrics preloaded.

  Performs a left join with `NodeMetrics` to include metrics even if a node
  has no metrics yet.

  ## Examples

      iex> list_node_with_metrics()
      [%Node{node_metric: %NodeMetrics{}}, %Node{node_metric: nil}, ...]
  """
  @spec list_node_with_metrics() :: term()
  def list_node_with_metrics do
    Node
    |> preload(:node_metric)
    |> Repo.all()
  end

  @doc """
  Gets a node by its machine identifier.

  Returns the node if found, or `nil` if no node exists with the given machine identifier.

  ## Examples

      iex> get_node_by_machine_identifier("machine_123")
      %Node{}

      iex> get_node_by_machine_identifier("nonexistent_machine")
      nil
  """
  @spec get_node_by_machine_identifier(String.t()) :: Node.t() | nil
  def get_node_by_machine_identifier(machine_id) do
    Repo.get_by(Node, machine_identifier: machine_id)
  end

  @dashboard_topic "telemetry:dashboard"

  @doc """
  Subscribes to lightweight dashboard update notifications.
  """
  @spec subscribe_dashboard_updates() :: :ok | {:error, term()}
  def subscribe_dashboard_updates do
    Phoenix.PubSub.subscribe(WCore.PubSub, @dashboard_topic)
  end

  @doc """
  Broadcasts a lightweight invalidation event for dashboard consumers.
  """
  @spec broadcast_dashboard_node_changed(node_id(), event_count(), event_timestamp()) ::
          :ok | {:error, term()}
  def broadcast_dashboard_node_changed(machine_identifier, event_count, timestamp) do
    Phoenix.PubSub.broadcast(
      WCore.PubSub,
      @dashboard_topic,
      {:node_changed, machine_identifier, event_count, timestamp}
    )
  end
end
