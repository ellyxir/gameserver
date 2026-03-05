defmodule Gameserver.WorldServer do
  @moduledoc """
  A named GenServer that tracks which users' presence and location in the world.
  """

  use GenServer

  alias Gameserver.User

  # State: %__MODULE__{users: %{Ecto.UUID.t() => User.t()}}
  defstruct users: %{}

  @typedoc "Error reasons for join/leave operations"
  @type error_reason() :: :already_joined | :not_found

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
  """
  @spec join(User.t(), GenServer.server()) :: :ok | {:error, error_reason()}
  def join(%User{} = user, server \\ __MODULE__) do
    GenServer.call(server, {:join, user})
  end

  @doc """
  Removes a user from the world.
  """
  @spec leave(User.t(), GenServer.server()) :: :ok | {:error, error_reason()}
  def leave(%User{} = user, server \\ __MODULE__) do
    GenServer.call(server, {:leave, user})
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

  # Server callbacks

  @impl GenServer
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl GenServer
  def handle_call({:join, %User{id: id} = user}, _from, %__MODULE__{users: users} = state) do
    if Map.has_key?(users, id) do
      {:reply, {:error, :already_joined}, state}
    else
      {:reply, :ok, %{state | users: Map.put(users, id, user)}}
    end
  end

  @impl GenServer
  def handle_call({:leave, %User{id: id}}, _from, %__MODULE__{users: users} = state) do
    if Map.has_key?(users, id) do
      {:reply, :ok, %{state | users: Map.delete(users, id)}}
    else
      {:reply, {:error, :not_found}, state}
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
end
