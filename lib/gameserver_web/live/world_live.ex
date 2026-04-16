defmodule GameserverWeb.WorldLive do
  @moduledoc """
  LiveView for the world page, rendering the dungeon map with
  players, mobs, and an online users list. Handles keyboard
  (WASD/arrow) and tile click input for player movement.
  """

  use GameserverWeb, :live_view

  alias Gameserver.Abilities
  alias Gameserver.Ability
  alias Gameserver.CombatEvent
  alias Gameserver.CombatServer
  alias Gameserver.Cooldowns
  alias Gameserver.Entity
  alias Gameserver.EntityServer
  alias Gameserver.Map, as: GameMap
  alias Gameserver.UUID
  alias Gameserver.WorldServer
  alias GameserverWeb.Entities

  @combat_log_limit 50

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    user_id = Map.get(params, "user_id")

    case validate_user(user_id) do
      {:ok, username} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())
          Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.movement_topic())
          Phoenix.PubSub.subscribe(Gameserver.PubSub, CombatServer.combat_topic())
          Phoenix.PubSub.subscribe(Gameserver.PubSub, EntityServer.entity_topic())
        end

        nodes = WorldServer.world_nodes()
        entities = Entities.add_world_nodes(%Entities{}, nodes)

        if Entities.has_entity?(entities, user_id) do
          map_cells = WorldServer.get_map() |> GameMap.to_cells()
          {:ok, entity} = EntityServer.get_entity(user_id)
          abilities = Enum.flat_map(entity.abilities, &resolve_ability/1)

          {:ok,
           socket
           |> assign(
             user_id: user_id,
             username: username,
             map_cells: map_cells,
             entities: entities,
             player_stats: entity.stats,
             player_cooldowns: entity.cooldowns,
             abilities: abilities,
             ability_ready: %{},
             cooldown_refresh_ref: nil,
             target_id: nil
           )
           |> refresh_cooldown_state()
           |> stream(:combat_log, [], limit: -@combat_log_limit)}
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

  def handle_event("use_ability", %{"ability-id" => ability_str}, socket) do
    case Enum.find(socket.assigns.abilities, fn a -> Atom.to_string(a.id) == ability_str end) do
      nil -> {:noreply, socket}
      ability -> invoke_ability(socket, ability)
    end
  end

  @spec invoke_ability(Phoenix.LiveView.Socket.t(), Ability.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp invoke_ability(socket, %Ability{id: id, range: 0}) do
    CombatServer.use_ability(socket.assigns.user_id, socket.assigns.user_id, id)
    {:noreply, socket}
  end

  defp invoke_ability(socket, %Ability{id: id, range: range}) when range > 0 do
    case socket.assigns.target_id do
      nil ->
        {:noreply, socket}

      target_id ->
        CombatServer.use_ability(socket.assigns.user_id, target_id, id)
        {:noreply, socket}
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
    case WorldServer.move(socket.assigns.user_id, direction) do
      {:error, {:collision, _pos, {:mob, mob_id}}} ->
        attack_on_collision(socket, mob_id)

      _ ->
        {:noreply, socket}
    end
  end

  @spec attack_on_collision(Phoenix.LiveView.Socket.t(), UUID.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp attack_on_collision(socket, mob_id) do
    [%Ability{id: id} | _] = socket.assigns.abilities
    CombatServer.use_ability(socket.assigns.user_id, mob_id, id)
    {:noreply, assign(socket, target_id: mob_id)}
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

  def handle_info({:combat_event, %CombatEvent{} = event}, socket) do
    message = format_combat_message(event, socket.assigns)
    entry = %{id: UUID.generate(), message: message}
    {:noreply, stream_insert(socket, :combat_log, entry, limit: -@combat_log_limit)}
  end

  def handle_info(
        {:entity_updated, %Entity{id: id} = entity},
        %{assigns: %{user_id: id}} = socket
      ) do
    {:noreply,
     socket
     |> assign(
       player_stats: entity.stats,
       player_cooldowns: entity.cooldowns
     )
     |> refresh_cooldown_state()}
  end

  def handle_info({:entity_updated, _entity}, socket), do: {:noreply, socket}
  def handle_info({:entity_created, _entity}, socket), do: {:noreply, socket}
  def handle_info({:entity_removed, _id}, socket), do: {:noreply, socket}

  def handle_info(:refresh_cooldowns, socket) do
    {:noreply,
     socket
     |> assign(:cooldown_refresh_ref, nil)
     |> refresh_cooldown_state()}
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

  # Scheduling buffer in ms — a small delay past the cooldown's scheduled end
  # so that `Cooldowns.ready?/2` reliably reports true when we re-render.
  @refresh_buffer_ms 10

  # Recomputes the per-ability ready map from the current cooldowns and reschedules
  # the next self-refresh. Cancels any outstanding refresh first so we don't
  # accumulate timers across rapid `:entity_updated` broadcasts.
  @spec refresh_cooldown_state(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp refresh_cooldown_state(socket) do
    cooldowns = socket.assigns.player_cooldowns

    ability_ready =
      Map.new(socket.assigns.abilities, fn %Ability{id: id} ->
        {id, Cooldowns.ready?(cooldowns, id)}
      end)

    socket
    |> cancel_cooldown_refresh()
    |> assign(:ability_ready, ability_ready)
    |> schedule_next_refresh()
  end

  @spec cancel_cooldown_refresh(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp cancel_cooldown_refresh(socket) do
    case socket.assigns.cooldown_refresh_ref do
      nil ->
        socket

      ref ->
        # If the timer already fired we may still process one stale
        # `:refresh_cooldowns` from the inbox — that's harmless, the
        # handler just recomputes against the current cooldowns.
        Process.cancel_timer(ref)
        assign(socket, :cooldown_refresh_ref, nil)
    end
  end

  @spec schedule_next_refresh(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp schedule_next_refresh(socket) do
    case Cooldowns.next_ready_in_ms(socket.assigns.player_cooldowns) do
      nil ->
        socket

      ms when is_integer(ms) ->
        ref = Process.send_after(self(), :refresh_cooldowns, ms + @refresh_buffer_ms)
        assign(socket, :cooldown_refresh_ref, ref)
    end
  end

  @spec resolve_ability(atom()) :: [Ability.t()]
  defp resolve_ability(ability_id) do
    case Abilities.get(ability_id) do
      {:ok, ability} -> [ability]
      {:error, _} -> []
    end
  end

  @spec my_position(Phoenix.LiveView.Socket.t() | map()) :: GameMap.coord()
  defp my_position(%Phoenix.LiveView.Socket{assigns: assigns}), do: my_position(assigns)

  defp my_position(%{user_id: user_id, entities: entities}) do
    {:ok, position} = Entities.get_position(entities, user_id)
    position
  end

  @spec format_combat_message(CombatEvent.t(), map()) :: String.t()
  defp format_combat_message(%CombatEvent{} = event, assigns) do
    attacker_name = entity_name(assigns, event.attacker_id)
    defender_name = entity_name(assigns, event.defender_id)

    cond do
      event.dead and event.attacker_id == assigns.user_id ->
        "You killed #{defender_name}!"

      event.dead and event.defender_id == assigns.user_id ->
        "#{attacker_name} killed you!"

      event.dead ->
        "#{attacker_name} killed #{defender_name}!"

      event.attacker_id == assigns.user_id ->
        "You hit #{defender_name} for #{event.damage} (#{event.defender_hp} hp)"

      event.defender_id == assigns.user_id ->
        "#{attacker_name} hits you for #{event.damage} (#{event.defender_hp} hp)"

      true ->
        "#{attacker_name} hits #{defender_name} for #{event.damage} (#{event.defender_hp} hp)"
    end
  end

  @spec entity_name(map(), UUID.t()) :: String.t()
  defp entity_name(assigns, id) do
    case Entities.get_name(assigns.entities, id) do
      {:ok, name} -> name
      {:error, :not_found} -> "unknown"
    end
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
