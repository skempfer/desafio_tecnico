defmodule WCore.Telemetry.TelemetryEvent do
  @moduledoc """
  Durable event log for incoming telemetry pulses.

  Each row represents one raw event received from an edge device before any
  in-memory aggregation or write-behind processing.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          machine_identifier: String.t() | nil,
          status: String.t() | nil,
          payload: map() | nil,
          error_message: String.t() | nil,
          occurred_at: DateTime.t() | nil,
          processed_at: DateTime.t() | nil,
          resolved_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @typedoc "Attributes accepted when creating or updating a telemetry event changeset."
  @type attrs :: %{
          optional(:machine_identifier) => String.t(),
          optional(:status) => String.t(),
          optional(:payload) => map(),
          optional(:error_message) => String.t(),
          optional(:occurred_at) => DateTime.t(),
          optional(:processed_at) => DateTime.t(),
          optional(:resolved_at) => DateTime.t()
        }

  schema "telemetry_events" do
    field :machine_identifier, :string
    field :status, :string
    field :payload, :map
    field :error_message, :string
    field :occurred_at, :utc_datetime
    field :processed_at, :utc_datetime
    field :resolved_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for durable telemetry events.

  Casts accepted attributes and validates the minimum required data needed to
  persist an incoming telemetry pulse in the durable event log.
  """
  @spec changeset(t(), attrs()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :machine_identifier,
      :status,
      :payload,
      :error_message,
      :occurred_at,
      :processed_at,
      :resolved_at
    ])
    |> validate_required([:machine_identifier, :status, :occurred_at])
  end
end
