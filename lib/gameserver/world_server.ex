defmodule Gameserver.WorldServer do
  @moduledoc """

  A named GenServer that tracks users' presence and location
  """

  use GenServer

  @doc """
  Starts the WorldServer and registers it under its module name.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    {:ok, %{}}
  end
end
