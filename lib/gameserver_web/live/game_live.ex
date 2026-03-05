defmodule GameserverWeb.GameLive do
  @moduledoc """
  LiveView for the login page where users enter their username to join the world.
  """

  use GameserverWeb, :live_view

  alias Gameserver.User
  alias Gameserver.WorldServer

  require Logger

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    login_form = to_form(%{"username" => ""}, as: :login_form)
    {:ok, assign(socket, login_form: login_form)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"login_form" => %{"username" => username}}, socket) do
    changeset = User.validate_username(username)
    {:noreply, assign(socket, login_form: to_form(changeset, as: :login_form))}
  end

  # "save" button - user wants to use this username
  def handle_event("save", %{"login_form" => %{"username" => username}}, socket) do
    with {:ok, user} <- User.new(username),
         :ok <- WorldServer.join(user) do
      {:noreply, push_navigate(socket, to: ~p"/world?user_id=#{user.id}")}
    else
      {:error, :already_joined} ->
        changeset =
          username
          |> User.validate_username()
          |> Ecto.Changeset.add_error(:username, "already joined")

        {:noreply, assign(socket, login_form: to_form(changeset, as: :login_form))}

      {:error, _reason} ->
        changeset = User.validate_username(username)
        {:noreply, assign(socket, login_form: to_form(changeset, as: :login_form))}
    end
  end

  def handle_event(event, params, socket) do
    Logger.warning("GameLive got unknown event: #{inspect(event)}, params=#{inspect(params)}")
    {:noreply, socket}
  end
end
