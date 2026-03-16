defmodule Gameserver.MobServer do
  @moduledoc """
  A DynamicSupervisor that spawns mobs into the world on startup.

  Currently has no children — per-mob AI GenServers will be added later.
  """

  use DynamicSupervisor

  alias Gameserver.Entity
  alias Gameserver.WorldServer

  @mobs [
    {"goblin", {12, 3}},
    {"spider", {7, 11}},
    {"rat", {3, 3}}
  ]

  @doc "Starts the MobServer. Accepts `:world_server` option, defaults to WorldServer."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    {world_server, sup_opts} = Keyword.pop(opts, :world_server, WorldServer)
    DynamicSupervisor.start_link(__MODULE__, world_server, sup_opts)
  end

  @impl DynamicSupervisor
  def init(world_server) do
    # we can move this to a child genserver for startup
    # if we notice we are blocking startup
    spawn_mobs(world_server)
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @spec spawn_mobs(GenServer.server()) :: :ok
  defp spawn_mobs(world_server) do
    Enum.each(@mobs, fn {name, pos} ->
      entity = Entity.new(name: name, type: :mob, pos: pos)
      {:ok, _pos} = WorldServer.join_entity(entity, world_server)
    end)
  end
end
