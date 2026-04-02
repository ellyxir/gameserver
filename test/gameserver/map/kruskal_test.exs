defmodule Gameserver.Map.KruskalTest do
  use ExUnit.Case, async: true

  alias Gameserver.Map.Kruskal

  describe "mst/2" do
    test "empty list returns empty edge list" do
      assert Kruskal.mst([], fn _, _ -> 1 end) == []
    end

    test "single node returns empty edge list" do
      assert Kruskal.mst([{0, 0}], fn _, _ -> 1 end) == []
    end

    test "two nodes returns one edge" do
      a = {0, 0}
      b = {3, 4}
      edges = Kruskal.mst([a, b], fn {x1, y1}, {x2, y2} -> abs(x1 - x2) + abs(y1 - y2) end)
      assert edges == [{a, b}]
    end

    test "four nodes in a square produces 3 MST edges" do
      # a--1--b
      # |     |
      # 1    10
      # |     |
      # c--1--d
      #
      # MST should pick the three cheapest edges: a-b, a-c, c-d
      a = :a
      b = :b
      c = :c
      d = :d

      costs = %{
        {a, b} => 1,
        {a, c} => 1,
        {a, d} => 10,
        {b, c} => 10,
        {b, d} => 10,
        {c, d} => 1
      }

      cost_fn = fn x, y ->
        Map.get(costs, {x, y}) || Map.get(costs, {y, x})
      end

      edges = Kruskal.mst([a, b, c, d], cost_fn)
      assert length(edges) == 3

      # all cheap edges should be picked, the expensive ones skipped
      edge_set = MapSet.new(edges, fn {x, y} -> MapSet.new([x, y]) end)
      assert MapSet.member?(edge_set, MapSet.new([a, b]))
      assert MapSet.member?(edge_set, MapSet.new([a, c]))
      assert MapSet.member?(edge_set, MapSet.new([c, d]))
    end
  end
end
