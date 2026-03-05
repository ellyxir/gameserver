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
end
