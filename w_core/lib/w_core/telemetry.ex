defmodule WCore.Telemetry do
  @moduledoc """
  The Telemetry context.
  """

  import Ecto.Query, warn: false
  alias WCore.Accounts.Scope
  alias WCore.Repo
  alias WCore.Telemetry.Node
  alias WCore.Telemetry.NodeMetrics

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
end
