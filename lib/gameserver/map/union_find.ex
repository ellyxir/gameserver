defmodule Gameserver.Map.UnionFind do
  @moduledoc """
  A map-based union-find (disjoint set) data structure.

  Each node maps to its parent. Roots point to themselves.
  Supports path compression on find.
  """

  @typedoc "Opaque union-find state. Each node maps to its parent; roots point to themselves."
  @opaque t() :: %{any() => any()}

  @doc """
  Creates a new union-find where each node is its own root.
  """
  @spec new([node]) :: t() when node: any()
  def new(nodes) do
    Map.new(nodes, fn node -> {node, node} end)
  end

  @doc """
  Finds the root of the set containing `node`.

  Uses path compression -- all nodes along the path are updated to point
  directly to the root, keeping future lookups fast.

  Returns `{root, updated_union_find}`.
  """
  @spec find(t(), any()) :: {root :: any(), t()}
  def find(uf, node) do
    case Map.fetch!(uf, node) do
      # root case
      ^node ->
        {node, uf}

      # not root, recurse up then update parent
      parent ->
        {root, uf} = find(uf, parent)
        {root, Map.put(uf, node, root)}
    end
  end

  @doc """
  Merges the sets containing `root_a` and `root_b`.

  Both arguments should be roots (as returned by `find/2`).
  """
  @spec union(t(), root_a :: any(), root_b :: any()) :: t()
  def union(uf, root_a, root_b) do
    Map.put(uf, root_a, root_b)
  end

  @doc """
  Returns true if `a` and `b` are in the same set.
  Also returns the updated union-find state since find/2 might compress.
  """
  @spec connected?(t(), any(), any()) :: {boolean(), t()}
  def connected?(uf, a, b) do
    {root_a, uf} = find(uf, a)
    {root_b, uf} = find(uf, b)
    {root_a == root_b, uf}
  end
end
