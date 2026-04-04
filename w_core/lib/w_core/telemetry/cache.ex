defmodule WCore.Telemetry.Cache do
  @moduledoc """
  In-memory cache for telemetry node metrics backed by an ETS table.

  Stores the latest status, payload, timestamp and a monotonic update counter
  for each node. The table is created as a named, public, concurrent-read/write
  `:set`, so reads and writes can happen from any process without locking.

  ## ETS record layout

  Each row is stored as a 5-element tuple:

      {node_id, status, count, payload, timestamp}

  | Position | Field       | Description                                      |
  |----------|-------------|--------------------------------------------------|
  | 1        | `node_id`   | Primary key — unique identifier of the node     |
  | 2        | `status`    | Latest reported status (e.g. `:ok`, `:error`)   |
  | 3        | `count`     | Number of times the entry has been updated       |
  | 4        | `payload`   | Arbitrary metric payload from the last update    |
  | 5        | `timestamp` | DateTime of the last update                      |

  ## Supervision

  The module exposes `child_spec/1` and `start_link/1` so it can be placed
  directly in a supervision tree as a `:worker` child.
  """

  @table :w_core_telemetry_cache

  @doc """
  Creates the ETS table and returns `{:ok, pid}`.

  Should be called by the supervisor via `start_link/1`. The table is
  configured with `read_concurrency: true` and `write_concurrency: true`
  for efficient concurrent access.
  """
  @spec start_link(term()) :: term()
  def start_link(_opts) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
    end

    {:ok, self()}
  end

  @doc """
  Returns the child specification for use in a supervision tree.

  The process is started as a permanent worker with a 500 ms shutdown timeout.
  """
  @spec child_spec(term()) :: term()
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @doc """
  Inserts or updates the cache entry for `node_id`.

  - **Insert**: when no entry exists, creates a new record with `count = 1`.
  - **Update**: atomically increments `count` and updates `status`, `payload`
    and `timestamp` in-place using `:ets.update_counter/3` and
    `:ets.update_element/3`.

  Returns the new update count on update, or `:true` on insert.
  """
  @spec put(term(), term(), term(), term()) :: term()
  def put(node_id, status, payload, timestamp) do
    case :ets.lookup(@table, node_id) do
      [] ->
        :ets.insert(@table, {node_id, status, 1, payload, timestamp})
      [{_, _, _count, _, _}] ->
        new_count = :ets.update_counter(@table, node_id, {3, 1})
        :ets.update_element(@table, node_id, {2, status})
        :ets.update_element(@table, node_id, {4, payload})
        :ets.update_element(@table, node_id, {5, timestamp})
        new_count
    end
  end

  @doc """
  Retrieves the cache entry for `node_id`.

  Returns `{status, count, payload, timestamp}` if found, or `nil` otherwise.
  """
  @spec get(term()) :: term()
  def get(node_id) do
    case :ets.lookup(@table, node_id) do
      [] -> nil
      [{_, status, count, payload, ts}] -> {status, count, payload, ts}
    end
  end

  @doc """
  Returns all entries in the cache as a list of raw ETS tuples.

  Each element has the form `{node_id, status, count, payload, timestamp}`.
  """
  @spec get_all() :: term()
  def get_all do
    :ets.tab2list(@table)
  end

  @doc """
  Removes the cache entry for `node_id`.

  No-op if the entry does not exist.
  """
  @spec delete(term()) :: term()
  def delete(node_id) do
    :ets.delete(@table, node_id)
  end

  @doc """
  Removes all entries from the cache table without deleting the table itself.
  """
  @spec clear() :: term()
  def clear do
    :ets.delete_all_objects(@table)
  end
end
