defmodule GameserverWeb.GameLive do
  use GameserverWeb, :live_view

  def mount(_params, _session, socket) do
    clicks = 1
    {:ok, assign(socket, :num_clicks, clicks)}
  end

  def handle_event("inc_clicks", _params, socket) do
    {:noreply, update(socket, :num_clicks, &(&1 + 1))}
  end
end
