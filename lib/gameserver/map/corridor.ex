defmodule Gameserver.Map.Corridor do
  @moduledoc """
  Connects rooms with L-shaped corridors using a minimum spanning tree.

  Given a list of rooms and a carved map, computes room centers,
  builds an MST via `Gameserver.Map.Kruskal`, then carves 1-tile-wide
  L-shaped corridors between connected rooms.
  """

  alias Gameserver.Map, as: GameMap
  alias Gameserver.Map.Kruskal

  @typep rand_state() :: :rand.state()

  @doc """
  Connects all rooms with L-shaped corridors.

  Builds an MST over room centers using euclidean distance, then carves
  a corridor for each edge. Randomly chooses horizontal-first or
  vertical-first for each corridor.

  Returns `{updated_map, rand_state, mst_edges}`.
  """
  @spec connect_rooms([GameMap.room()], GameMap.t(), rand_state()) ::
          {GameMap.t(), rand_state(), [{GameMap.room(), GameMap.room()}]}
  def connect_rooms([], map, rand), do: {map, rand, []}
  def connect_rooms([_], map, rand), do: {map, rand, []}

  def connect_rooms(rooms, map, rand) do
    edges = Kruskal.mst(rooms, &euclidean_distance/2)

    # carve an L-shaped corridor between each pair of connected rooms
    {map, rand} =
      Enum.reduce(edges, {map, rand}, fn {room_a, room_b}, {map, rand} ->
        center_a = GameMap.room_center(room_a)
        center_b = GameMap.room_center(room_b)
        carve_corridor(map, center_a, center_b, rand)
      end)

    {map, rand, edges}
  end

  @doc """
  Returns the number of rooms on the path between two rooms in the minimum spanning tree.

  Since a tree has exactly one path between any two nodes, uses breadth-first search
  to find it and returns the number of rooms traversed (including both endpoints).
  """
  @spec room_path_length(
          edges :: [{GameMap.room(), GameMap.room()}],
          from :: GameMap.room(),
          to :: GameMap.room()
        ) :: pos_integer()
  def room_path_length(edges, from, to) when is_list(edges) do
    adjacency = build_adjacency(edges)
    bfs_path_length(adjacency, from, to)
  end

  @spec build_adjacency([{GameMap.room(), GameMap.room()}]) :: %{
          GameMap.room() => [GameMap.room()]
        }
  defp build_adjacency(edges) do
    Enum.reduce(edges, %{}, fn {a, b}, acc ->
      acc
      |> Map.update(a, [b], &[b | &1])
      |> Map.update(b, [a], &[a | &1])
    end)
  end

  # depth counts rooms visited (including both endpoints), not edges traversed
  @spec bfs_path_length(%{GameMap.room() => [GameMap.room()]}, GameMap.room(), GameMap.room()) ::
          pos_integer()
  defp bfs_path_length(adjacency, from, to) do
    do_bfs(:queue.in({from, 1}, :queue.new()), to, adjacency, MapSet.new([from]))
  end

  @spec do_bfs(
          :queue.queue({GameMap.room(), pos_integer()}),
          GameMap.room(),
          %{GameMap.room() => [GameMap.room()]},
          MapSet.t()
        ) ::
          pos_integer()
  defp do_bfs(queue, target, adjacency, visited) do
    case :queue.out(queue) do
      {{:value, {^target, depth}}, _queue} ->
        depth

      {{:value, {room, depth}}, rest} ->
        neighbors =
          adjacency
          |> Map.get(room, [])
          |> Enum.reject(&MapSet.member?(visited, &1))

        {rest, visited} =
          Enum.reduce(neighbors, {rest, visited}, fn neighbor, {q, v} ->
            {:queue.in({neighbor, depth + 1}, q), MapSet.put(v, neighbor)}
          end)

        do_bfs(rest, target, adjacency, visited)

      {:empty, _queue} ->
        raise ArgumentError, "target room not reachable from source in the given edges"
    end
  end

  @spec euclidean_distance(GameMap.room(), GameMap.room()) :: float()
  defp euclidean_distance(room_a, room_b) do
    {x1, y1} = GameMap.room_center(room_a)
    {x2, y2} = GameMap.room_center(room_b)
    :math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)
  end

  # carves an L-shaped corridor between two points.
  # randomly picks horizontal-first or vertical-first.
  @spec carve_corridor(GameMap.t(), GameMap.coord(), GameMap.coord(), rand_state()) ::
          {GameMap.t(), rand_state()}
  defp carve_corridor(map, {x1, y1}, {x2, y2}, rand) do
    {choice, rand} = :rand.uniform_s(2, rand)

    map =
      if choice == 1 do
        # horizontal first, then vertical
        map
        |> carve_h_line(x1, x2, y1)
        |> carve_v_line(y1, y2, x2)
      else
        # vertical first, then horizontal
        map
        |> carve_v_line(y1, y2, x1)
        |> carve_h_line(x1, x2, y2)
      end

    {map, rand}
  end

  # carve a horizontal line of floor tiles from x1 to x2 at row y
  @spec carve_h_line(GameMap.t(), x1 :: integer(), x2 :: integer(), y :: integer()) :: GameMap.t()
  defp carve_h_line(map, x1, x2, y) do
    for x <- x1..x2//direction(x1, x2), reduce: map do
      acc -> GameMap.set_tile(acc, {x, y}, :floor)
    end
  end

  # carve a vertical line of floor tiles from y1 to y2 at column x
  @spec carve_v_line(GameMap.t(), y1 :: integer(), y2 :: integer(), x :: integer()) :: GameMap.t()
  defp carve_v_line(map, y1, y2, x) do
    for y <- y1..y2//direction(y1, y2), reduce: map do
      acc -> GameMap.set_tile(acc, {x, y}, :floor)
    end
  end

  @spec direction(integer(), integer()) :: 1 | -1
  defp direction(a, b) when a <= b, do: 1
  defp direction(_, _), do: -1
end
