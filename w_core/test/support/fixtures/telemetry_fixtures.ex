defmodule WCore.TelemetryFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `WCore.Telemetry` context.
  """

  @doc """
  Generate a unique node machine_identifier.
  """
  def unique_node_machine_identifier, do: "some machine_identifier#{System.unique_integer([:positive])}"

  @doc """
  Generate a node.
  """
  def node_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        location: "some location",
        machine_identifier: unique_node_machine_identifier()
      })

    {:ok, node} = WCore.Telemetry.create_node(scope, attrs)
    node
  end
end
