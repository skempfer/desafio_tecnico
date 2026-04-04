defmodule WCore.Telemetry.NodeMetrics do
  @moduledoc """
  Schema for the latest telemetry metrics of a node.

  This model stores the current status snapshot and aggregate counters used by
  dashboard and monitoring queries.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "node_metrics" do
    belongs_to :node, WCore.Telemetry.Node
    field :status, :string
    field :total_events_processed, :integer
    field :last_payload, :map
    field :last_seen_at, :utc_datetime
    timestamps()
  end

  @doc """
  Builds a changeset for node metrics.

  Validates required fields, checks node foreign key integrity, and enforces
  one metrics record per node through `unique_node_metrics_index`.
  """
  def changeset(metrics, attrs) do
    metrics
    |> cast(attrs, [:node_id, :status, :total_events_processed, :last_payload, :last_seen_at])
    |> validate_required([:node_id, :status, :total_events_processed, :last_seen_at])
    |> foreign_key_constraint(:node_id)
    |> unique_constraint(:node_id, name: :unique_node_metrics_index)
  end
end
