defmodule Gameserver.Map.UnionFindTest do
  use ExUnit.Case, async: true

  alias Gameserver.Map.UnionFind

  describe "new/1" do
    test "each node is its own root" do
      uf = UnionFind.new([:a, :b, :c])
      {root_a, _} = UnionFind.find(uf, :a)
      {root_b, _} = UnionFind.find(uf, :b)
      assert root_a == :a
      assert root_b == :b
    end
  end

  describe "find/2" do
    test "returns the node itself when it is the root" do
      uf = UnionFind.new([:x])
      {root, _} = UnionFind.find(uf, :x)
      assert root == :x
    end

    test "path compression updates parent to root" do
      uf = UnionFind.new([:a, :b, :c])
      uf = UnionFind.union(uf, :a, :b)
      uf = UnionFind.union(uf, :b, :c)

      # :a -> :b -> :c, find(:a) should compress to :a -> :c
      {root, uf} = UnionFind.find(uf, :a)
      assert root == :c

      # second find should be direct
      {root, _} = UnionFind.find(uf, :a)
      assert root == :c
    end
  end

  describe "union/3" do
    test "merges two sets" do
      uf = UnionFind.new([:a, :b])
      uf = UnionFind.union(uf, :a, :b)
      {root_a, uf} = UnionFind.find(uf, :a)
      {root_b, _} = UnionFind.find(uf, :b)
      assert root_a == root_b
    end
  end

  describe "connected?/3" do
    test "returns true for nodes in the same set" do
      uf = UnionFind.new([:a, :b])
      uf = UnionFind.union(uf, :a, :b)
      {connected, _} = UnionFind.connected?(uf, :a, :b)
      assert connected
    end

    test "returns false for nodes in different sets" do
      uf = UnionFind.new([:a, :b])
      {connected, _} = UnionFind.connected?(uf, :a, :b)
      refute connected
    end

    test "returns updated state with path compression" do
      uf = UnionFind.new([:a, :b, :c])
      uf = UnionFind.union(uf, :a, :b)
      uf = UnionFind.union(uf, :b, :c)
      {true, _uf} = UnionFind.connected?(uf, :a, :c)
    end
  end
end
