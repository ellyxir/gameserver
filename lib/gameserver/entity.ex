defmodule Gameserver.Entity do
  @moduledoc """
  Represents any entity in the game world — players and mobs alike.

  An entity has a pos on the map, combat stats, and cooldowns.
  The `:type` field distinguishes players (`:user`) from mobs (`:mob`).
  """

  alias Gameserver.BaseStat
  alias Gameserver.Cooldowns
  alias Gameserver.Map, as: GameMap
  alias Gameserver.Stats
  alias Gameserver.UUID

  defstruct [:id, :type, :name, :pos, stats: %Stats{}, cooldowns: %Cooldowns{}]

  @typedoc "Entity type — either a user-controlled player or a server-controlled mob"
  @type entity_type() :: :user | :mob

  @typedoc "An entity in the game world"
  @type t() :: %__MODULE__{
          id: UUID.t(),
          type: entity_type(),
          name: String.t(),
          pos: GameMap.coord() | nil,
          stats: Stats.t(),
          cooldowns: Cooldowns.t()
        }

  @typedoc false
  @typep option() ::
           {:id, UUID.t()}
           | {:type, entity_type()}
           | {:name, String.t()}
           | {:pos, GameMap.coord()}
           | {:stats, Stats.t()}
           | {:cooldowns, Cooldowns.t()}

  @typedoc false
  @typep options() :: [option()]

  @doc """
  Creates a new entity.

  Accepts a keyword list with `:name` and `:type` (generates UUID if `:id` not provided),
  or a `Gameserver.Mob` struct.
  """
  @spec new(Gameserver.Mob.t() | options()) :: t()
  def new(%Gameserver.Mob{} = mob) do
    new(id: mob.id, name: mob.name, type: :mob, pos: mob.spawn_pos)
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
end
