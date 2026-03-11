defmodule Gameserver.Map do
  @moduledoc """
  Represents a 2D grid map for the game world.

  Tiles are stored in a map keyed by `{x, y}` coordinate pairs.
  Origin `(0, 0)` is top-left, with X increasing rightward and Y increasing downward.
  """

  defstruct [:width, :height, :tiles]

  @typedoc "Tile types that can occupy a map cell"
  @type tile() :: :wall | :floor | :door | :upstairs | :downstairs

  @typedoc "An {x, y} coordinate pair"
  @type coord() :: {non_neg_integer(), non_neg_integer()}

  @typedoc "A room is a rectangle. coord() for top right point, and w,h for width and height"
  @type room() :: {coord(), non_neg_integer(), non_neg_integer()}

  @typedoc "A 2D grid map with configurable dimensions"
  @type t() :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          tiles: %{coord() => tile()}
        }

  @doc """
  Creates a new map with the given dimensions.

  Defaults to `:wall` so generators can "carve out" rooms/corridors as `:floor`.

  Options:
    - `:default` - the tile type to fill the map with (default: `:wall`)
  """
  @spec new(pos_integer(), pos_integer(), keyword()) :: t()
  def new(width, height, opts \\ []) when width > 0 and height > 0 do
    default_tile = Keyword.get(opts, :default, :wall)

    tiles =
      for x <- 0..(width - 1), y <- 0..(height - 1), into: %{} do
        {{x, y}, default_tile}
      end

    %__MODULE__{width: width, height: height, tiles: tiles}
  end

  @doc """
  Returns the tile at the given coordinates.
  """
  @spec get_tile(t(), coord()) :: {:ok, tile()} | {:error, :out_of_bounds}
  def get_tile(%__MODULE__{} = map, {x, y} = coord) do
    if in_bounds?(map, coord) do
      {:ok, Map.get(map.tiles, {x, y})}
    else
      {:error, :out_of_bounds}
    end
  end

  @doc """
  Returns the tile at the given coordinates, raises if out of bounds.
  """
  @spec get_tile!(t(), coord()) :: tile()
  def get_tile!(%__MODULE__{} = map, {x, y} = coord) do
    case get_tile(map, coord) do
      {:ok, tile} -> tile
      {:error, :out_of_bounds} -> raise ArgumentError, "coordinates (#{x}, #{y}) out of bounds"
    end
  end

  @doc """
  Sets the tile at the given coordinates.

  Returns the map unchanged if coordinates are out of bounds.
  """
  @spec set_tile(t(), coord(), tile()) :: t()
  def set_tile(%__MODULE__{} = map, {_x, _y} = coord, tile) do
    if in_bounds?(map, coord) do
      %{map | tiles: Map.put(map.tiles, coord, tile)}
    else
      map
    end
  end

  @doc """
  Returns true if the coordinates are within the map bounds.
  """
  @spec in_bounds?(t(), coord()) :: boolean()
  def in_bounds?(%__MODULE__{width: width, height: height}, {x, y}) do
    x >= 0 and x < width and y >= 0 and y < height
  end

  @doc """
  Fills a rectangular area with the given tile type.

  The rectangle starts at `{x, y}` and extends `w` tiles wide and `h` tiles tall.
  """
  @spec fill_rect(t(), room(), tile()) :: t()
  def fill_rect(%__MODULE__{} = map, {{x, y}, w, h}, tile) do
    Enum.reduce(x..(x + w - 1), map, fn cx, acc ->
      Enum.reduce(y..(y + h - 1), acc, fn cy, acc2 ->
        set_tile(acc2, {cx, cy}, tile)
      end)
    end)
  end

  @doc """
  Creates a sample dungeon map with 3 rooms connected by corridors.

  The dungeon is approximately 15x15 tiles.
  """
  @spec sample_dungeon() :: t()
  def sample_dungeon do
    width = 15
    height = 15

    new(width, height)
    # Room 1: top-left (4x4 at position 1,1)
    |> fill_rect({{1, 1}, 4, 4}, :floor)
    # Room 2: top-right (4x4 at position 10,1)
    |> fill_rect({{10, 1}, 4, 4}, :floor)
    # Room 3: bottom-center (5x4 at position 5,10)
    |> fill_rect({{5, 10}, 5, 4}, :floor)
    # Corridor from room 1 to room 2 (horizontal at y=2)
    |> fill_rect({{5, 2}, 5, 1}, :floor)
    # Corridor from room 1 down to room 3 (vertical at x=3)
    |> fill_rect({{3, 5}, 1, 5}, :floor)
    # Corridor from room 2 down to room 3 (vertical at x=11)
    |> fill_rect({{11, 5}, 1, 5}, :floor)
    # Connect vertical corridors to room 3 (horizontal at y=10)
    |> fill_rect({{3, 10}, 3, 1}, :floor)
    |> fill_rect({{10, 10}, 2, 1}, :floor)
  end

  @doc """
  Converts the map to a list of ASCII strings, one per row.

  Walls render as `#`, floors as `.`, doors as `+`.
  """
  @spec to_ascii(t()) :: [String.t()]
  def to_ascii(%__MODULE__{width: width, height: height} = map) do
    for y <- 0..(height - 1) do
      for x <- 0..(width - 1), into: "" do
        tile_to_char(get_tile!(map, {x, y}))
      end
    end
  end

  @spec tile_to_char(tile()) :: String.t()
  defp tile_to_char(:wall), do: "#"
  defp tile_to_char(:floor), do: "."
  defp tile_to_char(:door), do: "+"
end

defimpl String.Chars, for: Gameserver.Map do
  def to_string(map) do
    map |> Gameserver.Map.to_ascii() |> Enum.join("\n")
  end
end
