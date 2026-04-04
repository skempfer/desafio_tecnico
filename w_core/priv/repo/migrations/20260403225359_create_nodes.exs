defmodule WCore.Repo.Migrations.CreateNodes do
  use Ecto.Migration

  @moduledoc """
  Creates the `nodes` table used as the static registry of monitored devices.

  Each node belongs to a user and is uniquely identified by
  `machine_identifier`.
  """

  @doc """
  Creates the `nodes` table and its ownership/uniqueness indexes.
  """
  def change do
    create table(:nodes) do
      add :machine_identifier, :string
      add :location, :string
      add :user_id, references(:users, type: :id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:nodes, [:user_id])

    create unique_index(:nodes, [:machine_identifier])
  end
end
