defmodule Gameserver.Map.CorridorTest do
  use ExUnit.Case, async: true

  alias Gameserver.Map, as: GameMap
  alias Gameserver.Map.Corridor

  describe "connect_rooms/3" do
    test "all floor tiles are reachable after connecting rooms" do
      # place 4 rooms on a 30x30 grid with a fixed seed
      rooms = [
        {{2, 2}, 4, 4},
        {{20, 2}, 4, 4},
        {{2, 20}, 4, 4},
        {{20, 20}, 4, 4}
      ]

      map = GameMap.new(30, 30)

      map =
        Enum.reduce(rooms, map, fn {{rx, ry}, rw, rh}, acc ->
          GameMap.fill_rect(acc, {rx, ry}, rw, rh, :floor)
        end)

      rand = :rand.seed_s(:exsss, 42)
      {map, _rand, _edges} = Corridor.connect_rooms(rooms, map, rand)

      floor_tiles =
        for x <- 0..(map.width - 1),
            y <- 0..(map.height - 1),
            GameMap.get_tile!(map, {x, y}) == :floor,
            do: {x, y}

      floor_set = MapSet.new(floor_tiles)
      assert MapSet.size(floor_set) > 0

      # flood fill from the first floor tile should reach all floor tiles
      [start | _] = floor_tiles
      reachable = flood_fill(start, floor_set)
      assert MapSet.equal?(reachable, floor_set)
    end

    test "corridors are deterministic with the same seed" do
      rooms = [
        {{2, 2}, 4, 4},
        {{20, 2}, 4, 4},
        {{2, 20}, 4, 4}
      ]

      map = GameMap.new(30, 30)

      map =
        Enum.reduce(rooms, map, fn {{rx, ry}, rw, rh}, acc ->
          GameMap.fill_rect(acc, {rx, ry}, rw, rh, :floor)
        end)

      rand = :rand.seed_s(:exsss, 99)
      {map1, _, _} = Corridor.connect_rooms(rooms, map, rand)

      rand = :rand.seed_s(:exsss, 99)
      {map2, _, _} = Corridor.connect_rooms(rooms, map, rand)

      assert map1.tiles == map2.tiles
    end

    test "empty room list returns map unchanged" do
      map = GameMap.new(20, 20)
      rand = :rand.seed_s(:exsss, 1)
      {result, _, _} = Corridor.connect_rooms([], map, rand)
      assert result.tiles == map.tiles
    end

    test "single room returns map unchanged" do
      rooms = [{{5, 5}, 3, 3}]
      map = GameMap.new(20, 20) |> GameMap.fill_rect({5, 5}, 3, 3, :floor)
      rand = :rand.seed_s(:exsss, 1)
      {result, _rand, _edges} = Corridor.connect_rooms(rooms, map, rand)
      assert result.tiles == map.tiles
    end

    test "returns MST edges" do
      rooms = [
        {{2, 2}, 4, 4},
        {{20, 2}, 4, 4},
        {{2, 20}, 4, 4}
      ]

      map = GameMap.new(30, 30)

      map =
        Enum.reduce(rooms, map, fn {{rx, ry}, rw, rh}, acc ->
          GameMap.fill_rect(acc, {rx, ry}, rw, rh, :floor)
        end)

      rand = :rand.seed_s(:exsss, 42)
      {_map, _rand, edges} = Corridor.connect_rooms(rooms, map, rand)

      # 3 rooms = 2 MST edges
      assert length(edges) == 2
      # each edge is a pair of rooms
      assert Enum.all?(edges, fn {a, b} -> a in rooms and b in rooms end)
    end
  end

  describe "room_path_length/3" do
    test "returns number of rooms on path between two connected rooms" do
      #  A -- B -- C (linear MST)
      a = {{0, 0}, 3, 3}
      b = {{10, 0}, 3, 3}
      c = {{20, 0}, 3, 3}
      edges = [{a, b}, {b, c}]

      assert Corridor.room_path_length(edges, a, b) == 2
      assert Corridor.room_path_length(edges, a, c) == 3
      assert Corridor.room_path_length(edges, c, a) == 3
    end

    test "returns 1 when from and to are the same room" do
      a = {{0, 0}, 3, 3}
      b = {{10, 0}, 3, 3}
      edges = [{a, b}]

      assert Corridor.room_path_length(edges, a, a) == 1
    end

    test "finds path in branching tree" do
      #       B
      #      /
      # A - D
      #      \
      #       C
      a = {{0, 0}, 3, 3}
      b = {{10, 10}, 3, 3}
      c = {{10, 20}, 3, 3}
      d = {{10, 0}, 3, 3}
      edges = [{a, d}, {d, b}, {d, c}]

      assert Corridor.room_path_length(edges, a, b) == 3
      assert Corridor.room_path_length(edges, b, c) == 3
      assert Corridor.room_path_length(edges, a, d) == 2
    end
  end

  defp flood_fill(start, floor_set) do
    do_flood_fill([start], floor_set, MapSet.new())
  end

  defp do_flood_fill([], _floor_set, visited), do: visited

  defp do_flood_fill([{x, y} | rest], floor_set, visited) do
    if MapSet.member?(floor_set, {x, y}) and not MapSet.member?(visited, {x, y}) do
      visited = MapSet.put(visited, {x, y})
      neighbors = [{x + 1, y}, {x - 1, y}, {x, y + 1}, {x, y - 1}]
      do_flood_fill(neighbors ++ rest, floor_set, visited)
    else
      do_flood_fill(rest, floor_set, visited)
    end
  end
end
