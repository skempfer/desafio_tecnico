defmodule WCore.Repo.Migrations.AddErrorTrackingToTelemetryEvents do
  use Ecto.Migration

  @moduledoc """
  Adds structured error tracking fields to telemetry events.

  The new columns support error history UIs that need a human-readable message
  and a resolved lifecycle without deleting the original event log.
  """

  @doc """
  Adds `error_message` and `resolved_at` columns plus indexes used by machine
  error history queries.
  """
  @spec change() :: any()
  def change do
    alter table(:telemetry_events) do
      add :error_message, :string
      add :resolved_at, :utc_datetime
    end

    create index(:telemetry_events, [:resolved_at])
    create index(:telemetry_events, [:machine_identifier, :resolved_at])
  end
end
