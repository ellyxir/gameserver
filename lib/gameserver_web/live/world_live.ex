defmodule GameserverWeb.WorldLive do
  @moduledoc """
  LiveView for the world page, rendering the dungeon map with
  players, mobs, and an online users list. Handles keyboard
  (WASD/arrow) and tile click input for player movement.
  """

  use GameserverWeb, :live_view

  alias Gameserver.Entity
  alias Gameserver.Map, as: GameMap
  alias Gameserver.WorldServer
  alias GameserverWeb.Entities

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    user_id = Map.get(params, "user_id")

    case validate_user(user_id) do
      {:ok, username} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())
          Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.movement_topic())
        end

        nodes = WorldServer.world_nodes()
        entities = Entities.add_world_nodes(%Entities{}, nodes)

        if Entities.has_entity?(entities, user_id) do
          map_cells = WorldServer.get_map() |> GameMap.to_cells()

          {:ok,
           assign(socket,
             user_id: user_id,
             username: username,
             map_cells: map_cells,
             entities: entities
           )}
        else
          {:ok, push_navigate(socket, to: ~p"/game")}
        end

      :error ->
        {:ok, push_navigate(socket, to: ~p"/game")}
    end
  end

  @key_to_direction %{
    "w" => :north,
    "a" => :west,
    "s" => :south,
    "d" => :east,
    "ArrowUp" => :north,
    "ArrowLeft" => :west,
    "ArrowDown" => :south,
    "ArrowRight" => :east
  }

  @impl Phoenix.LiveView
  def handle_event("keydown", %{"key" => key}, socket) do
    case Map.get(@key_to_direction, key) do
      nil -> {:noreply, socket}
      direction -> move_player(socket, direction)
    end
  end

  def handle_event("tile-click", %{"x" => x, "y" => y}, socket) do
    case direction_from(my_position(socket), GameMap.parse_coord(x, y)) do
      nil -> {:noreply, socket}
      direction -> move_player(socket, direction)
    end
  end

  @spec direction_from(GameMap.coord(), GameMap.coord()) :: GameMap.direction() | nil
  defp direction_from(same, same), do: nil

  defp direction_from({fx, fy}, {tx, ty}) do
    dx = tx - fx
    dy = ty - fy

    if abs(dx) >= abs(dy) do
      if dx > 0, do: :east, else: :west
    else
      if dy > 0, do: :south, else: :north
    end
  end

  @spec move_player(Phoenix.LiveView.Socket.t(), GameMap.direction()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp move_player(socket, direction) do
    WorldServer.move(socket.assigns.user_id, direction)
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:entity_joined, %Entity{} = entity}, socket) do
    entities = Entities.add_entity(socket.assigns.entities, entity)
    {:noreply, assign(socket, entities: entities)}
  end

  def handle_info({:entity_moved, id, pos}, socket) do
    entities = socket.assigns.entities

    if Entities.has_entity?(entities, id) do
      {:noreply, assign(socket, entities: Entities.update_position(entities, id, pos))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:entity_left, id}, socket) do
    if id == socket.assigns.user_id do
      {:noreply, push_navigate(socket, to: ~p"/game")}
    else
      entities = Entities.remove(socket.assigns.entities, id)
      {:noreply, assign(socket, entities: entities)}
    end
  end

  @impl Phoenix.LiveView
  def terminate(_reason, socket) do
    case socket.assigns do
      %{user_id: user_id} when is_binary(user_id) ->
        WorldServer.leave(user_id)

      _ ->
        :ok
    end
  end

  @spec my_position(Phoenix.LiveView.Socket.t() | map()) :: GameMap.coord()
  defp my_position(%Phoenix.LiveView.Socket{assigns: assigns}), do: my_position(assigns)

  defp my_position(%{user_id: user_id, entities: entities}) do
    {:ok, position} = Entities.get_position(entities, user_id)
    position
  end

  @spec validate_user(String.t() | nil) :: {:ok, String.t()} | :error
  defp validate_user(nil), do: :error

  defp validate_user(user_id) do
    case WorldServer.who(user_id, WorldServer) do
      [{^user_id, username}] -> {:ok, username}
      [] -> :error
    end
  end
end
