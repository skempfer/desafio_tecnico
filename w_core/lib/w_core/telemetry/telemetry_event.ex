defmodule WCore.Telemetry.TelemetryEvent do
  @moduledoc """
  Durable event log for incoming telemetry pulses.

  Each row represents one raw event received from an edge device before any
  in-memory aggregation or write-behind processing.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "telemetry_events" do
    field :machine_identifier, :string
    field :status, :string
    field :payload, :map
    field :occurred_at, :utc_datetime
    field :processed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for durable telemetry events.

  Casts accepted attributes and validates the minimum required data needed to
  persist an incoming telemetry pulse in the durable event log.
  """
  @spec changeset(term(), term()) :: term()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:machine_identifier, :status, :payload, :occurred_at, :processed_at])
    |> validate_required([:machine_identifier, :status, :occurred_at])
  end
end
