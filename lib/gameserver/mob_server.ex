defmodule Gameserver.MobServer do
  @moduledoc """
  A DynamicSupervisor that spawns and supervises per-mob GenServer processes.
  """

  use DynamicSupervisor

  alias Gameserver.Map, as: GameMap
  alias Gameserver.UUID
  alias Gameserver.WorldServer

  @mob_names ["goblin", "spider", "rat"]

  @typedoc false
  @typep option() ::
           {:world_server, GenServer.server()}
           | {:name, Supervisor.name() | nil}
           | {:strategy, DynamicSupervisor.strategy()}
           | {:max_children, non_neg_integer() | :infinity}

  @doc "Starts the MobServer. Accepts `:world_server` option, defaults to WorldServer."
  @spec start_link([option()]) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    {world_server, sup_opts} = Keyword.pop(opts, :world_server, WorldServer)
    DynamicSupervisor.start_link(__MODULE__, world_server, sup_opts)
  end

  @impl DynamicSupervisor
  def init(world_server) do
    sup = self()

    # can't call DynamicSupervisor.start_child/2 from init since we're not up yet
    # so we spawn a child process to do this
    spawn_link(fn ->
      map = %GameMap{rooms: rooms} = WorldServer.get_map(world_server)

      # distribute mobs across rooms, cycling through available rooms
      @mob_names
      |> Enum.zip(Stream.cycle(rooms))
      |> Enum.each(fn {name, room} ->
        pos = GameMap.random_tile_in_room(map, room)
        {:ok, _pid} = spawn_mob(sup, name, pos, world_server)
      end)
    end)

    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @spec spawn_mob(GenServer.server(), String.t(), GameMap.coord(), GenServer.server()) ::
          DynamicSupervisor.on_start_child()
  defp spawn_mob(supervisor, name, pos, world_server) do
    mob = %Gameserver.Mob{
      id: UUID.generate(),
      name: name,
      spawn_pos: pos,
      world_server: world_server
    }

    DynamicSupervisor.start_child(supervisor, {Gameserver.Mob, mob})
  end
end
