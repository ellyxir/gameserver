defmodule Gameserver.Entity do
  @moduledoc """
  Represents any entity in the game world — players and mobs alike.

  An entity has a pos on the map, combat stats, and cooldowns.
  The `:type` field distinguishes players (`:user`) from mobs (`:mob`).
  """

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

  @doc """
  Creates a new entity.

  Accepts a keyword list with `:name` and `:type` (generates UUID if `:id` not provided),
  or a `Gameserver.Mob` struct.
  """
  @spec new(Gameserver.Mob.t() | keyword()) :: t()
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
end
