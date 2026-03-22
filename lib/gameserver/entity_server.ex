defmodule Gameserver.EntityServer do
  @moduledoc """
  GenServer to hold all entity data.
  """
  use GenServer

  alias Gameserver.Entity
  alias Gameserver.UUID

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

  @doc """
  Returns an entity by id. Returns `{:ok, entity}` or `{:error, :not_found}`.
  """
  @spec get_entity(UUID.t(), GenServer.server()) :: {:ok, Entity.t()} | {:error, :not_found}
  def get_entity(id, server \\ __MODULE__) when is_binary(id) do
    GenServer.call(server, {:get_entity, id})
  end

  @doc """
  Removes an entity by id. Returns `:ok` or `{:error, :not_found}`.
  """
  @spec remove_entity(UUID.t(), GenServer.server()) :: :ok | {:error, :not_found}
  def remove_entity(id, server \\ __MODULE__) when is_binary(id) do
    GenServer.call(server, {:remove_entity, id})
  end

  # Server callbacks

  @impl GenServer
  def handle_call({:get_entity, id}, _from, state) do
    case Map.get(state, id) do
      nil -> {:reply, {:error, :not_found}, state}
      entity -> {:reply, {:ok, entity}, state}
    end
  end

  def handle_call({:remove_entity, id}, _from, state) do
    if Map.has_key?(state, id) do
      {:reply, :ok, Map.delete(state, id)}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:create_entity, %Entity{id: id} = entity}, _from, state) do
    if Map.has_key?(state, id) do
      {:reply, {:error, :already_exists}, state}
    else
      {:reply, :ok, Map.put(state, id, entity)}
    end
  end
end
