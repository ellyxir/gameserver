defmodule Gameserver.Bench.MetricsTest do
  use ExUnit.Case, async: true

  alias Gameserver.Bench.Metrics

  setup do
    %{table: Metrics.new()}
  end

  test "records and retrieves latency measurements", %{table: table} do
    Metrics.record_latency(table, 1000)
    Metrics.record_latency(table, 2000)
    Metrics.record_latency(table, 3000)

    latencies = Metrics.get_latencies(table)
    assert length(latencies) == 3
    assert Enum.sort(latencies) == [1000, 2000, 3000]
  end

  test "records and retrieves render durations", %{table: table} do
    Metrics.record_render(table, 500)
    Metrics.record_render(table, 1500)

    renders = Metrics.get_renders(table)
    assert Enum.sort(renders) == [500, 1500]
  end

  test "records and retrieves beam snapshots", %{table: table} do
    snapshot = %{scheduler_util: 0.45, process_count: 1200, memory_mb: 89.5}
    Metrics.record_beam(table, snapshot)

    assert [^snapshot] = Metrics.get_beam_snapshots(table)
  end

  describe "format_us/1" do
    test "formats microseconds" do
      assert Metrics.format_us(500) == "500 us"
    end

    test "formats zero" do
      assert Metrics.format_us(0) == "0 us"
    end

    test "formats at boundary" do
      assert Metrics.format_us(1000) == "1.0 ms"
    end

    test "formats milliseconds" do
      assert Metrics.format_us(3500) == "3.5 ms"
    end
  end

  describe "percentile/2" do
    test "computes p50 of a sorted list" do
      values = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
      assert Metrics.percentile(values, 50) == 50
    end

    test "computes p95 of a sorted list" do
      values = Enum.to_list(1..100)
      assert Metrics.percentile(values, 95) == 95
    end

    test "computes p99 of a sorted list" do
      values = Enum.to_list(1..100)
      assert Metrics.percentile(values, 99) == 99
    end

    test "returns nil for empty list" do
      assert Metrics.percentile([], 50) == nil
    end

    test "handles single element list" do
      assert Metrics.percentile([42], 50) == 42
      assert Metrics.percentile([42], 99) == 42
    end
  end
end
