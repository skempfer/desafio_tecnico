defmodule WCore.Telemetry.Node do
  use Ecto.Schema
  import Ecto.Changeset

  schema "nodes" do
    field :machine_identifier, :string
    field :location, :string
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for a Telemetry Node within a user_scope context.

  this function enforces:
  - Required fields: `machine_identifier` and `location`
  - Uniqueness of `machine_identifier` (per system)
  - Automatic association of the node with the current user from the `user_scope`

  It should be used whenever creating or updating a node thet is bound to a specific user,
  ensuring consistency and preventing croos-user data leakage.

  ## Parameters
   * `node` - the `%Node{}` struct being created os updated
    * `attrs` - incoming attributes for casting
    * `user_scope` - the struct containing the authenticated user context,

  ## Returns
  - An `%Ecto.Changeset{}` ready for insertion or persistence.
  """
  def changeset(node, attrs, user_scope) do
    node
    |> cast(attrs, [:machine_identifier, :location])
    |> validate_required([:machine_identifier, :location])
    |> unique_constraint(:machine_identifier)
    |> put_change(:user_id, user_scope.user.id)
  end
end
