defmodule Gameserver.WorldServer.StateETS do
  @moduledoc """
  Holds the WorldServer map seed in an ETS table that survives WorldServer
  crashes under rest_for_one supervision.
  """
  use GenServer

  @ets_table :seed_table
  @ets_key :seed

  defstruct [:ets_table_ref]

  @typedoc "ETS holder state containing the table reference"
  @type t() :: %__MODULE__{
          ets_table_ref: :ets.tid() | nil
        }

  @typedoc false
  @typep option() :: {:name, GenServer.name() | nil}

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Persists the map generation seed."
  @spec save_seed(integer(), GenServer.server()) :: :ok
  def save_seed(seed, server \\ __MODULE__) when is_integer(seed) do
    GenServer.call(server, {:save_seed, seed})
  end

  @doc "Returns the stored map generation seed."
  @spec get_seed(GenServer.server()) :: integer() | nil
  def get_seed(server \\ __MODULE__) do
    GenServer.call(server, :get_seed)
  end

  @impl GenServer
  @spec init([option()]) :: {:ok, t(), {:continue, :setup}}
  def init(_opts) do
    {:ok, %__MODULE__{}, {:continue, :setup}}
  end

  @impl GenServer
  @spec handle_continue(:setup, t()) :: {:noreply, t()}
  def handle_continue(:setup, state) do
    tid = :ets.new(@ets_table, [:private, :set])
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
