defmodule GameserverWeb.WorldLive do
  @moduledoc """
  LiveView for the world page, rendering the dungeon map with
  the player's position and online users list. Handles keyboard
  (WASD/arrow) and tile click input for player movement.
  """

  use GameserverWeb, :live_view

  require Logger

  alias Gameserver.Entity
  alias Gameserver.Map, as: GameMap
  alias Gameserver.User
  alias Gameserver.WorldServer

  # All player positions keyed by user_id.
  @typep player_positions() :: %{Ecto.UUID.t() => {User.username(), GameMap.coord()}}

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    user_id = Map.get(params, "user_id")

    case validate_user(user_id) do
      {:ok, username} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())
          Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.movement_topic())
        end

        all_players = WorldServer.players()

        player_positions =
          Map.new(all_players, fn {%User{id: id, username: uname}, pos} -> {id, {uname, pos}} end)

        if Map.has_key?(player_positions, user_id) do
          map_cells = WorldServer.get_map() |> GameMap.to_cells()

          {:ok,
           assign(socket,
             user_id: user_id,
             username: username,
             map_cells: map_cells,
             player_positions: player_positions
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
  def handle_info({:entity_joined, %Entity{type: :user} = entity}, socket) do
    player_positions =
      Map.put(socket.assigns.player_positions, entity.id, {entity.name, entity.pos})

    {:noreply, assign(socket, player_positions: player_positions)}
  end

  def handle_info({:entity_joined, %Entity{type: type}}, socket) do
    Logger.warning("unhandled entity_joined for type #{type}")
    {:noreply, socket}
  end

  def handle_info({:entity_moved, id, pos}, socket) do
    if Map.has_key?(socket.assigns.player_positions, id) do
      player_positions = put_position(socket.assigns.player_positions, id, pos)
      {:noreply, assign(socket, player_positions: player_positions)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:entity_left, id}, socket) do
    if id == socket.assigns.user_id do
      {:noreply, push_navigate(socket, to: ~p"/game")}
    else
      player_positions = Map.delete(socket.assigns.player_positions, id)
      {:noreply, assign(socket, player_positions: player_positions)}
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

  defp my_position(%{user_id: user_id, player_positions: player_positions}) do
    {_username, position} = player_positions[user_id]
    position
  end

  @spec put_position(player_positions(), Ecto.UUID.t(), GameMap.coord()) :: player_positions()
  defp put_position(player_positions, user_id, position) do
    Map.update!(player_positions, user_id, fn {username, _old} -> {username, position} end)
  end

  @spec players_at(player_positions(), GameMap.coord()) :: [Ecto.UUID.t()]
  defp players_at(player_positions, coord) do
    for {id, {_username, pos}} <- player_positions, pos == coord, do: id
  end

  @spec usernames(player_positions()) :: [User.username()]
  defp usernames(player_positions) do
    for {_id, {username, _pos}} <- player_positions, do: username
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
