defmodule Gameserver.CombatServer do
  @moduledoc """
  handles all things combat
  fairly stateless, mainly acts to ensure everything happens sequentially

  calls out to the WorldServer for world coordinates,
  calls out to EntityServer to read/write stats
  """

  use GenServer

  alias Gameserver.Abilities
  alias Gameserver.Ability
  alias Gameserver.CombatEvent
  alias Gameserver.Cooldowns
  alias Gameserver.Effect
  alias Gameserver.Entity
  alias Gameserver.EntityServer
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
         {:ok, ability} <- Abilities.get(:melee_strike),
         :ok <- check_adjacent(attacker, defender, ability.range) do
      defender_hp_before = Stat.effective(defender.stats.hp, defender.stats)

      transforms = execute_ability(ability, attacker, defender)
      update_fn = build_entity_update_fn(transforms)

      {:ok, defender} =
        EntityServer.update_entity(
          defender_id,
          update_fn,
          entity_server
        )

      defender_hp_after = Stat.effective(defender.stats.hp, defender.stats)
      damage_taken = defender_hp_before - defender_hp_after
      broadcast_combat_event(attacker, defender, damage_taken, defender_hp_after)

      {:reply, {:ok, {:attack, ability.cooldown_ms}}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @doc """
  Executes an ability's effects against a target, returning a list of transforms.

  Iterates the ability's effect list, calling `valid?/3` then `apply/3` on each.
  Effects that fail validation are skipped.
  """
  @spec execute_ability(Ability.t(), source :: Entity.t(), target :: Entity.t()) ::
          [Effect.transform()]
  def execute_ability(%Ability{effects: effects}, %Entity{} = source, %Entity{} = target) do
    effects
    |> Enum.filter(fn {module, args} -> module.valid?(args, source, target) end)
    |> Enum.map(fn {module, args} -> module.apply(args, source, target) end)
  end

  @spec build_entity_update_fn([Effect.transform()]) :: Effect.transform()
  defp build_entity_update_fn(transforms) do
    fn entity ->
      entity = Enum.reduce(transforms, entity, fn transform, acc -> transform.(acc) end)
      dead = entity.stats.dead || Stat.effective(entity.stats.hp, entity.stats) <= 0
      %{entity | stats: %{entity.stats | dead: dead}}
    end
  end

  @spec broadcast_combat_event(
          attacker :: Entity.t(),
          defender :: Entity.t(),
          dmg :: non_neg_integer(),
          defender_hp :: non_neg_integer()
        ) :: :ok
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

  @spec check_adjacent(Entity.t(), Entity.t(), range :: pos_integer()) ::
          :ok | {:error, :out_of_range}
  defp check_adjacent(
         %Entity{pos: {a_x, a_y}},
         %Entity{pos: {d_x, d_y}},
         range
       ) do
    if abs(a_x - d_x) <= range and abs(a_y - d_y) <= range do
      :ok
    else
      {:error, :out_of_range}
    end
  end
end
