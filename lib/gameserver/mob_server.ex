defmodule Gameserver.MobServer do
  @moduledoc """
  A DynamicSupervisor that spawns and supervises per-mob GenServer processes.
  """

  use DynamicSupervisor

  alias Gameserver.EntityServer
  alias Gameserver.Map, as: GameMap
  alias Gameserver.UUID
  alias Gameserver.WorldServer

  @default_mob_names ["goblin", "spider", "rat"]

  @typedoc false
  @typep option() ::
           {:world_server, GenServer.server()}
           | {:entity_server, GenServer.server()}
           | {:mob_count, non_neg_integer()}
           | {:name, Supervisor.name() | nil}
           | {:strategy, DynamicSupervisor.strategy()}
           | {:max_children, non_neg_integer() | :infinity}

  @doc "Starts the MobServer. Accepts `:world_server`, `:entity_server`, and `:mob_count` options."
  @spec start_link([option()]) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    {world_server, opts} = Keyword.pop(opts, :world_server, WorldServer)
    {entity_server, opts} = Keyword.pop(opts, :entity_server, EntityServer)
    {mob_count, sup_opts} = Keyword.pop(opts, :mob_count)
    DynamicSupervisor.start_link(__MODULE__, {world_server, entity_server, mob_count}, sup_opts)
  end

  # dialyzer can't track opaque types (MapSet) through Enum.reduce accumulators
  @dialyzer {:no_opaque, init: 1}
  @impl DynamicSupervisor
  def init({world_server, entity_server, mob_count_override}) do
    sup = self()

    # can't call DynamicSupervisor.start_child/2 from init since we're not up yet
    # so we spawn a child process to do this
    spawn_link(fn ->
      map = %GameMap{rooms: rooms} = WorldServer.get_map(world_server)

      # distribute mobs across rooms, cycling through available rooms
      mob_count =
        case mob_count_override do
          nil -> Application.get_env(:gameserver, :mob_count, 35)
          n -> n
        end

      @default_mob_names
      |> Stream.cycle()
      |> Enum.take(mob_count)
      |> Enum.zip(Stream.cycle(rooms))
      |> Enum.reduce(MapSet.new(), fn {name, room}, taken ->
        pos = available_tile_in_room(map, room, taken)
        {:ok, _pid} = spawn_mob(sup, name, pos, world_server, entity_server: entity_server)
        MapSet.put(taken, pos)
      end)
    end)

    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @max_tile_attempts 50

  @dialyzer {:no_opaque, available_tile_in_room: 4}
  @spec available_tile_in_room(
          GameMap.t(),
          GameMap.room(),
          MapSet.t(GameMap.coord()),
          attempts :: non_neg_integer()
        ) ::
          GameMap.coord()
  defp available_tile_in_room(map, room, taken, attempts \\ @max_tile_attempts)

  defp available_tile_in_room(map, room, _taken, 0) do
    GameMap.random_tile_in_room(map, room)
  end

  defp available_tile_in_room(map, room, taken, attempts) do
    pos = GameMap.random_tile_in_room(map, room)

    if MapSet.member?(taken, pos) do
      available_tile_in_room(map, room, taken, attempts - 1)
    else
      pos
    end
  end

  @mob_abilities [:melee_strike, :poison_strike]

  @respawn_delay_ms 5000

  @doc "Spawns a new mob under this supervisor and joins it to the world."
  @spec spawn_mob(GenServer.server(), String.t(), GameMap.coord(), GenServer.server(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def spawn_mob(supervisor, name, pos, world_server, opts \\ []) do
    mob = %Gameserver.Mob{
      id: UUID.generate(),
      name: name,
      spawn_pos: pos,
      abilities: @mob_abilities,
      entity_server: Keyword.get(opts, :entity_server, EntityServer),
      mob_server: supervisor,
      respawn_delay_ms: Keyword.get(opts, :respawn_delay_ms, @respawn_delay_ms),
      world_server: world_server
    }

    DynamicSupervisor.start_child(supervisor, {Gameserver.Mob, mob})
  end
end
