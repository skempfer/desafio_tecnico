defmodule WCore.Telemetry.Node do
  @moduledoc """
  Schema for registered telemetry nodes.

  A node represents a monitored device owned by a user.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          machine_identifier: String.t() | nil,
          location: String.t() | nil,
          user_id: integer() | nil,
          node_metric:
            WCore.Telemetry.NodeMetrics.t()
            | Ecto.Association.NotLoaded.t()
            | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "nodes" do
    field :machine_identifier, :string
    field :location, :string
    field :user_id, :id

    has_one :node_metric, WCore.Telemetry.NodeMetrics

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for a telemetry node within a user scope.

  This function enforces:
  - Required fields: `machine_identifier` and `location`
  - Uniqueness of `machine_identifier` (per system)
  - Automatic association of the node with the authenticated user in `user_scope`

  It should be used whenever creating or updating a node bound to a specific
  user, ensuring consistency and preventing cross-user data leakage.

  ## Parameters
  - `node` - `%Node{}` being created or updated
  - `attrs` - incoming attributes for casting
  - `user_scope` - authenticated user context used to set `user_id`

  ## Returns
  - An `%Ecto.Changeset{}` ready for insertion or persistence.
  """
  @spec changeset(term(), term(), term()) :: term()
  def changeset(node, attrs, user_scope) do
    node
    |> cast(attrs, [:machine_identifier, :location])
    |> validate_required([:machine_identifier, :location])
    |> unique_constraint(:machine_identifier)
    |> put_change(:user_id, user_scope.user.id)
  end
end
