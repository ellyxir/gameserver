defmodule GameserverWeb.WorldLive do
  @moduledoc """
  LiveView for the world page showing online users.
  """

  use GameserverWeb, :live_view

  alias Gameserver.WorldServer

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    user_id = Map.get(params, "user_id")

    case validate_user(user_id) do
      {:ok, username} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())
        end

        users = WorldServer.who()
        {:ok, assign(socket, user_id: user_id, username: username, users: users)}

      :error ->
        {:ok, push_navigate(socket, to: ~p"/game")}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:user_joined, _user}, socket) do
    users = WorldServer.who()
    {:noreply, assign(socket, users: users)}
  end

  def handle_info({:user_left, user}, socket) do
    if user.id == socket.assigns.user_id do
      {:noreply, push_navigate(socket, to: ~p"/game")}
    else
      users = WorldServer.who()
      {:noreply, assign(socket, users: users)}
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

  @spec validate_user(String.t() | nil) :: {:ok, String.t()} | :error
  defp validate_user(nil), do: :error

  defp validate_user(user_id) do
    case WorldServer.who(user_id, WorldServer) do
      [{^user_id, username}] -> {:ok, username}
      [] -> :error
    end
  end
end
