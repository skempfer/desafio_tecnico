defmodule WCore.Repo.Migrations.CreateTelemetryEvents do
  use Ecto.Migration

  @moduledoc """
  Creates the durable telemetry event log table.

  The `telemetry_events` table stores each raw event received by the ingestion
  pipeline, allowing reliable persistence before cache updates and downstream
  processing.
  """

  @typedoc "Supported indexed fields for telemetry event lookup and processing queries."
  @type indexed_field :: :machine_identifier | :processed_at | :occurred_at

  @doc """
  Creates the `telemetry_events` table and supporting indexes.

  Indexes optimize common lookup and processing flows by machine identifier,
  event occurrence time, and processing state.
  """
  @spec change() :: any()
  def change do
    create table(:telemetry_events) do
      add :machine_identifier, :string, null: false
      add :status, :string, null: false
      add :payload, :map
      add :occurred_at, :utc_datetime, null: false
      add :processed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:telemetry_events, [:machine_identifier])
    create index(:telemetry_events, [:processed_at])
    create index(:telemetry_events, [:occurred_at])
  end
end
