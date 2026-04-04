defmodule WCore.Repo.Migrations.CreateNodeMetrics do
  use Ecto.Migration

  @moduledoc """
  Creates the `node_metrics` table used to store each node's latest telemetry
  state.

  The unique index on `node_id` enforces one metrics row per node.
  """

  @doc """
  Creates the `node_metrics` table and indexes for lookup and recency queries.
  """
  def change do
    create table(:node_metrics) do
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :status, :string, null: false
      add :total_events_processed, :integer, default: 0, null: false
      add :last_payload, :text
      add :last_seen_at, :utc_datetime, null: false

      timestamps()
    end

    create index(:node_metrics, [:node_id], unique: true, name: :unique_node_metrics_index)

    create index(:node_metrics, [:last_seen_at])
  end
end
