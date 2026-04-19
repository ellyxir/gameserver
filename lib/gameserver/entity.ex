defmodule Gameserver.Entity do
  @moduledoc """
  Represents any entity in the game world — players and mobs alike.

  An entity has a pos on the map, combat stats, and cooldowns.
  The `:type` field distinguishes players (`:user`) from mobs (`:mob`).
  """

  alias Gameserver.BaseStat
  alias Gameserver.Cooldowns
  alias Gameserver.Map, as: GameMap
  alias Gameserver.Stat
  alias Gameserver.Stats
  alias Gameserver.Tick
  alias Gameserver.UUID

  defstruct [
    :id,
    :type,
    :name,
    :pos,
    stats: %Stats{},
    abilities: [],
    cooldowns: %Cooldowns{},
    ticks: %{}
  ]

  @typedoc "Entity type — either a user-controlled player or a server-controlled mob"
  @type entity_type() :: :user | :mob

  @typedoc "Ability ids that can be looked up via `Abilities.get/1`"
  @type ability_list() :: [atom()]

  @typedoc "An entity in the game world"
  @type t() :: %__MODULE__{
          id: UUID.t(),
          type: entity_type(),
          name: String.t(),
          pos: GameMap.coord() | nil,
          stats: Stats.t(),
          abilities: ability_list(),
          cooldowns: Cooldowns.t(),
          ticks: %{UUID.t() => Tick.t()}
        }

  @typedoc false
  @typep option() ::
           {:id, UUID.t()}
           | {:type, entity_type()}
           | {:name, String.t()}
           | {:pos, GameMap.coord()}
           | {:stats, Stats.t()}
           | {:abilities, [atom()]}
           | {:cooldowns, Cooldowns.t()}
           | {:ticks, %{UUID.t() => Tick.t()}}

  @typedoc false
  @typep options() :: [option()]

  @doc """
  Creates a new entity.

  Accepts a keyword list with `:name` and `:type` (generates UUID if `:id` not provided),
  or a `Gameserver.Mob` struct.
  """
  @spec new(Gameserver.Mob.t() | options()) :: t()
  def new(%Gameserver.Mob{} = mob) do
    new(id: mob.id, name: mob.name, type: :mob, pos: mob.spawn_pos, abilities: mob.abilities)
  end

  def new(opts) do
    opts = Keyword.put_new_lazy(opts, :id, &UUID.generate/0)
    struct!(__MODULE__, opts)
  end

  @doc """
  Returns the entity's id.
  """
  @spec id(t()) :: UUID.t()
  def id(%__MODULE__{id: id}), do: id

  @doc """
  Adds a tick to this entity's ticks map.
  """
  @spec register_tick(t(), Tick.t()) :: t()
  def register_tick(%__MODULE__{ticks: ticks} = entity, %Tick{id: id} = tick) do
    %{entity | ticks: Map.put(ticks, id, tick)}
  end

  @doc """
  Removes a tick by id and runs its `on_kill` cleanup function.
  Returns the entity unchanged if the tick id is not found.
  """
  @spec remove_tick(t(), UUID.t()) :: t()
  def remove_tick(%__MODULE__{ticks: ticks} = entity, tick_id) do
    case Map.pop(ticks, tick_id) do
      {nil, _ticks} -> entity
      {%Tick{on_kill: on_kill}, remaining} -> on_kill.(%{entity | ticks: remaining})
    end
  end

  @doc """
  Returns the tick, :error if not found
  """
  @spec get_tick(t(), tick_id :: UUID.t()) :: {:ok, Tick.t()} | :error
  def get_tick(%__MODULE__{ticks: ticks} = _entity, tick_id) do
    Map.fetch(ticks, tick_id)
  end

  @doc """
  Adds a bonus to a `BaseStat` field on this entity.
  Returns the updated entity and the generated bonus id.
  """
  @spec add_stat_bonus(t(), atom(), integer()) :: {t(), effect_id :: UUID.t()}
  def add_stat_bonus(%__MODULE__{} = entity, stat, amount) do
    current_stat = Map.fetch!(entity.stats, stat)
    {updated_stat, id} = BaseStat.add_bonus(current_stat, amount)
    {%{entity | stats: Map.put(entity.stats, stat, updated_stat)}, id}
  end

  @doc """
  Removes a bonus from a `BaseStat` field on this entity by bonus id.
  """
  @spec remove_stat_bonus(t(), atom(), effect_id :: UUID.t()) :: t()
  def remove_stat_bonus(%__MODULE__{} = entity, stat, id) when is_binary(id) do
    current_stat = Map.fetch!(entity.stats, stat)
    updated_stat = BaseStat.remove_bonus(current_stat, id)
    %{entity | stats: Map.put(entity.stats, stat, updated_stat)}
  end

  @doc """
  Convenience function, returns :ok if entity can move
  dead mobs/players cannot move
  """
  @spec can_move(t()) :: :ok | {:error, :dead}
  def can_move(%__MODULE__{stats: %Stats{dead: true}}), do: {:error, :dead}
  def can_move(%__MODULE__{stats: %Stats{dead: false}}), do: :ok

  @doc """
  Marks the entity dead if effective HP has reached zero.
  Already-dead entities stay dead. Sticky — never resurrects.
  """
  @spec check_death(t()) :: t()
  def check_death(%__MODULE__{stats: stats} = entity) do
    dead = stats.dead || Stat.effective(stats.hp, stats) <= 0
    %{entity | stats: %{stats | dead: dead}}
  end
end
