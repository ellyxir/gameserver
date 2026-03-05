defmodule GameserverWeb.WorldLive do
  @moduledoc """
  LiveView for the world page showing online users.
  """

  use GameserverWeb, :live_view

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <p>World</p>
    """
  end
end
