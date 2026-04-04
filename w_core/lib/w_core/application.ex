defmodule WCore.Application do
  @moduledoc """
  OTP application entrypoint for WCore.

  Starts and supervises the core runtime services:

  - telemetry and endpoint supervision
  - database repository
  - automatic migration runner for non-release environments
  - DNS clustering and PubSub
  """

  use Application

  @doc """
  Starts the WCore supervision tree.

  Initializes repository, migration runner, PubSub and HTTP endpoint.
  """
  @impl true
  @spec start(term(), term()) :: term()
  def start(_type, _args) do
    children = [
      WCoreWeb.Telemetry,
      WCore.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:w_core, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:w_core, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: WCore.PubSub},
      WCoreWeb.Endpoint,
      {WCore.Telemetry.Cache, []},
      {WCore.Telemetry.Ingester, []},
      {WCore.Telemetry.Worker, []}
    ]

    opts = [strategy: :one_for_one, name: WCore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Handles endpoint configuration updates during hot code upgrades.
  """
  @impl true
  @spec config_change(term(), term(), term()) :: term()
  def config_change(changed, _new, removed) do
    WCoreWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations? do
    # Run migrations automatically outside releases.
    System.get_env("RELEASE_NAME") == nil
  end
end
