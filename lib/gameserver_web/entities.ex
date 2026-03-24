defmodule GameserverWeb.Entities do
  @moduledoc """
  Data collection for tracking entities on the LiveView side.
  Stores players and mobs in a single map keyed by entity id.
  """

  defstruct map: %{}

  alias Gameserver.Entity
  alias Gameserver.Map, as: GameMap
  alias Gameserver.UUID
  alias Gameserver.WorldServer

  @typedoc "Tracks all entities for LiveView rendering"
  @type t() :: %__MODULE__{
          map: %{UUID.t() => WorldServer.world_node()}
        }

  @doc """
  Adds world nodes from `WorldServer.world_nodes/0` format.
  """
  @spec add_world_nodes(t(), %{UUID.t() => WorldServer.world_node()}) :: t()
  def add_world_nodes(%__MODULE__{} = entities, nodes) when is_map(nodes) do
    %__MODULE__{entities | map: Map.merge(entities.map, nodes)}
  end

  @doc """
  Adds a single entity from a PubSub join message.
  """
  @spec add_entity(t(), Entity.t()) :: t()
  def add_entity(%__MODULE__{} = entities, %Entity{id: id} = entity) do
    %__MODULE__{entities | map: Map.put(entities.map, id, WorldServer.world_node(entity))}
  end

  @doc """
  Returns true if the entity exists in the collection.
  """
  @spec has_entity?(t(), UUID.t()) :: boolean()
  def has_entity?(%__MODULE__{} = entities, id) when is_binary(id) do
    Map.has_key?(entities.map, id)
  end

  @doc """
  Returns the position of an entity.
  """
  @spec get_position(t(), UUID.t()) :: {:ok, GameMap.coord()} | :error
  def get_position(%__MODULE__{} = entities, id) when is_binary(id) do
    case Map.get(entities.map, id) do
      %{pos: pos} -> {:ok, pos}
      nil -> :error
    end
  end

  @doc """
  Updates an entity's position.
  """
  @spec update_position(t(), UUID.t(), GameMap.coord()) :: t()
  def update_position(%__MODULE__{} = entities, id, pos) when is_binary(id) do
    %__MODULE__{
      entities
      | map: Map.update!(entities.map, id, fn node -> %{node | pos: pos} end)
    }
  end

  @doc """
  Removes an entity by id.
  """
  @spec remove(t(), UUID.t()) :: t()
  def remove(%__MODULE__{} = entities, id) when is_binary(id) do
    %__MODULE__{entities | map: Map.delete(entities.map, id)}
  end

  @doc """
  Returns ids of players at a given coordinate.
  """
  @spec players_at(t(), GameMap.coord()) :: [UUID.t()]
  def players_at(%__MODULE__{} = entities, coord) do
    for {id, %{type: :user, pos: pos}} <- entities.map, pos == coord, do: id
  end

  @doc """
  Returns the first letter of the mob name at a coordinate,
  or nil if no mob is present. Used as a render helper in templates.
  """
  @spec mob_symbol_at(t(), GameMap.coord()) :: String.t() | nil
  def mob_symbol_at(%__MODULE__{} = entities, coord) do
    Enum.find_value(entities.map, fn
      {_id, %{type: :mob, name: name, pos: pos}} when pos == coord -> String.first(name)
      _ -> nil
    end)
  end

  @doc """
  Returns all player usernames.
  """
  @spec usernames(t()) :: [String.t()]
  def usernames(%__MODULE__{} = entities) do
    for {_id, %{type: :user, name: name}} <- entities.map, do: name
  end
end
