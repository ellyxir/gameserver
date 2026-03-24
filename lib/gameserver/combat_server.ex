defmodule Gameserver.CombatServer do
  @moduledoc """
  handles all things combat
  fairly stateless, mainly acts to ensure everything happens sequentially

  calls out to the WorldServer for world coordinates,
  calls out to EntityServer to read/write stats
  """

  use GenServer

  alias Gameserver.Cooldowns
  alias Gameserver.EntityServer
  alias Gameserver.UUID
  alias Gameserver.WorldServer

  @typedoc "CombatServer state"
  @type t() :: %__MODULE__{
          entity_server: GenServer.server(),
          world_server: GenServer.server()
        }

  defstruct entity_server: EntityServer,
            world_server: WorldServer

  @doc """
  Starts the combat server. Accepts `:name`, `:entity_server`, and `:world_server` options.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @attack_cooldown_ms 1000

  @doc """
  Attacks defender with attacker. Validates adjacency, applies damage.

  Returns `{:ok, {:attack, cooldown_ms}}` on success.
  """
  @spec attack(UUID.t(), UUID.t(), GenServer.server()) ::
          {:ok, Cooldowns.cooldown()} | {:error, :not_found | :out_of_range}
  def attack(attacker_id, defender_id, server \\ __MODULE__) do
    GenServer.call(server, {:attack, attacker_id, defender_id})
  end

  # Server callbacks

  @impl GenServer
  def init(args) do
    entity_server = Keyword.get(args, :entity_server, EntityServer)
    world_server = Keyword.get(args, :world_server, WorldServer)
    {:ok, %__MODULE__{entity_server: entity_server, world_server: world_server}}
  end

  @impl GenServer
  def handle_call(
        {:attack, attacker_id, defender_id},
        _from,
        %__MODULE__{entity_server: entity_server, world_server: world_server} = state
      ) do
    with {:ok, attacker} <- EntityServer.get_entity(attacker_id, entity_server),
         {:ok, _defender} <- EntityServer.get_entity(defender_id, entity_server),
         :ok <- check_adjacent(attacker_id, defender_id, world_server) do
      damage = attacker.stats.attack_power

      {:ok, _updated} =
        EntityServer.update_entity(
          defender_id,
          fn e -> %{e | stats: %{e.stats | hp: max(0, e.stats.hp - damage)}} end,
          entity_server
        )

      {:reply, {:ok, {:attack, @attack_cooldown_ms}}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @spec check_adjacent(UUID.t(), UUID.t(), GenServer.server()) ::
          :ok | {:error, :out_of_range | :not_found}
  defp check_adjacent(attacker_id, defender_id, world_server) do
    with {:ok, {ax, ay}} <- WorldServer.get_position(attacker_id, world_server),
         {:ok, {dx, dy}} <- WorldServer.get_position(defender_id, world_server) do
      if abs(ax - dx) <= 1 and abs(ay - dy) <= 1 do
        :ok
      else
        {:error, :out_of_range}
      end
    end
  end
end
