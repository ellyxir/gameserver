defmodule Gameserver.Cooldowns do
  @moduledoc """
  Tracks named cooldowns with configurable durations.

  Uses monotonic time for reliable elapsed-time comparisons.
  """

  defstruct timers: %{}

  @typedoc "A cooldown identifier"
  @type id() :: atom()

  @typedoc "Cooldown duration in milliseconds"
  @type duration_ms() :: pos_integer()

  @typep timer() :: {started_at :: integer(), duration_ms()}

  @typedoc "A single cooldown: its name and duration"
  @type cooldown() :: {id(), duration_ms()}

  @typedoc "A collection of named cooldown timers"
  @type t() :: %__MODULE__{
          timers: %{id() => timer()}
        }

  @doc "Creates an empty cooldown tracker."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Starts or restarts a named cooldown with the given duration in milliseconds."
  @spec start(t(), id(), duration_ms()) :: t()
  def start(%__MODULE__{timers: timers} = cd, id, duration_ms) do
    %{cd | timers: Map.put(timers, id, {System.monotonic_time(:millisecond), duration_ms})}
  end

  @doc "Returns true if the named cooldown has elapsed or was never started."
  @spec ready?(t(), id()) :: boolean()
  def ready?(%__MODULE__{timers: timers}, id) do
    case Map.get(timers, id) do
      nil -> true
      {started_at, duration} -> System.monotonic_time(:millisecond) - started_at >= duration
    end
  end

  @doc "Returns `:ok` if ready, `{:error, :cooldown}` if still active."
  @spec check(t(), id()) :: :ok | {:error, :cooldown}
  def check(%__MODULE__{} = cd, id) do
    if ready?(cd, id), do: :ok, else: {:error, :cooldown}
  end
end
