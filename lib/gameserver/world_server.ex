defmodule Gameserver.WorldServer do
  @moduledoc """
  A named GenServer that acts as a spatial index for the game world.

  Validates movement (collision, walls) and maintains entity positions.
  Entity data (stats, cooldowns, identity) is owned by EntityServer.
  """

  use GenServer

  alias Gameserver.Cooldowns
  alias Gameserver.Entity
  alias Gameserver.EntityServer
  alias Gameserver.Map, as: GameMap
  alias Gameserver.User
  alias Gameserver.UUID
  alias Gameserver.WorldServer.StateETS

  defstruct entities: %{},
            map: %GameMap{width: 0, height: 0, tiles: %{}},
            entity_server: EntityServer

  @typedoc "Spatial index entry for collision detection and queries"
  @type world_node() :: %{
          pos: GameMap.coord(),
          type: Entity.entity_type(),
          name: String.t()
        }

  @typep t() :: %__MODULE__{
           entities: %{UUID.t() => world_node()},
           map: GameMap.t(),
           entity_server: GenServer.server()
         }

  @typedoc "what blocked a move — wall, mob, or user at the destination"
  @type obstacle() :: :wall | {:mob, UUID.t()} | {:user, UUID.t()}

  @typedoc "Error reasons for join operations"
  @type join_error() :: :already_joined | :username_not_available | :no_spawn_point | :collision

  @presence_topic "world:presence"
  @movement_topic "world:movement"
  @move_cooldown_ms 150

  # Client API

  @doc """
  Starts the WorldServer. Accepts `:name` and `:entity_server` options.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Adds a user to the world by wrapping them in an entity and assigns them a spawn position.

  Returns `{:ok, position}` on success with the spawn coordinates,
  `{:error, :already_joined}` if the user ID is already in the world,
  or `{:error, :username_not_available}` if another user has the same username.
  """
  @spec join_user(User.t(), GenServer.server()) :: {:ok, GameMap.coord()} | {:error, join_error()}
  def join_user(%User{} = user, server \\ __MODULE__) do
    entity = Entity.new(id: user.id, name: user.username, type: :user)
    GenServer.call(server, {:join_entity, entity})
  end

  @doc """
  Adds an entity directly to the world and assigns a spawn position.

  For `:user` entities, validates username uniqueness and duplicate joins.
  Pre-set positions on user entities are ignored — users always get the spawn point.

  For `:mob` entities, only checks for duplicate ID. If the mob has a pre-set
  `pos`, it is validated (must be a walkable, unoccupied tile). Mobs without
  a pre-set position get the default spawn point.
  """
  @spec join_entity(Entity.t(), GenServer.server()) ::
          {:ok, GameMap.coord()} | {:error, join_error()}
  def join_entity(%Entity{} = entity, server \\ __MODULE__) do
    GenServer.call(server, {:join_entity, entity})
  end

  @doc """
  Removes an entity from the world by id.
  """
  @spec leave(UUID.t(), GenServer.server()) :: :ok | {:error, :not_found}
  def leave(id, server \\ __MODULE__) when is_binary(id) do
    GenServer.call(server, {:leave, id})
  end

  @doc """
  Returns users in the world as `{user_id, username}` tuples.

  - `who()` - returns all users
  - `who(user_id)` - returns matching user or empty list
  - `who([user_ids])` - returns matching users
  """
  @spec who(GenServer.server()) :: [{UUID.t(), User.username()}]
  def who(server \\ __MODULE__) do
    GenServer.call(server, :who)
  end

  @spec who(UUID.t() | [UUID.t()], GenServer.server()) :: [
          {UUID.t(), User.username()}
        ]
  def who(id_or_ids, server) when is_binary(id_or_ids) or is_list(id_or_ids) do
    GenServer.call(server, {:who, id_or_ids})
  end

  @doc """
  Returns all world nodes as a map of `%{id => world_node}`.
  """
  @spec world_nodes(GenServer.server()) :: %{UUID.t() => world_node()}
  def world_nodes(server \\ __MODULE__) do
    GenServer.call(server, :world_nodes)
  end

  @doc """
  Returns the position of an entity by id.
  """
  @spec get_position(UUID.t(), GenServer.server()) ::
          {:ok, GameMap.coord()} | {:error, :not_found}
  def get_position(id, server \\ __MODULE__) when is_binary(id) do
    GenServer.call(server, {:get_position, id})
  end

  @doc """
  Moves an entity one step in the given direction.

  Returns `{:ok, new_position}` on success,
    `{:error, {:collision, destination, obstacle}}` if the destination is blocked,
    `{:error, :cooldown}` if the entity moved too recently,
    `{:error, :not_found}` if the entity is not in the world.
  """
  @spec move(UUID.t(), GameMap.direction(), GenServer.server()) ::
          {:ok, GameMap.coord()}
          | {:error, :not_found | :cooldown | {:collision, GameMap.coord(), obstacle()}}
  def move(id, direction, server \\ __MODULE__) when is_binary(id) do
    GenServer.call(server, {:move, id, direction})
  end

  @doc """
  Returns the PubSub topic for presence updates.

  Subscribe to receive `{:entity_joined, entity}` and `{:entity_left, id}` messages.
  """
  @spec presence_topic() :: String.t()
  def presence_topic, do: @presence_topic

  @doc """
  Returns the PubSub topic for movement updates.

  Subscribe to receive `{:entity_moved, id, position}` messages.
  """
  @spec movement_topic() :: String.t()
  def movement_topic, do: @movement_topic

  @doc """
  Returns the current map from the world.
  """
  @spec get_map(GenServer.server()) :: GameMap.t()
  def get_map(server \\ __MODULE__) do
    GenServer.call(server, :get_map)
  end

  @doc "Returns the movement cooldown duration in milliseconds."
  @spec move_cooldown_ms() :: pos_integer()
  def move_cooldown_ms, do: @move_cooldown_ms

  # Server callbacks

  @default_map_width 30
  @default_map_height 30

  @impl GenServer
  def init(opts) do
    entity_server = Keyword.get(opts, :entity_server, EntityServer)
    state_ets = Keyword.get(opts, :state_ets, StateETS)

    # get seed from stateets in case we crashed
    seed = StateETS.get_seed(state_ets)

    # generate the map
    map =
      Keyword.get(
        opts,
        :map,
        GameMap.generate(@default_map_width, @default_map_height, seed: seed)
      )

    # grab the new seed in case it was changed
    %GameMap{seed: seed} = map

    # save seed to ets
    StateETS.save_seed(seed, state_ets)

    # rebuild user entities, remove orphaned mobs from entityserver
    entities =
      entity_server
      |> EntityServer.list_entities()
      |> Enum.reduce(%{}, fn entity, acc ->
        case entity.type do
          :user ->
            Map.put(acc, entity.id, world_node(entity))

          :mob ->
            EntityServer.remove_entity(entity.id, entity_server)
            acc
        end
      end)

    {:ok, %__MODULE__{map: map, entity_server: entity_server, entities: entities}}
  end

  @impl GenServer
  def handle_call(
        {:join_entity, %Entity{id: id} = entity},
        _from,
        %__MODULE__{entities: entities} = state
      ) do
    with :ok <- check_not_already_joined(entities, id),
         :ok <- check_user_constraints(entities, entity),
         {:ok, pos} <- resolve_spawn_position(entity, state) do
      entity = %{entity | pos: pos}
      :ok = EntityServer.create_entity(entity, state.entity_server)
      broadcast_presence({:entity_joined, entity})
      {:reply, {:ok, pos}, %{state | entities: Map.put(entities, id, world_node(entity))}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:leave, id}, _from, %__MODULE__{entities: entities} = state) do
    case Map.pop(entities, id) do
      {nil, _entities} ->
        {:reply, {:error, :not_found}, state}

      {_world_node, remaining} ->
        :ok = EntityServer.remove_entity(id, state.entity_server)
        broadcast_presence({:entity_left, id})
        {:reply, :ok, %{state | entities: remaining}}
    end
  end

  @impl GenServer
  def handle_call(:who, _from, %__MODULE__{entities: entities} = state) do
    result =
      entities
      |> Enum.filter(fn {_id, entry} -> entry.type == :user end)
      |> Enum.map(fn {id, entry} -> {id, entry.name} end)

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:world_nodes, _from, %__MODULE__{entities: entities} = state) do
    {:reply, entities, state}
  end

  @impl GenServer
  def handle_call({:who, ids}, _from, %__MODULE__{entities: entities} = state)
      when is_list(ids) do
    result =
      Enum.flat_map(ids, fn id ->
        case Map.get(entities, id) do
          %{type: :user, name: name} -> [{id, name}]
          _ -> []
        end
      end)

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:who, id}, _from, %__MODULE__{entities: entities} = state) do
    result =
      case Map.get(entities, id) do
        %{type: :user, name: name} -> [{id, name}]
        _ -> []
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:get_position, id}, _from, %__MODULE__{entities: entities} = state) do
    result =
      case Map.get(entities, id) do
        nil -> {:error, :not_found}
        %{pos: pos} -> {:ok, pos}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(
        {:move, id, direction},
        _from,
        %__MODULE__{entities: entities} = state
      ) do
    with {:ok, world_node} <- get_world_node(entities, id),
         {:ok, entity} <- EntityServer.get_entity(id, state.entity_server),
         :ok <- Cooldowns.check(entity.cooldowns, :move),
         {:ok, destination} <- validate_move(id, world_node, direction, state) do
      :ok = apply_move(id, destination, state)
      new_entities = Map.put(entities, id, %{world_node | pos: destination})
      {:reply, {:ok, destination}, %{state | entities: new_entities}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_map, _from, %__MODULE__{map: map} = state) do
    {:reply, map, state}
  end

  # Private helpers

  @spec apply_move(UUID.t(), GameMap.coord(), t()) :: :ok
  defp apply_move(id, destination, state) do
    update_fn =
      fn e ->
        cooldowns = Cooldowns.start(e.cooldowns, :move, @move_cooldown_ms)
        %{e | pos: destination, cooldowns: cooldowns}
      end

    {:ok, _updated} =
      EntityServer.update_entity(
        id,
        update_fn,
        state.entity_server
      )

    broadcast_movement({:entity_moved, id, destination})
  end

  @doc """
  Converts an entity to a world node.
  """
  @spec world_node(Entity.t()) :: world_node()
  def world_node(%Entity{} = entity) do
    %{pos: entity.pos, type: entity.type, name: entity.name}
  end

  @spec check_not_already_joined(%{UUID.t() => world_node()}, UUID.t()) ::
          :ok | {:error, :already_joined}
  defp check_not_already_joined(entities, id) do
    if Map.has_key?(entities, id), do: {:error, :already_joined}, else: :ok
  end

  @spec check_user_constraints(%{UUID.t() => world_node()}, Entity.t()) ::
          :ok | {:error, :username_not_available}
  defp check_user_constraints(entities, %Entity{type: :user, name: name}) do
    if username_taken?(entities, name), do: {:error, :username_not_available}, else: :ok
  end

  defp check_user_constraints(_entities, %Entity{type: :mob}), do: :ok

  @spec resolve_spawn_position(Entity.t(), t()) ::
          {:ok, GameMap.coord()} | {:error, :no_spawn_point | :collision}
  defp resolve_spawn_position(
         %Entity{type: :mob, pos: pos},
         %__MODULE__{map: map, entities: entities}
       )
       when pos != nil do
    cond do
      GameMap.collision?(map, pos) -> {:error, :collision}
      tile_occupied?(entities, pos) -> {:error, :collision}
      true -> {:ok, pos}
    end
  end

  defp resolve_spawn_position(_entity, %__MODULE__{map: map}), do: GameMap.get_spawn_point(map)

  @spec tile_occupied?(%{UUID.t() => world_node()}, GameMap.coord()) :: boolean()
  defp tile_occupied?(entities, pos) do
    Enum.any?(entities, fn {_id, entry} -> entry.pos == pos end)
  end

  @spec get_world_node(%{UUID.t() => world_node()}, UUID.t()) ::
          {:ok, world_node()} | {:error, :not_found}
  defp get_world_node(entities, id) do
    case Map.get(entities, id) do
      nil -> {:error, :not_found}
      world_node -> {:ok, world_node}
    end
  end

  @spec validate_move(UUID.t(), world_node(), GameMap.direction(), t()) ::
          {:ok, GameMap.coord()} | {:error, {:collision, GameMap.coord(), obstacle()}}
  defp validate_move(id, world_node, direction, %__MODULE__{map: map, entities: entities}) do
    destination = GameMap.interpolate(world_node.pos, direction)

    cond do
      GameMap.collision?(map, world_node.pos, destination) ->
        {:error, {:collision, destination, :wall}}

      blocking = find_blocking_entity(id, world_node.type, destination, entities) ->
        {blocking_id, blocking_entry} = blocking
        {:error, {:collision, destination, {blocking_entry.type, blocking_id}}}

      true ->
        {:ok, destination}
    end
  end

  # Mobs block everything. Players block mobs but not other players.
  @spec find_blocking_entity(
          UUID.t(),
          Entity.entity_type(),
          GameMap.coord(),
          %{UUID.t() => world_node()}
        ) :: {UUID.t(), world_node()} | nil
  defp find_blocking_entity(actor_id, actor_type, destination, entities) do
    Enum.find(entities, fn {id, entry} ->
      id != actor_id and entry.pos == destination and blocks?(entry.type, actor_type)
    end)
  end

  @spec blocks?(Entity.entity_type(), Entity.entity_type()) :: boolean()
  defp blocks?(:mob, _actor_type), do: true
  defp blocks?(:user, :mob), do: true
  defp blocks?(:user, :user), do: false

  @spec username_taken?(%{UUID.t() => world_node()}, String.t()) :: boolean()
  defp username_taken?(entities, name) do
    Enum.any?(entities, fn {_id, entry} -> entry.type == :user and entry.name == name end)
  end

  @spec broadcast_presence({:entity_joined, Entity.t()} | {:entity_left, UUID.t()}) :: :ok
  defp broadcast_presence(message) do
    Phoenix.PubSub.broadcast(Gameserver.PubSub, @presence_topic, message)
  end

  @spec broadcast_movement({:entity_moved, UUID.t(), GameMap.coord()}) :: :ok
  defp broadcast_movement(message) do
    Phoenix.PubSub.broadcast(Gameserver.PubSub, @movement_topic, message)
  end
end
