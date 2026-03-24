defmodule Gameserver.CombatServer do
  @moduledoc """
  A named GenServer, handles all combat

  Uses EntityServer to hold game stats for each entity (mobs/players)
  """

  use GenServer

  alias Gameserver.EntityServer
  alias Gameserver.WorldServer

  defstruct entity_server: EntityServer,
            world_server: WorldServer

  @doc """
  starts the combat server
  can pass in optional :name for genserver, :entity_server, and :world_server
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(args) do
    entity_server = Keyword.get(args, :entity_server, EntityServer)
    world_server = Keyword.get(args, :world_server, WorldServer)
    {:ok, %__MODULE__{entity_server: entity_server, world_server: world_server}}
  end
end
