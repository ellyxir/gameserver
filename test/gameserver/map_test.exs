defmodule Gameserver.MapTest do
  use ExUnit.Case, async: true

  alias Gameserver.Map, as: GameMap

  describe "new/3" do
    test "creates a map with given dimensions" do
      map = GameMap.new(10, 8)
      assert map.width == 10
      assert map.height == 8
    end

    test "initializes all tiles to :wall by default" do
      map = GameMap.new(3, 3)

      for x <- 0..2, y <- 0..2 do
        assert GameMap.get_tile!(map, {x, y}) == :wall
      end
    end

    test "accepts custom default tile" do
      map = GameMap.new(3, 3, default: :floor)

      for x <- 0..2, y <- 0..2 do
        assert GameMap.get_tile!(map, {x, y}) == :floor
      end
    end
  end

  describe "get_tile/2" do
    test "returns {:ok, tile} at coordinates" do
      map = GameMap.new(5, 5) |> GameMap.set_tile({2, 3}, :floor)
      assert GameMap.get_tile(map, {2, 3}) == {:ok, :floor}
    end

    test "returns {:error, :out_of_bounds} for out of bounds coordinates" do
      map = GameMap.new(5, 5)
      assert GameMap.get_tile(map, {-1, 0}) == {:error, :out_of_bounds}
      assert GameMap.get_tile(map, {5, 0}) == {:error, :out_of_bounds}
      assert GameMap.get_tile(map, {0, -1}) == {:error, :out_of_bounds}
      assert GameMap.get_tile(map, {0, 5}) == {:error, :out_of_bounds}
    end
  end

  describe "get_tile!/2" do
    test "returns tile at coordinates" do
      map = GameMap.new(5, 5) |> GameMap.set_tile({2, 3}, :floor)
      assert GameMap.get_tile!(map, {2, 3}) == :floor
    end

    test "raises for out of bounds coordinates" do
      map = GameMap.new(5, 5)

      assert_raise ArgumentError, "coordinates (-1, 0) out of bounds", fn ->
        GameMap.get_tile!(map, {-1, 0})
      end
    end
  end

  describe "set_tile/3" do
    test "sets tile at coordinates" do
      map = GameMap.new(5, 5) |> GameMap.set_tile({1, 2}, :floor)
      assert GameMap.get_tile!(map, {1, 2}) == :floor
    end

    test "returns unchanged map for out of bounds coordinates" do
      map = GameMap.new(5, 5)
      result = GameMap.set_tile(map, {-1, 0}, :floor)
      assert result == map
    end
  end

  describe "in_bounds?/2" do
    test "returns true for valid coordinates" do
      map = GameMap.new(10, 10)
      assert GameMap.in_bounds?(map, {0, 0})
      assert GameMap.in_bounds?(map, {9, 9})
      assert GameMap.in_bounds?(map, {5, 5})
    end

    test "returns false for negative coordinates" do
      map = GameMap.new(10, 10)
      refute GameMap.in_bounds?(map, {-1, 0})
      refute GameMap.in_bounds?(map, {0, -1})
    end

    test "returns false for coordinates at or beyond dimensions" do
      map = GameMap.new(10, 10)
      refute GameMap.in_bounds?(map, {10, 0})
      refute GameMap.in_bounds?(map, {0, 10})
    end
  end

  describe "fill_rect/5" do
    test "fills rectangular area with tile type" do
      map = GameMap.new(10, 10) |> GameMap.fill_rect({2, 2}, 4, 3, :floor)

      # Inside the rect
      assert GameMap.get_tile!(map, {2, 2}) == :floor
      assert GameMap.get_tile!(map, {5, 4}) == :floor

      # Outside the rect
      assert GameMap.get_tile!(map, {1, 2}) == :wall
      assert GameMap.get_tile!(map, {6, 2}) == :wall
    end
  end

  describe "set_tile_in_room!/5" do
    test "places tile on a floor tile within the room" do
      map = GameMap.new(10, 10) |> GameMap.fill_rect({2, 2}, 3, 3, :floor)
      result = GameMap.set_tile_in_room!(map, {2, 2}, 3, 3, :upstairs)

      floor_coords =
        for x <- 2..4, y <- 2..4, GameMap.get_tile!(result, {x, y}) == :upstairs, do: {x, y}

      assert length(floor_coords) == 1
    end

    test "raises when no floor tiles exist in the room" do
      map = GameMap.new(10, 10)

      assert_raise ArgumentError, fn ->
        GameMap.set_tile_in_room!(map, {2, 2}, 3, 3, :upstairs)
      end
    end
  end

  describe "sample_dungeon/0" do
    test "returns a map struct" do
      map = GameMap.sample_dungeon()
      assert %GameMap{} = map
    end

    test "has reasonable dimensions around 15x15" do
      map = GameMap.sample_dungeon()
      assert map.width >= 10 and map.width <= 20
      assert map.height >= 10 and map.height <= 20
    end

    test "contains both wall and floor tiles" do
      map = GameMap.sample_dungeon()

      tiles =
        for x <- 0..(map.width - 1), y <- 0..(map.height - 1) do
          GameMap.get_tile!(map, {x, y})
        end

      assert :wall in tiles
      assert :floor in tiles
    end

    test "has floor tiles forming connected areas (rooms/corridors)" do
      map = GameMap.sample_dungeon()

      floor_count =
        for x <- 0..(map.width - 1), y <- 0..(map.height - 1), reduce: 0 do
          acc ->
            if GameMap.get_tile!(map, {x, y}) == :floor, do: acc + 1, else: acc
        end

      # Should have a reasonable number of floor tiles for 3 rooms + corridors
      assert floor_count > 30
    end
  end

  describe "to_ascii/1" do
    test "converts map to list of row strings" do
      map = GameMap.new(3, 2)
      rows = GameMap.to_ascii(map)

      assert rows == ["###", "###"]
    end

    test "renders floors as dots" do
      map = GameMap.new(3, 1, default: :floor)
      assert GameMap.to_ascii(map) == ["..."]
    end

    test "renders doors as plus signs" do
      map = GameMap.new(3, 1) |> GameMap.set_tile({1, 0}, :door)
      assert GameMap.to_ascii(map) == ["#+#"]
    end
  end

  describe "to_cells/1" do
    test "converts map to list of character lists" do
      map = GameMap.new(3, 2)
      cells = GameMap.to_cells(map)

      assert cells == [["#", "#", "#"], ["#", "#", "#"]]
    end

    test "renders different tile types as individual characters" do
      map = GameMap.new(3, 1) |> GameMap.set_tile({1, 0}, :floor)
      assert GameMap.to_cells(map) == [["#", ".", "#"]]
    end
  end

  describe "String.Chars protocol" do
    test "to_string/1 returns ascii rows joined by newlines" do
      map = GameMap.new(3, 2)
      assert to_string(map) == "###\n###"
    end
  end

  describe "get_spawn_point/1" do
    test "returns a floor tile coordinate" do
      map = GameMap.new(5, 5) |> GameMap.set_tile({2, 3}, :upstairs)

      {:ok, {x, y}} = GameMap.get_spawn_point(map)

      assert GameMap.get_tile!(map, {x, y}) == :upstairs
    end

    test "returns error when map has no floor tiles" do
      map = GameMap.new(5, 5)

      assert {:error, :no_spawn_point} = GameMap.get_spawn_point(map)
    end
  end

  describe "interpolate/3" do
    test "moves north (decreases y)" do
      assert GameMap.interpolate({5, 5}, :north) == {5, 4}
    end

    test "moves south (increases y)" do
      assert GameMap.interpolate({5, 5}, :south) == {5, 6}
    end

    test "moves east (increases x)" do
      assert GameMap.interpolate({5, 5}, :east) == {6, 5}
    end

    test "moves west (decreases x)" do
      assert GameMap.interpolate({5, 5}, :west) == {4, 5}
    end

    test "moves multiple units" do
      assert GameMap.interpolate({5, 5}, :north, 3) == {5, 2}
      assert GameMap.interpolate({5, 5}, :east, 4) == {9, 5}
    end
  end

  describe "collision?/2" do
    test "floor tiles have no collision" do
      map = GameMap.new(3, 3, default: :floor)
      refute GameMap.collision?(map, {1, 1})
    end

    test "wall tiles have collision" do
      map = GameMap.new(3, 3)
      assert GameMap.collision?(map, {1, 1})
    end

    test "door and stair tiles have no collision" do
      map = GameMap.new(3, 3)
      refute GameMap.collision?(GameMap.set_tile(map, {1, 1}, :door), {1, 1})
      refute GameMap.collision?(GameMap.set_tile(map, {1, 1}, :upstairs), {1, 1})
      refute GameMap.collision?(GameMap.set_tile(map, {1, 1}, :downstairs), {1, 1})
    end

    test "out of bounds has collision" do
      map = GameMap.new(3, 3)
      assert GameMap.collision?(map, {-1, 0})
      assert GameMap.collision?(map, {3, 0})
      assert GameMap.collision?(map, {0, -1})
      assert GameMap.collision?(map, {0, 3})
    end
  end

  describe "collision?/3 (path)" do
    test "no collision on clear path" do
      map = GameMap.new(5, 1, default: :floor)
      refute GameMap.collision?(map, {0, 0}, {3, 0})
    end

    test "wall in path causes collision" do
      map = GameMap.new(5, 1, default: :floor) |> GameMap.set_tile({2, 0}, :wall)
      assert GameMap.collision?(map, {0, 0}, {4, 0})
    end

    test "does not check the starting tile" do
      map = GameMap.new(5, 1, default: :floor) |> GameMap.set_tile({0, 0}, :wall)
      refute GameMap.collision?(map, {0, 0}, {3, 0})
    end

    test "checks destination tile" do
      map = GameMap.new(5, 1, default: :floor) |> GameMap.set_tile({3, 0}, :wall)
      assert GameMap.collision?(map, {0, 0}, {3, 0})
    end

    test "works vertically" do
      map = GameMap.new(1, 5, default: :floor) |> GameMap.set_tile({0, 2}, :wall)
      assert GameMap.collision?(map, {0, 0}, {0, 4})
    end

    test "dest out of bounds causes collision" do
      map = GameMap.new(5, 1, default: :floor)
      assert GameMap.collision?(map, {3, 0}, {5, 0})
    end
  end

  describe "parse_coord/2" do
    test "converts string pair to coord tuple" do
      assert GameMap.parse_coord("3", "7") == {3, 7}
    end

    test "handles zero" do
      assert GameMap.parse_coord("0", "0") == {0, 0}
    end
  end
end
