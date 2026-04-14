defmodule Gameserver.EntityServer do
  @moduledoc """
  GenServer to hold all entity data.
  """
  use GenServer

  alias Gameserver.Effect
  alias Gameserver.Entity
  alias Gameserver.UUID

  @entity_topic "entity:changes"

  @doc """
  Returns the PubSub topic for entity change broadcasts.
  """
  @spec entity_topic() :: String.t()
  def entity_topic, do: @entity_topic

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

  @typedoc false
  @typep option() :: {:name, GenServer.name() | nil}

  @spec start_link([option()]) :: GenServer.on_start()
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

  @doc """
  Applies an update function to an entity. Returns `{:ok, updated_entity}` or
  `{:error, :not_found}`.
  """
  @spec update_entity(UUID.t(), Effect.transform(), GenServer.server()) ::
          {:ok, Entity.t()} | {:error, :not_found | {:update_failed, term()}}
  def update_entity(id, fun, server \\ __MODULE__) when is_binary(id) and is_function(fun, 1) do
    GenServer.call(server, {:update_entity, id, fun})
  end

  @doc """
  Returns all entities.
  """
  @spec list_entities(GenServer.server()) :: [Entity.t()]
  def list_entities(server \\ __MODULE__) do
    GenServer.call(server, :list_entities)
  end

  # Server callbacks

  @impl GenServer
  def handle_call(:list_entities, _from, state) do
    {:reply, Map.values(state), state}
  end

  def handle_call({:get_entity, id}, _from, state) do
    case Map.get(state, id) do
      nil -> {:reply, {:error, :not_found}, state}
      entity -> {:reply, {:ok, entity}, state}
    end
  end

  def handle_call({:update_entity, id, fun}, _from, state) do
    case Map.get(state, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      entity ->
        case safe_apply(fun, [entity]) do
          {:ok, updated} ->
            broadcast({:entity_updated, updated})
            {:reply, {:ok, updated}, Map.put(state, id, updated)}

          {:error, reason} ->
            {:reply, {:error, {:update_failed, reason}}, state}
        end
    end
  end

  def handle_call({:remove_entity, id}, _from, state) do
    if Map.has_key?(state, id) do
      broadcast({:entity_removed, id})
      {:reply, :ok, Map.delete(state, id)}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:create_entity, %Entity{id: id} = entity}, _from, state) do
    if Map.has_key?(state, id) do
      {:reply, {:error, :already_exists}, state}
    else
      broadcast({:entity_created, entity})
      {:reply, :ok, Map.put(state, id, entity)}
    end
  end

  @spec safe_apply(function(), [term()]) :: {:ok, term()} | {:error, term()}
  defp safe_apply(fun, args) do
    {:ok, apply(fun, args)}
  rescue
    e -> {:error, Exception.message(e)}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(Gameserver.PubSub, @entity_topic, message)
  end
end
