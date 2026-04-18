defmodule Gameserver.CombatServer do
  @moduledoc """
  handles all things combat
  fairly stateless, mainly acts to ensure everything happens sequentially

  calls out to the WorldServer for world coordinates,
  calls out to EntityServer to read/write stats
  """

  use GenServer

  import Gameserver.UUID, only: [is_uuid: 1]

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
  Has `source_id` use `ability_id` on `target_id`. `source_id` and `target_id`
  may be equal for self-cast abilities (e.g. buffs with range 0).

  Validates that the source knows the ability, the ability is off cooldown, the
  target is alive and within range, then runs the ability's effects on the
  target and starts the cooldown on the source.

  Returns `{:ok, {:use_ability, cooldown_ms}}` on success.
  """
  @spec use_ability(source :: UUID.t(), target :: UUID.t(), ability :: atom(), GenServer.server()) ::
          {:ok, Cooldowns.cooldown()}
          | {:error,
             :not_found
             | :out_of_range
             | :missing_ability
             | :on_cooldown
             | :target_dead
             | :no_valid_effects}
  def use_ability(source_id, target_id, ability_id, server \\ __MODULE__)
      when is_atom(ability_id) do
    GenServer.call(server, {:use_ability, source_id, target_id, ability_id})
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
        {:use_ability, source_id, target_id, ability_id},
        _from,
        %__MODULE__{entity_server: entity_server} = state
      )
      when is_atom(ability_id) do
    with {:ok, source} <- EntityServer.get_entity(source_id, entity_server),
         {:ok, target} <- EntityServer.get_entity(target_id, entity_server),
         :ok <- check_alive(target),
         {:ok, ability} <- Abilities.get(ability_id),
         {:has_ability, true} <- {:has_ability, ability_id in source.abilities},
         :ok <- Cooldowns.check(source.cooldowns, ability_id),
         :ok <- check_adjacent(source, target, ability.range) do
      transforms = execute_ability(ability, source, target)

      if transforms == [] do
        {:reply, {:error, :no_valid_effects}, state}
      else
        target_hp_before = Stat.effective(target.stats.hp, target.stats)
        update_fn = build_entity_update_fn(transforms)

        {:ok, target} =
          EntityServer.update_entity(
            target_id,
            update_fn,
            entity_server
          )

        start_cooldown(source_id, ability, entity_server)

        target_hp_after = Stat.effective(target.stats.hp, target.stats)
        damage_taken = target_hp_before - target_hp_after
        broadcast_combat_event(source, target, damage_taken, target_hp_after)

        {:reply, {:ok, {:use_ability, ability.cooldown_ms}}, state}
      end
    else
      {:error, :cooldown} -> {:reply, {:error, :on_cooldown}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
      {:has_ability, false} -> {:reply, {:error, :missing_ability}, state}
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
      transforms
      |> Enum.reduce(entity, fn transform, acc -> transform.(acc) end)
      |> Entity.check_death()
    end
  end

  @doc """
  Broadcasts a combat event on the combat PubSub topic.
  Runs in the caller's process, does not go through the CombatServer GenServer.
  Accepts either an Entity or a UUID for the attacker.
  """
  @spec broadcast_combat_event(
          attacker :: Entity.t() | UUID.t(),
          defender :: Entity.t(),
          dmg :: non_neg_integer(),
          defender_hp :: non_neg_integer()
        ) :: :ok
  def broadcast_combat_event(%Entity{} = attacker, %Entity{} = defender, damage, defender_hp)
      when is_integer(damage) and is_integer(defender_hp) do
    broadcast_combat_event(attacker.id, defender, damage, defender_hp)
  end

  def broadcast_combat_event(attacker_id, %Entity{} = defender, damage, defender_hp)
      when is_uuid(attacker_id) and is_integer(damage) and is_integer(defender_hp) do
    event = %CombatEvent{
      attacker_id: attacker_id,
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

  @spec check_adjacent(Entity.t(), Entity.t(), range :: non_neg_integer()) ::
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

  @spec start_cooldown(UUID.t(), Ability.t(), GenServer.server()) :: :ok
  defp start_cooldown(
         source_id,
         %Ability{id: ability_id, cooldown_ms: cooldown_ms},
         entity_server
       ) do
    # Source may have been removed between the target update and now.
    # Best-effort: if the entity is gone, skip the cooldown.
    case EntityServer.update_entity(
           source_id,
           fn entity ->
             %{entity | cooldowns: Cooldowns.start(entity.cooldowns, ability_id, cooldown_ms)}
           end,
           entity_server
         ) do
      {:ok, _} -> :ok
      {:error, :not_found} -> :ok
    end
  end
end
