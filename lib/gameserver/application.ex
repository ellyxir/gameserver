defmodule Gameserver.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GameserverWeb.Telemetry,
      Gameserver.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:gameserver, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:gameserver, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Gameserver.PubSub},
      Gameserver.EntityServer,
      Gameserver.WorldServer.StateETS,
      Gameserver.WorldServer,
      {Registry, keys: :unique, name: Gameserver.ProcessRegistry},
      Gameserver.MobServer,
      Gameserver.CombatServer,
      # Start to serve requests, typically the last entry
      GameserverWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_all, name: Gameserver.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GameserverWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations? do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
