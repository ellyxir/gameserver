defmodule Gameserver.Mob do
  @moduledoc """
  Every Mob is a GenServer. It listens to combat messages and does mobby things.
  """

  use GenServer, restart: :transient

  alias Gameserver.CombatServer
  alias Gameserver.Map, as: GameMap
  alias Gameserver.UUID
  alias Gameserver.WorldServer

  @enforce_keys [:id, :name, :spawn_pos]
  defstruct [
    :id,
    :name,
    :spawn_pos,
    combat_server: CombatServer,
    world_server: WorldServer
  ]

  @typedoc "Mob, we use spawn_pos to initially spawn the mob. It's not valuable afterwards"
  @type t() :: %__MODULE__{
          id: UUID.t(),
          name: String.t(),
          spawn_pos: GameMap.coord(),
          combat_server: GenServer.server(),
          world_server: GenServer.server()
        }

  @doc """
  Starts a Mob GenServer, registered via `Gameserver.ProcessRegistry` by its id.
  """
  @spec start_link(t()) :: GenServer.on_start()
  def start_link(%__MODULE__{} = mob) do
    GenServer.start_link(__MODULE__, mob, name: via(mob.id))
  end

  @doc "Returns a via tuple for looking up a mob by id."
  @spec via(UUID.t()) :: GenServer.name()
  def via(id), do: {:via, Registry, {Gameserver.ProcessRegistry, {__MODULE__, id}}}

  @impl GenServer
  @spec init(t()) :: {:ok, t()}
  def init(%__MODULE__{} = mob) do
    Phoenix.PubSub.subscribe(Gameserver.PubSub, CombatServer.combat_topic())
    send(self(), :join_world)
    {:ok, mob}
  end

  @impl GenServer
  def handle_info(:join_world, state) do
    entity = Gameserver.Entity.new(state)
    {:ok, _pos} = WorldServer.join_entity(entity, state.world_server)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:combat_event, _event}, state) do
    {:noreply, state}
  end
end
