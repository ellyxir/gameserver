defmodule Gameserver.Map.Kruskal do
  @moduledoc """
  Generic minimum spanning tree using Kruskal's algorithm.

  Works on any list of nodes -- the caller provides a cost function
  that returns the weight between two nodes.
  """

  alias Gameserver.Map.UnionFind

  @typedoc "A cost function that returns the weight between two nodes."
  @type cost_fn() :: (vertex :: any(), vertex :: any() -> number())

  @typep weighted_edge() :: {cost :: number(), vertex :: any(), vertex :: any()}
  @typep edge() :: {vertex :: any(), vertex :: any()}

  @doc """
  Returns the minimum spanning tree for the given nodes.

  Takes a list of nodes and a cost function `(node, node -> number())`.
  Returns a list of `{node_a, node_b}` pairs forming the MST edges.
  """
  @spec mst([vertex], cost_fn()) :: [edge()] when vertex: any()
  def mst([], _cost_fn), do: []
  def mst([_], _cost_fn), do: []

  def mst(nodes, cost_fn) when is_list(nodes) and is_function(cost_fn, 2) do
    edges =
      for {a, b} <- combinations(nodes), do: {cost_fn.(a, b), a, b}

    sorted = Enum.sort_by(edges, fn {cost, _, _} -> cost end)
    uf = UnionFind.new(nodes)
    pick_edges(sorted, uf, length(nodes) - 1, [])
  end

  # walk sorted edges, accepting those that connect disjoint sets
  @spec pick_edges([weighted_edge()], UnionFind.t(), remaining :: non_neg_integer(), [edge()]) ::
          [edge()]
  defp pick_edges(_edges, _uf, 0, acc), do: Enum.reverse(acc)
  defp pick_edges([], _uf, _remaining, acc), do: Enum.reverse(acc)

  defp pick_edges([{_cost, a, b} | rest], uf, remaining, acc) do
    {root_a, uf} = UnionFind.find(uf, a)
    {root_b, uf} = UnionFind.find(uf, b)

    if root_a == root_b do
      pick_edges(rest, uf, remaining, acc)
    else
      uf = UnionFind.union(uf, root_a, root_b)
      pick_edges(rest, uf, remaining - 1, [{a, b} | acc])
    end
  end

  # returns all unique 2-element combinations from a list
  @spec combinations([any()]) :: [{any(), any()}]
  defp combinations([]), do: []

  defp combinations([head | tail]) do
    Enum.map(tail, fn elem -> {head, elem} end) ++ combinations(tail)
  end
end
