defmodule Gameserver.Mob do
  @moduledoc """
  Every Mob is a GenServer managing a single NPC's combat behaviour.

  Joins the world on start, subscribes to combat events. When damaged, sets the
  attacker as aggro target and begins a periodic attack loop. Each tick picks a
  random ability from its configured abilities list; retries on cooldown, clears
  aggro on unrecoverable errors (target dead, out of range, not found).
  """

  use GenServer, restart: :transient

  alias Gameserver.CombatEvent
  alias Gameserver.CombatServer
  alias Gameserver.Cooldowns
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
  # mob has no abilities at all, it can never attack, clear aggro and stop the loop
  def handle_info(:attack_target, %{abilities: []} = state) do
    {:noreply, %{state | aggro_target: nil, attack_timer: nil}}
  end

  def handle_info(:attack_target, %{aggro_target: target_id} = state) when target_id != nil do
    case mob_action(state, target_id, state.combat_server) do
      {:ok, _cooldown} ->
        timer = Process.send_after(self(), :attack_target, @attack_interval_ms)
        {:noreply, %{state | attack_timer: timer}}

      {:error, :on_cooldown} ->
        # all abilities are on cooldown right now, reschedule and try again later
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

  # picks a random ability from the mob's list and uses it on the target.
  # on :on_cooldown, retries with the remaining abilities.
  # returns {:ok, cooldown} on success, or {:error, reason} if no ability
  # could be used (all on cooldown, target dead, etc.)
  @spec mob_action(t(), target_id :: UUID.t(), combat_server :: GenServer.server()) ::
          {:ok, Cooldowns.cooldown()} | {:error, term()}
  # base case: reached only via recursion below, after every ability returned
  # :on_cooldown. the empty-list case at handle_info catches the "mob never had
  # abilities" scenario earlier.
  defp mob_action(%__MODULE__{abilities: []}, _target_id, _combat_server) do
    {:error, :on_cooldown}
  end

  defp mob_action(%__MODULE__{abilities: abilities} = mob, target_id, combat_server) do
    ability_id = select_ability(mob)

    case CombatServer.use_ability(mob.id, target_id, ability_id, combat_server) do
      {:ok, cooldown} ->
        {:ok, cooldown}

      {:error, :on_cooldown} ->
        updated_mob = %{mob | abilities: List.delete(abilities, ability_id)}
        mob_action(updated_mob, target_id, combat_server)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # returns one of the mob's abilities to use during combat
  @spec select_ability(t()) :: atom()
  defp select_ability(%__MODULE__{abilities: abilities} = _mob) do
    Enum.random(abilities)
  end
end
