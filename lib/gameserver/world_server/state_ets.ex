defmodule Gameserver.WorldServer.StateETS do
  @moduledoc """
  process to store world server seed in ETS
  this is used to reconstruct the map should the world server crash
  """
  use GenServer

  @ets_table :world_state
  @ets_key :seed

  defstruct [:ets_table_ref]

  @typedoc "ETS holder state containing the table reference"
  @type t() :: %__MODULE__{
          ets_table_ref: :ets.tid() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Persists the map generation seed."
  @spec save_seed(integer(), GenServer.server()) :: :ok
  def save_seed(seed, server \\ __MODULE__) do
    GenServer.call(server, {:save_seed, seed})
  end

  @doc "Returns the stored map generation seed."
  @spec get_seed(GenServer.server()) :: integer() | nil
  def get_seed(server \\ __MODULE__) do
    GenServer.call(server, :get_seed)
  end

  @impl GenServer
  @spec init(keyword()) :: {:ok, t(), {:continue, :setup}}
  def init(_opts) do
    {:ok, %__MODULE__{}, {:continue, :setup}}
  end

  @impl GenServer
  def handle_continue(:setup, state) do
    # set up ETS
    tid = :ets.new(@ets_table, [:public, :set])
    {:noreply, %{state | ets_table_ref: tid}}
  end

  @impl GenServer
  def handle_call({:save_seed, seed}, _from, %__MODULE__{ets_table_ref: tid} = state) do
    :ets.insert(tid, {@ets_key, seed})
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:get_seed, _from, %__MODULE__{ets_table_ref: tid} = state) do
    case :ets.lookup(tid, @ets_key) do
      [{@ets_key, seed}] ->
        {:reply, seed, state}

      [] ->
        {:reply, nil, state}
    end
  end
end
