defmodule Gameserver.Bench.Metrics do
  @moduledoc """
  ETS-based metrics collection for the load test bench task.

  Stores latency measurements, BEAM metric snapshots, and render
  durations. Provides percentile computation and report formatting.
  """

  @typedoc "ETS table reference"
  @type table() :: :ets.table()

  @doc "Creates a new metrics ETS table."
  @spec new() :: table()
  def new do
    :ets.new(:bench_metrics, [:bag, :public])
  end

  @doc "Deletes the metrics table."
  @spec delete(table()) :: true
  def delete(table) do
    :ets.delete(table)
  end

  @doc "Records an event round-trip latency in microseconds."
  @spec record_latency(table(), latency_us :: non_neg_integer()) :: true
  def record_latency(table, latency_us) do
    :ets.insert(table, {:latency, latency_us})
  end

  @doc "Returns all recorded latencies as a list."
  @spec get_latencies(table()) :: [non_neg_integer()]
  def get_latencies(table) do
    table
    |> :ets.match({:latency, :"$1"})
    |> List.flatten()
  end

  @doc "Records a LiveView render duration in microseconds."
  @spec record_render(table(), duration_us :: non_neg_integer()) :: true
  def record_render(table, duration_us) do
    :ets.insert(table, {:render, duration_us})
  end

  @doc "Returns all recorded render durations as a list."
  @spec get_renders(table()) :: [non_neg_integer()]
  def get_renders(table) do
    table
    |> :ets.match({:render, :"$1"})
    |> List.flatten()
  end

  # TODO(@ellyxir): define a type for beam snapshots once the mix task shape is settled
  @doc "Records a BEAM metrics snapshot."
  @spec record_beam(table(), snapshot :: map()) :: true
  def record_beam(table, snapshot) do
    :ets.insert(table, {:beam, snapshot})
  end

  @doc "Returns all recorded BEAM snapshots as a list."
  @spec get_beam_snapshots(table()) :: [map()]
  def get_beam_snapshots(table) do
    table
    |> :ets.match({:beam, :"$1"})
    |> List.flatten()
  end

  @doc "Computes the p-th percentile of a sorted list. Returns nil for empty lists."
  @spec percentile([number()], p :: number()) :: number() | nil
  def percentile([], _p), do: nil

  def percentile(sorted, p) do
    index = max(0, ceil(length(sorted) * p / 100) - 1)
    Enum.at(sorted, index)
  end

  @doc "Formats a microsecond value as a human-readable string."
  @spec format_us(number()) :: String.t()
  def format_us(us) when us >= 1000, do: "#{Float.round(us / 1000, 2)} ms"
  def format_us(us), do: "#{us} us"
end
