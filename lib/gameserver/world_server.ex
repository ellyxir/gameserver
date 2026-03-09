defmodule Gameserver.WorldServer do
  @moduledoc """
  A named GenServer that tracks user presence and location in the world.
  """

  use GenServer

  alias Gameserver.User

  # State: %__MODULE__{users: %{Ecto.UUID.t() => User.t()}}
  defstruct users: %{}

  @typedoc "Error reasons for join/leave operations"
  @type error_reason() :: :already_joined | :not_found | :username_not_available

  @presence_topic "world:presence"

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
  Adds a user to the world.

  Returns `{:error, :already_joined}` if the user ID is already in the world,
  or `{:error, :username_not_available}` if another user has the same username.
  """
  @spec join(User.t(), GenServer.server()) :: :ok | {:error, error_reason()}
  def join(%User{} = user, server \\ __MODULE__) do
    GenServer.call(server, {:join, user})
  end

  @doc """
  Removes a user from the world by user_id.
  """
  @spec leave(Ecto.UUID.t(), GenServer.server()) :: :ok | {:error, error_reason()}
  def leave(user_id, server \\ __MODULE__) when is_binary(user_id) do
    GenServer.call(server, {:leave, user_id})
  end

  @doc """
  Returns users in the world as `{user_id, username}` tuples.

  - `who()` - returns all users
  - `who(user_id)` - returns matching user or empty list
  - `who([user_ids])` - returns matching users
  """
  @spec who(GenServer.server()) :: [{Ecto.UUID.t(), String.t()}]
  def who(server \\ __MODULE__) do
    GenServer.call(server, :who)
  end

  @spec who(Ecto.UUID.t() | [Ecto.UUID.t()], GenServer.server()) :: [{Ecto.UUID.t(), String.t()}]
  def who(id_or_ids, server) do
    GenServer.call(server, {:who, id_or_ids})
  end

  @doc """
  Returns the PubSub topic for presence updates.

  Subscribe to receive `{:user_joined, user}` and `{:user_left, user}` messages.
  """
  @spec presence_topic() :: String.t()
  def presence_topic, do: @presence_topic

  # Server callbacks

  @impl GenServer
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl GenServer
  def handle_call(
        {:join, %User{id: id, username: username} = user},
        _from,
        %__MODULE__{users: users} = state
      ) do
    cond do
      Map.has_key?(users, id) ->
        {:reply, {:error, :already_joined}, state}

      username_taken?(users, username) ->
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
  def handle_call({:leave, user_id}, _from, %__MODULE__{users: users} = state) do
    case Map.pop(users, user_id) do
      {nil, _users} ->
        {:reply, {:error, :not_found}, state}

      {user, remaining_users} ->
        broadcast_presence({:user_left, user})
        {:reply, :ok, %{state | users: remaining_users}}
    end
  end

  @impl GenServer
  def handle_call(:who, _from, %__MODULE__{users: users} = state) do
    result =
      users
      |> Map.values()
      |> Enum.map(fn %User{id: id, username: username} -> {id, username} end)

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:who, ids}, _from, %__MODULE__{users: users} = state) when is_list(ids) do
    result =
      Enum.flat_map(ids, fn id ->
        case Map.get(users, id) do
          nil -> []
          %User{id: user_id, username: username} -> [{user_id, username}]
        end
      end)

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:who, id}, _from, %__MODULE__{users: users} = state) do
    result =
      case Map.get(users, id) do
        nil -> []
        %User{id: user_id, username: username} -> [{user_id, username}]
      end

    {:reply, result, state}
  end

  # Private helpers

  @spec username_taken?(%{Ecto.UUID.t() => User.t()}, String.t()) :: boolean()
  defp username_taken?(users, username) do
    Enum.any?(users, fn {_id, user} -> user.username == username end)
  end

  @spec broadcast_presence({:user_joined | :user_left, User.t()}) :: :ok
  defp broadcast_presence(message) do
    Phoenix.PubSub.broadcast(Gameserver.PubSub, @presence_topic, message)
  end
end
