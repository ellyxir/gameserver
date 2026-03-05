defmodule GameserverWeb.GameLive do
  use GameserverWeb, :live_view

  require Logger

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    login_form = to_form(%{"username" => ""}, as: :login_form)
    {:ok, assign(socket, num_clicks: 1, user: nil, login_form: login_form)}
  end

  @impl Phoenix.LiveView
  def handle_event("inc_clicks", _params, socket) do
    {:noreply, update(socket, :num_clicks, &(&1 + 1))}
  end

  # validate username as user types
  def handle_event("validate", %{"login_form" => %{"username" => username}}, socket) do
    changeset = Gameserver.User.validate_username(username)
    {:noreply, assign(socket, login_form: to_form(changeset, as: :login_form))}
  end

  # "save" button - user wants to use this username
  def handle_event("save", %{"login_form" => %{"username" => username}}, socket) do
    Logger.info("GameLive SAVE event: username #{inspect(username)}")
    {:noreply, assign(socket, user: username)}
  end

  def handle_event(event, params, socket) do
    Logger.info("GameLive got unknown event: #{inspect(event)}, params=#{inspect(params)}")
    {:noreply, socket}
  end
end
