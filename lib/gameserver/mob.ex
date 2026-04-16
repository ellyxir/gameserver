defmodule Gameserver.Mob do
  @moduledoc """
  Every Mob is a GenServer. It listens to combat messages and does mobby things.
  """

  use GenServer, restart: :transient

  alias Gameserver.CombatEvent
  alias Gameserver.CombatServer
  alias Gameserver.Entity
  alias Gameserver.Map, as: GameMap
  alias Gameserver.UUID
  alias Gameserver.WorldServer

  @enforce_keys [:id, :name, :spawn_pos]
  defstruct [
    :id,
    :name,
    :spawn_pos,
    :aggro_target,
    :attack_timer,
    abilities: [],
    combat_server: CombatServer,
    world_server: WorldServer
  ]

  @typedoc "Mob, we use spawn_pos to initially spawn the mob. It's not valuable afterwards"
  @type t() :: %__MODULE__{
          id: UUID.t(),
          name: String.t(),
          spawn_pos: GameMap.coord(),
          aggro_target: UUID.t() | nil,
          attack_timer: reference() | nil,
          abilities: Entity.ability_list(),
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

  @attack_interval_ms 2000

  @impl GenServer
  def handle_info(
        {:combat_event, %CombatEvent{defender_id: my_id, attacker_id: attacker_id, dead: true}},
        %{id: my_id} = state
      ) do
    # we are dead, cancel timer if we have one
    if state.attack_timer, do: Process.cancel_timer(state.attack_timer)

    # despawn
    WorldServer.leave(my_id, state.world_server)

    # kill process
    {:stop, :normal, %{state | aggro_target: attacker_id, attack_timer: nil}}
  end

  def handle_info(
        {:combat_event, %CombatEvent{defender_id: my_id, attacker_id: attacker_id}},
        %{id: my_id} = state
      ) do
    timer =
      state.attack_timer || Process.send_after(self(), :attack_target, 0)

    {:noreply, %{state | aggro_target: attacker_id, attack_timer: timer}}
  end

  @impl GenServer
  def handle_info(:attack_target, %{aggro_target: target} = state) when target != nil do
    case CombatServer.use_ability(state.id, target, :melee_strike, state.combat_server) do
      {:ok, _cooldown} ->
        timer = Process.send_after(self(), :attack_target, @attack_interval_ms)
        {:noreply, %{state | attack_timer: timer}}

      {:error, _reason} ->
        {:noreply, %{state | aggro_target: nil, attack_timer: nil}}
    end
  end

  def handle_info(:attack_target, %{aggro_target: nil} = state) do
    {:noreply, %{state | attack_timer: nil}}
  end

  @impl GenServer
  def handle_info({:combat_event, _event}, state) do
    {:noreply, state}
  end
end
