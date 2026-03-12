defmodule Gameserver.WorldServer do
  @moduledoc """
  A named GenServer that tracks user presence and location in the world.
  """

  use GenServer

  alias Gameserver.Map, as: GameMap
  alias Gameserver.Player
  alias Gameserver.User

  defstruct players: %{}, map: nil

  @typedoc "Error reasons for join operations"
  @type join_error() :: :already_joined | :username_not_available | :no_spawn_point

  @presence_topic "world:presence"
  @movement_topic "world:movement"

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
  Adds a user to the world and assigns them a spawn position.

  Returns `{:ok, position}` on success with the spawn coordinates,
  `{:error, :already_joined}` if the user ID is already in the world,
  or `{:error, :username_not_available}` if another user has the same username.
  """
  @spec join(User.t(), GenServer.server()) :: {:ok, GameMap.coord()} | {:error, join_error()}
  def join(%User{} = user, server \\ __MODULE__) do
    GenServer.call(server, {:join, user})
  end

  @doc """
  Removes a user from the world by user_id.
  """
  @spec leave(Ecto.UUID.t(), GenServer.server()) :: :ok | {:error, :not_found}
  def leave(user_id, server \\ __MODULE__) when is_binary(user_id) do
    GenServer.call(server, {:leave, user_id})
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
  def who(id_or_ids, server) do
    GenServer.call(server, {:who, id_or_ids})
  end

  @doc """
  Returns all players with their positions as `{user_id, username, position}` tuples.
  """
  @spec players(GenServer.server()) :: [{Ecto.UUID.t(), User.username(), GameMap.coord()}]
  def players(server \\ __MODULE__) do
    GenServer.call(server, :players)
  end

  @doc """
  Returns the position of a player by user_id.
  """
  @spec get_position(Ecto.UUID.t(), GenServer.server()) ::
          {:ok, GameMap.coord()} | {:error, :not_found}
  def get_position(user_id, server \\ __MODULE__) when is_binary(user_id) do
    GenServer.call(server, {:get_position, user_id})
  end

  @doc """
  Moves a player one step in the given direction.

  Returns `{:ok, new_position}` on success, `{:error, :collision}` if the
  destination is blocked, or `{:error, :not_found}` if the player is not in the world.
  """
  @spec move(Ecto.UUID.t(), GameMap.direction(), GenServer.server()) ::
          {:ok, GameMap.coord()} | {:error, :not_found | :collision}
  def move(user_id, direction, server \\ __MODULE__) when is_binary(user_id) do
    GenServer.call(server, {:move, user_id, direction})
  end

  @doc """
  Returns the PubSub topic for presence updates.

  Subscribe to receive `{:user_joined, user}` and `{:user_left, user}` messages.
  """
  @spec presence_topic() :: String.t()
  def presence_topic, do: @presence_topic

  @doc """
  Returns the PubSub topic for movement updates.

  Subscribe to receive `{:player_moved, user_id, position}` messages.
  """
  @spec movement_topic() :: String.t()
  def movement_topic, do: @movement_topic

  # Server callbacks

  @impl GenServer
  def init(_opts) do
    {:ok, %__MODULE__{map: GameMap.sample_dungeon()}}
  end

  @impl GenServer
  def handle_call(
        {:join, %User{id: id, username: username} = user},
        _from,
        %__MODULE__{players: players, map: map} = state
      ) do
    cond do
      Map.has_key?(players, id) ->
        {:reply, {:error, :already_joined}, state}

      username_taken?(players, username) ->
        {:reply, {:error, :username_not_available}, state}

      true ->
        case GameMap.get_spawn_point(map) do
          {:ok, position} ->
            player = Player.new(user, position)
            broadcast_presence({:user_joined, user})
            {:reply, {:ok, position}, %{state | players: Map.put(players, id, player)}}

          {:error, :no_spawn_point} ->
            {:reply, {:error, :no_spawn_point}, state}
        end
    end
  end

  @impl GenServer
  def handle_call({:leave, user_id}, _from, %__MODULE__{players: players} = state) do
    case Map.pop(players, user_id) do
      {nil, _players} ->
        {:reply, {:error, :not_found}, state}

      {%Player{user: user}, remaining_players} ->
        broadcast_presence({:user_left, user})
        {:reply, :ok, %{state | players: remaining_players}}
    end
  end

  @impl GenServer
  def handle_call(:who, _from, %__MODULE__{players: players} = state) do
    result =
      players
      |> Map.values()
      |> Enum.map(&player_to_tuple/1)

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:players, _from, %__MODULE__{players: players} = state) do
    result =
      players
      |> Map.values()
      |> Enum.map(&player_to_tuple_with_position/1)

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:who, ids}, _from, %__MODULE__{players: players} = state) when is_list(ids) do
    result =
      Enum.flat_map(ids, fn id ->
        case Map.get(players, id) do
          nil -> []
          player -> [player_to_tuple(player)]
        end
      end)

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:who, id}, _from, %__MODULE__{players: players} = state) do
    result =
      case Map.get(players, id) do
        nil -> []
        player -> [player_to_tuple(player)]
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:get_position, user_id}, _from, %__MODULE__{players: players} = state) do
    result =
      case Map.get(players, user_id) do
        nil -> {:error, :not_found}
        %Player{position: position} -> {:ok, position}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(
        {:move, user_id, direction},
        _from,
        %__MODULE__{players: players, map: map} = state
      ) do
    case Map.get(players, user_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %Player{} = player ->
        case apply_move_and_notify(player, user_id, direction, map) do
          {:ok, %Player{position: destination} = updated_player} ->
            {:reply, {:ok, destination},
             %{state | players: Map.put(players, user_id, updated_player)}}

          {:error, :collision} ->
            {:reply, {:error, :collision}, state}
        end
    end
  end

  # Private helpers

  @spec player_to_tuple(Player.t()) :: {Ecto.UUID.t(), User.username()}
  defp player_to_tuple(%Player{user: %User{id: id, username: username}}) do
    {id, username}
  end

  @spec player_to_tuple_with_position(Player.t()) ::
          {Ecto.UUID.t(), User.username(), GameMap.coord()}
  defp player_to_tuple_with_position(%Player{
         user: %User{id: id, username: username},
         position: position
       }) do
    {id, username, position}
  end

  @spec apply_move_and_notify(Player.t(), Ecto.UUID.t(), GameMap.direction(), GameMap.t()) ::
          {:ok, Player.t()} | {:error, :collision}
  defp apply_move_and_notify(%Player{position: position} = player, user_id, direction, map) do
    destination = GameMap.interpolate(position, direction)

    if GameMap.collision?(map, position, destination) do
      {:error, :collision}
    else
      broadcast_movement({:player_moved, user_id, destination})
      {:ok, %{player | position: destination}}
    end
  end

  @spec username_taken?(%{Ecto.UUID.t() => Player.t()}, User.username()) :: boolean()
  defp username_taken?(players, username) do
    Enum.any?(players, fn {_id, %Player{user: user}} -> user.username == username end)
  end

  @spec broadcast_presence({:user_joined | :user_left, User.t()}) :: :ok
  defp broadcast_presence(message) do
    Phoenix.PubSub.broadcast(Gameserver.PubSub, @presence_topic, message)
  end

  @spec broadcast_movement({:player_moved, Ecto.UUID.t(), GameMap.coord()}) :: :ok
  defp broadcast_movement(message) do
    Phoenix.PubSub.broadcast(Gameserver.PubSub, @movement_topic, message)
  end
end
