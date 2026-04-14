defmodule Gameserver.TickServer do
  @moduledoc """
  Schedules and executes ticks for all entities.

  Subscribes to entity changes via PubSub. When an entity gains a new tick,
  TickServer schedules `Process.send_after` timers to run the tick's transform
  on the configured interval. This keeps tick scheduling in one place rather
  than duplicating it across Mob, player, and future entity types.
  """

  use GenServer

  alias Gameserver.Effect
  alias Gameserver.Entity
  alias Gameserver.EntityServer
  alias Gameserver.Tick
  alias Gameserver.UUID

  defstruct entity_server: EntityServer, tick_owners: %{}

  @typedoc "TickServer state"
  @type t() :: %__MODULE__{
          entity_server: GenServer.server(),
          tick_owners: %{(tick_id :: UUID.t()) => entity_id :: UUID.t()}
        }

  @typep option() :: {:name, GenServer.name() | nil} | {:entity_server, GenServer.server()}

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {entity_server, opts} = Keyword.pop(opts, :entity_server, EntityServer)
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, entity_server, name: name)
  end

  @impl GenServer
  @spec init(GenServer.server()) :: {:ok, t()}
  def init(entity_server) do
    Phoenix.PubSub.subscribe(Gameserver.PubSub, EntityServer.entity_topic())
    {:ok, %__MODULE__{entity_server: entity_server}}
  end

  # PubSub: EntityServer broadcasts {:entity_updated, entity} on every update.
  # We check for new ticks and schedule timers for them.
  @impl GenServer
  def handle_info({:entity_updated, %Entity{id: entity_id, ticks: ticks}}, state) do
    new_tick_ids =
      ticks
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(state.tick_owners, &1))

    Enum.each(new_tick_ids, fn tick_id ->
      tick = Map.fetch!(ticks, tick_id)
      Process.send_after(self(), {:tick, tick_id, tick.repeat_ms}, tick.repeat_ms)

      if tick.kill_after_ms do
        Process.send_after(self(), {:kill_tick, tick_id}, tick.kill_after_ms)
      end
    end)

    new_owners = Map.new(new_tick_ids, &{&1, entity_id})
    {:noreply, %{state | tick_owners: Map.merge(state.tick_owners, new_owners)}}
  end

  def handle_info({:tick, tick_id, repeat_ms}, state) do
    case Map.fetch(state.tick_owners, tick_id) do
      {:ok, entity_id} ->
        execute_tick(tick_id, entity_id, repeat_ms, state)

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:kill_tick, tick_id}, state) do
    case Map.pop(state.tick_owners, tick_id) do
      {nil, _owners} ->
        {:noreply, state}

      {entity_id, remaining} ->
        EntityServer.update_entity(
          entity_id,
          &Entity.remove_tick(&1, tick_id),
          state.entity_server
        )

        {:noreply, %{state | tick_owners: remaining}}
    end
  end

  def handle_info({:entity_created, _entity}, state), do: {:noreply, state}
  def handle_info({:entity_removed, _id}, state), do: {:noreply, state}

  @spec execute_tick(UUID.t(), UUID.t(), pos_integer(), t()) ::
          {:noreply, t()}
  defp execute_tick(tick_id, entity_id, repeat_ms, state) do
    result =
      EntityServer.update_entity(
        entity_id,
        build_tick_update_fn(tick_id),
        state.entity_server
      )

    case result do
      {:ok, updated} when is_map_key(updated.ticks, tick_id) ->
        Process.send_after(self(), {:tick, tick_id, repeat_ms}, repeat_ms)
        {:noreply, state}

      _stopped_or_error ->
        {:noreply, %{state | tick_owners: Map.delete(state.tick_owners, tick_id)}}
    end
  end

  @spec build_tick_update_fn(UUID.t()) :: Effect.transform()
  defp build_tick_update_fn(tick_id) do
    fn entity ->
      case Map.fetch(entity.ticks, tick_id) do
        {:ok, %Tick{transform: transform}} -> apply_transform(transform, entity, tick_id)
        :error -> entity
      end
    end
  end

  @spec apply_transform(Tick.transform(), Entity.t(), UUID.t()) :: Entity.t()
  defp apply_transform(transform, entity, tick_id) do
    case transform.(entity) do
      {entity, :continue} -> entity
      {entity, :stop} -> Entity.remove_tick(entity, tick_id)
    end
  end
end
