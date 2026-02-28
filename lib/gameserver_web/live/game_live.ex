defmodule GameserverWeb.GameLive do
  use GameserverWeb, :live_view

  require Logger

  def mount(_params, _session, socket) do
    username_form = to_form(%{"username" => ""})
    {:ok, assign(socket, num_clicks: 1, user: nil, username_form: username_form)}
  end

  def handle_event("inc_clicks", _params, socket) do
    {:noreply, update(socket, :num_clicks, &(&1 + 1))}
  end

  def handle_event("save", %{"username" => username} = _params, socket) do
    Logger.info("GameLive SAVE event: username #{inspect(username)}")
    {:noreply, assign(socket, user: username)}
  end

  def handle_event(event, params, socket) do
    Logger.info("GameLive got unknown event: #{inspect(event)}, params=#{inspect(params)}")
    {:noreply, socket}
  end
end
