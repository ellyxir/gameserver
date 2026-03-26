defmodule Gameserver.CombatServer do
  @moduledoc """
  handles all things combat
  fairly stateless, mainly acts to ensure everything happens sequentially

  calls out to the WorldServer for world coordinates,
  calls out to EntityServer to read/write stats
  """

  use GenServer

  alias Gameserver.Cooldowns
  alias Gameserver.Entity
  alias Gameserver.EntityServer
  alias Gameserver.UUID
  alias Gameserver.WorldServer

  @typedoc "CombatServer state"
  @type t() :: %__MODULE__{
          entity_server: GenServer.server(),
          world_server: GenServer.server()
        }

  @typedoc "A broadcast combat event with attacker/defender IDs and damage dealt"
  @type combat_event() :: %{
          attacker_id: UUID.t(),
          defender_id: UUID.t(),
          damage: non_neg_integer(),
          defender_hp: non_neg_integer()
        }

  defstruct entity_server: EntityServer,
            world_server: WorldServer

  @doc """
  Starts the combat server. Accepts `:name`, `:entity_server`, and `:world_server` options.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
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
         :ok <- check_adjacent(attacker, defender) do
      defender_hp_before = defender.stats.hp

      {:ok, update_fn} = perform_attack(attacker, defender)

      {:ok, defender} =
        EntityServer.update_entity(
          defender_id,
          update_fn,
          entity_server
        )

      defender_hp_after = defender.stats.hp
      damage_taken = defender_hp_before - defender_hp_after
      broadcast_combat_event(attacker, defender, damage_taken, defender_hp_after)

      {:reply, {:ok, {:attack, @attack_cooldown_ms}}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @doc """
  performs attack, returns the updated attacker and defender entities
  note this is a pure function, doesn't update the entityserver
  """
  @spec perform_attack(Entity.t(), Entity.t()) :: {:ok, EntityServer.entity_transform_function()}
  def perform_attack(%Entity{} = attacker, %Entity{} = _defender) do
    damage = attacker.stats.attack_power

    update_fn = fn e -> %{e | stats: %{e.stats | hp: max(0, e.stats.hp - damage)}} end

    {:ok, update_fn}
  end

  @spec broadcast_combat_event(Entity.t(), Entity.t(), non_neg_integer(), non_neg_integer()) ::
          :ok
  defp broadcast_combat_event(attacker, defender, damage, defender_hp) do
    event = %{
      attacker_id: attacker.id,
      defender_id: defender.id,
      damage: damage,
      defender_hp: defender_hp
    }

    Phoenix.PubSub.broadcast(Gameserver.PubSub, @combat_topic, {:combat_event, event})
  end

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
