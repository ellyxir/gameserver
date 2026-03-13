defmodule Gameserver.WorldServer do
  @moduledoc """
  A named GenServer that tracks entity presence and location in the world.
  """

  use GenServer

  alias Gameserver.Cooldowns
  alias Gameserver.Entity
  alias Gameserver.Map, as: GameMap
  alias Gameserver.User

  defstruct entities: %{}, map: nil

  @typedoc "Error reasons for join operations"
  @type join_error() :: :already_joined | :username_not_available | :no_spawn_point

  @presence_topic "world:presence"
  @movement_topic "world:movement"
  @move_cooldown_ms 150

  # Client API

  @doc """
  Starts the WorldServer. Accepts `:name` option, defaults to module name.
  During unit tests we start up without the name so that we can reset.
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
  For `:mob` entities, only checks for duplicate ID.
  """
  @spec join_entity(Entity.t(), GenServer.server()) ::
          {:ok, GameMap.coord()} | {:error, join_error()}
  def join_entity(%Entity{} = entity, server \\ __MODULE__) do
    GenServer.call(server, {:join_entity, entity})
  end

  @doc """
  Removes an entity from the world by id.
  """
  @spec leave(Ecto.UUID.t(), GenServer.server()) :: :ok | {:error, :not_found}
  def leave(id, server \\ __MODULE__) when is_binary(id) do
    GenServer.call(server, {:leave, id})
  end

  @doc """
  Returns users in the world as `{user_id, username}` tuples.

  - `who()` - returns all users
  - `who(user_id)` - returns matching user or empty list
  - `who([user_ids])` - returns matching users
  """
  @spec who(GenServer.server()) :: [{Ecto.UUID.t(), User.username()}]
  def who(server \\ __MODULE__) do
    GenServer.call(server, :who)
  end

  @spec who(Ecto.UUID.t() | [Ecto.UUID.t()], GenServer.server()) :: [
          {Ecto.UUID.t(), User.username()}
        ]
  def who(id_or_ids, server) when is_binary(id_or_ids) or is_list(id_or_ids) do
    GenServer.call(server, {:who, id_or_ids})
  end

  @doc """
  Returns all user-type entities as `{user, position}` tuples.
  """
  @spec players(GenServer.server()) :: [{User.t(), GameMap.coord()}]
  def players(server \\ __MODULE__) do
    GenServer.call(server, :players)
  end

  @doc """
  Returns the position of an entity by id.
  """
  @spec get_position(Ecto.UUID.t(), GenServer.server()) ::
          {:ok, GameMap.coord()} | {:error, :not_found}
  def get_position(id, server \\ __MODULE__) when is_binary(id) do
    GenServer.call(server, {:get_position, id})
  end

  @doc """
  Moves an entity one step in the given direction.

  Returns `{:ok, new_position}` on success,
    `{:error, :collision}` if the destination is blocked,
    `{:error, :cooldown}` if the entity moved too recently,
    `{:error, :not_found}` if the entity is not in the world.
  """
  @spec move(Ecto.UUID.t(), GameMap.direction(), GenServer.server()) ::
          {:ok, GameMap.coord()} | {:error, :not_found | :collision | :cooldown}
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

  @impl GenServer
  def init(_opts) do
    {:ok, %__MODULE__{map: GameMap.sample_dungeon()}}
  end

  @impl GenServer
  def handle_call(
        {:join_entity, %Entity{id: id} = entity},
        _from,
        %__MODULE__{entities: entities, map: map} = state
      ) do
    with :ok <- check_not_already_joined(entities, id),
         :ok <- check_user_constraints(entities, entity),
         {:ok, pos} <- GameMap.get_spawn_point(map) do
      entity = %{entity | pos: pos}
      broadcast_presence({:entity_joined, entity})
      {:reply, {:ok, pos}, %{state | entities: Map.put(entities, id, entity)}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:leave, id}, _from, %__MODULE__{entities: entities} = state) do
    case Map.pop(entities, id) do
      {nil, _entities} ->
        {:reply, {:error, :not_found}, state}

      {%Entity{} = entity, remaining} ->
        broadcast_presence({:entity_left, entity.id})
        {:reply, :ok, %{state | entities: remaining}}
    end
  end

  @impl GenServer
  def handle_call(:who, _from, %__MODULE__{entities: entities} = state) do
    result =
      entities
      |> users()
      |> Enum.map(&entity_to_tuple/1)

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:players, _from, %__MODULE__{entities: entities} = state) do
    result =
      entities
      |> users()
      |> Enum.map(&entity_to_user_pos/1)

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:who, ids}, _from, %__MODULE__{entities: entities} = state)
      when is_list(ids) do
    result =
      Enum.flat_map(ids, fn id ->
        case Map.get(entities, id) do
          %Entity{type: :user} = entity -> [entity_to_tuple(entity)]
          _ -> []
        end
      end)

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:who, id}, _from, %__MODULE__{entities: entities} = state) do
    result =
      case Map.get(entities, id) do
        %Entity{type: :user} = entity -> [entity_to_tuple(entity)]
        _ -> []
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:get_position, id}, _from, %__MODULE__{entities: entities} = state) do
    result =
      case Map.get(entities, id) do
        nil -> {:error, :not_found}
        %Entity{pos: pos} -> {:ok, pos}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(
        {:move, id, direction},
        _from,
        %__MODULE__{entities: entities, map: map} = state
      ) do
    with {:ok, entity} <- get_entity(entities, id),
         :ok <- Cooldowns.check(entity.cooldowns, :move),
         {:ok, updated} <- apply_move_and_notify(entity, direction, map) do
      new_state = %{state | entities: Map.put(entities, id, updated)}
      {:reply, {:ok, updated.pos}, new_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_map, _from, %__MODULE__{map: map} = state) do
    {:reply, map, state}
  end

  # Private helpers

  @spec check_not_already_joined(%{Ecto.UUID.t() => Entity.t()}, Ecto.UUID.t()) ::
          :ok | {:error, :already_joined}
  defp check_not_already_joined(entities, id) do
    if Map.has_key?(entities, id), do: {:error, :already_joined}, else: :ok
  end

  @spec check_user_constraints(%{Ecto.UUID.t() => Entity.t()}, Entity.t()) ::
          :ok | {:error, :username_not_available}
  defp check_user_constraints(entities, %Entity{type: :user, name: name}) do
    if username_taken?(entities, name), do: {:error, :username_not_available}, else: :ok
  end

  defp check_user_constraints(_entities, %Entity{type: :mob}), do: :ok

  @spec get_entity(%{Ecto.UUID.t() => Entity.t()}, Ecto.UUID.t()) ::
          {:ok, Entity.t()} | {:error, :not_found}
  defp get_entity(entities, id) do
    case Map.get(entities, id) do
      nil -> {:error, :not_found}
      %Entity{} = entity -> {:ok, entity}
    end
  end

  @spec users(%{Ecto.UUID.t() => Entity.t()}) :: [Entity.t()]
  defp users(entities) do
    entities
    |> Map.values()
    |> Enum.filter(&(&1.type == :user))
  end

  @spec entity_to_tuple(Entity.t()) :: {Ecto.UUID.t(), String.t()}
  defp entity_to_tuple(%Entity{id: id, name: name}), do: {id, name}

  @spec entity_to_user_pos(Entity.t()) :: {User.t(), GameMap.coord()}
  defp entity_to_user_pos(%Entity{id: id, name: name, pos: pos}) do
    {:ok, user} = User.new(id: id, username: name)
    {user, pos}
  end

  @spec apply_move_and_notify(Entity.t(), GameMap.direction(), GameMap.t()) ::
          {:ok, Entity.t()} | {:error, :collision}
  defp apply_move_and_notify(%Entity{pos: pos} = entity, direction, map) do
    destination = GameMap.interpolate(pos, direction)

    if GameMap.collision?(map, pos, destination) do
      {:error, :collision}
    else
      broadcast_movement({:entity_moved, entity.id, destination})
      updated_cooldowns = Cooldowns.start(entity.cooldowns, :move, @move_cooldown_ms)
      {:ok, %{entity | pos: destination, cooldowns: updated_cooldowns}}
    end
  end

  @spec username_taken?(%{Ecto.UUID.t() => Entity.t()}, String.t()) :: boolean()
  defp username_taken?(entities, name) do
    Enum.any?(entities, fn {_id, entity} -> entity.type == :user and entity.name == name end)
  end

  @spec broadcast_presence({:entity_joined, Entity.t()} | {:entity_left, Ecto.UUID.t()}) :: :ok
  defp broadcast_presence(message) do
    Phoenix.PubSub.broadcast(Gameserver.PubSub, @presence_topic, message)
  end

  @spec broadcast_movement({:entity_moved, Ecto.UUID.t(), GameMap.coord()}) :: :ok
  defp broadcast_movement(message) do
    Phoenix.PubSub.broadcast(Gameserver.PubSub, @movement_topic, message)
  end
end
