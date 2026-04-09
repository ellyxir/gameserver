defmodule Gameserver.CombatServer do
  @moduledoc """
  handles all things combat
  fairly stateless, mainly acts to ensure everything happens sequentially

  calls out to the WorldServer for world coordinates,
  calls out to EntityServer to read/write stats
  """

  use GenServer

  alias Gameserver.Ability
  alias Gameserver.CombatEvent
  alias Gameserver.Cooldowns
  alias Gameserver.Effect
  alias Gameserver.Entity
  alias Gameserver.EntityServer
  alias Gameserver.HpStat
  alias Gameserver.Stat
  alias Gameserver.UUID
  alias Gameserver.WorldServer

  @typedoc "CombatServer state"
  @type t() :: %__MODULE__{
          entity_server: GenServer.server(),
          world_server: GenServer.server()
        }

  defstruct entity_server: EntityServer,
            world_server: WorldServer

  @doc """
  Starts the combat server. Accepts `:name`, `:entity_server`, and `:world_server` options.
  """
  @typedoc false
  @typep option() ::
           {:name, GenServer.name() | nil}
           | {:entity_server, GenServer.server()}
           | {:world_server, GenServer.server()}

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @attack_cooldown_ms 1000
  @combat_topic "combat:events"

  @doc "Returns the PubSub topic for combat event broadcasts."
  @spec combat_topic() :: String.t()
  def combat_topic, do: @combat_topic

  @doc """
  Attacks defender with attacker. Validates adjacency, applies damage.

  Returns `{:ok, {:attack, cooldown_ms}}` on success.
  """
  @spec attack(UUID.t(), UUID.t(), GenServer.server()) ::
          {:ok, Cooldowns.cooldown()} | {:error, :not_found | :out_of_range}
  def attack(attacker_id, defender_id, server \\ __MODULE__) do
    GenServer.call(server, {:attack, attacker_id, defender_id})
  end

  # Server callbacks

  @impl GenServer
  def init(args) do
    entity_server = Keyword.get(args, :entity_server, EntityServer)
    world_server = Keyword.get(args, :world_server, WorldServer)
    {:ok, %__MODULE__{entity_server: entity_server, world_server: world_server}}
  end

  @impl GenServer
  def handle_call(
        {:attack, attacker_id, defender_id},
        _from,
        %__MODULE__{entity_server: entity_server} = state
      ) do
    with {:ok, attacker} <- EntityServer.get_entity(attacker_id, entity_server),
         {:ok, defender} <- EntityServer.get_entity(defender_id, entity_server),
         :ok <- check_alive(defender),
         :ok <- check_adjacent(attacker, defender) do
      defender_hp_before = Stat.effective(defender.stats.hp, defender.stats)

      update_fn = perform_attack(attacker, defender)

      {:ok, defender} =
        EntityServer.update_entity(
          defender_id,
          update_fn,
          entity_server
        )

      defender_hp_after = Stat.effective(defender.stats.hp, defender.stats)
      damage_taken = defender_hp_before - defender_hp_after
      broadcast_combat_event(attacker, defender, damage_taken, defender_hp_after)

      {:reply, {:ok, {:attack, @attack_cooldown_ms}}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @doc """
  Executes an ability's effects against a target, returning a list of intents.

  Iterates the ability's effect list, calling `valid?/3` then `apply/3` on each.
  Effects that fail validation are skipped.
  """
  @spec execute_ability(Ability.t(), source :: Entity.t(), target :: Entity.t()) ::
          [Effect.intent()]
  def execute_ability(%Ability{effects: effects}, %Entity{} = source, %Entity{} = target) do
    effects
    |> Enum.filter(fn {module, args} -> module.valid?(args, source, target) end)
    |> Enum.map(fn {module, args} -> module.apply(args, source, target) end)
  end

  @doc """
  performs attack, returns the function to be executed on the entityserver to update the defender
  note this is a pure function, doesn't update the entityserver
  """
  @spec perform_attack(Entity.t(), Entity.t()) :: EntityServer.entity_transform_function()
  def perform_attack(%Entity{} = attacker, %Entity{} = _defender) do
    damage = attacker.stats.attack_power

    fn e ->
      hp = HpStat.apply_damage(e.stats.hp, damage)

      # once dead, always dead
      is_dead = e.stats.dead || Stat.effective(hp, e.stats) <= 0

      %{e | stats: %{e.stats | hp: hp, dead: is_dead}}
    end
  end

  @spec broadcast_combat_event(Entity.t(), Entity.t(), non_neg_integer(), non_neg_integer()) ::
          :ok
  defp broadcast_combat_event(%Entity{} = attacker, %Entity{} = defender, damage, defender_hp)
       when is_integer(damage) and is_integer(defender_hp) do
    event = %CombatEvent{
      attacker_id: attacker.id,
      defender_id: defender.id,
      damage: damage,
      defender_hp: defender_hp,
      dead: defender.stats.dead
    }

    Phoenix.PubSub.broadcast(Gameserver.PubSub, @combat_topic, {:combat_event, event})
  end

  @spec check_alive(Entity.t()) :: :ok | {:error, :target_dead}
  defp check_alive(%Entity{stats: %{dead: false}}), do: :ok
  defp check_alive(%Entity{stats: %{dead: true}}), do: {:error, :target_dead}

  @spec check_adjacent(Entity.t(), Entity.t()) ::
          :ok | {:error, :out_of_range}
  defp check_adjacent(
         %Entity{pos: {a_x, a_y}} = _attacker,
         %Entity{pos: {d_x, d_y}} = _defender
       ) do
    if abs(a_x - d_x) <= 1 and abs(a_y - d_y) <= 1 do
      :ok
    else
      {:error, :out_of_range}
    end
  end
end
