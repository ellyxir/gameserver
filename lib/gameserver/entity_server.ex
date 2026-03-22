defmodule Gameserver.EntityServer do
  @moduledoc """
  GenServer to hold all entity data.
  """
  use GenServer

  alias Gameserver.Entity

  @typedoc """
  map of entity uuids to entities
  """
  @type state() :: %{
          Gameserver.UUID.t() => Gameserver.Entity.t()
        }

  @impl GenServer
  def init(_) do
    {:ok, %{}}
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # Client API

  @doc """
  Stores a new entity. Returns `:ok` or `{:error, :already_exists}`.
  """
  @spec create_entity(Entity.t(), GenServer.server()) :: :ok | {:error, :already_exists}
  def create_entity(%Entity{} = entity, server \\ __MODULE__) do
    GenServer.call(server, {:create_entity, entity})
  end

  # Server callbacks

  @impl GenServer
  def handle_call({:create_entity, %Entity{id: id} = entity}, _from, state) do
    if Map.has_key?(state, id) do
      {:reply, {:error, :already_exists}, state}
    else
      {:reply, :ok, Map.put(state, id, entity)}
    end
  end
end
