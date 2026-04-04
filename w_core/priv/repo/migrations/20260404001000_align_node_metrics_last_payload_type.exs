defmodule WCore.Repo.Migrations.AlignNodeMetricsLastPayloadType do
  use Ecto.Migration

  @moduledoc """
  Aligns `node_metrics.last_payload` column type with the Ecto schema.

  The schema models `last_payload` as `:map`, so this migration updates the
  database column from `:text` to `:map` for consistency.
  """

  @doc """
  Rebuilds `node_metrics` so `last_payload` uses `:map`.
  """
  def up do
    create table(:node_metrics_new) do
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :status, :string, null: false
      add :total_events_processed, :integer, default: 0, null: false
      add :last_payload, :map
      add :last_seen_at, :utc_datetime, null: false

      timestamps()
    end

    execute("""
    INSERT INTO node_metrics_new (
      id,
      node_id,
      status,
      total_events_processed,
      last_payload,
      last_seen_at,
      inserted_at,
      updated_at
    )
    SELECT
      id,
      node_id,
      status,
      total_events_processed,
      last_payload,
      last_seen_at,
      inserted_at,
      updated_at
    FROM node_metrics
    """)

    drop table(:node_metrics)
    rename table(:node_metrics_new), to: table(:node_metrics)

    create index(:node_metrics, [:node_id], unique: true, name: :unique_node_metrics_index)
    create index(:node_metrics, [:last_seen_at])
  end

  @doc """
  Reverts `node_metrics.last_payload` back to `:text`.
  """
  def down do
    create table(:node_metrics_old) do
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :status, :string, null: false
      add :total_events_processed, :integer, default: 0, null: false
      add :last_payload, :text
      add :last_seen_at, :utc_datetime, null: false

      timestamps()
    end

    execute("""
    INSERT INTO node_metrics_old (
      id,
      node_id,
      status,
      total_events_processed,
      last_payload,
      last_seen_at,
      inserted_at,
      updated_at
    )
    SELECT
      id,
      node_id,
      status,
      total_events_processed,
      last_payload,
      last_seen_at,
      inserted_at,
      updated_at
    FROM node_metrics
    """)

    drop table(:node_metrics)
    rename table(:node_metrics_old), to: table(:node_metrics)

    create index(:node_metrics, [:node_id], unique: true, name: :unique_node_metrics_index)
    create index(:node_metrics, [:last_seen_at])
  end
end
