defmodule Gameserver.Map do
  @moduledoc """
  Represents a 2D grid map for the game world.

  Tiles are stored in a map keyed by `{x, y}` coordinate pairs.
  Origin `(0, 0)` is top-left, with X increasing rightward and Y increasing downward.
  """

  defstruct [:width, :height, :tiles]

  @typedoc "An {x, y} coordinate pair"
  @type coord() :: {non_neg_integer(), non_neg_integer()}

  @typedoc "Cardinal direction for movement."
  @type direction() :: :north | :south | :east | :west

  @type width() :: pos_integer()
  @type height() :: pos_integer()

  @tile_chars %{
    wall: "#",
    floor: ".",
    door: "+",
    upstairs: "<",
    downstairs: ">"
  }

  @typedoc """
    Tile types that can occupy a map cell.
    We generate it from @tile_chars. Helps with `tile_to_char/1` for exhaustivity.
  """
  @type tile() ::
          unquote(
            @tile_chars
            |> Map.keys()
            |> Enum.reduce(fn atom, acc -> {:|, [], [acc, atom]} end)
          )

  @typedoc "A 2D grid map with configurable dimensions"
  @type t() :: %__MODULE__{
          width: width(),
          height: height(),
          tiles: %{coord() => tile()}
        }

  @doc """
  Creates a new map with the given dimensions.

  Defaults to `:wall` so generators can "carve out" rooms/corridors as `:floor`.

  Options:
    - `:default` - the tile type to fill the map with (default: `:wall`)
  """
  @spec new(width(), height(), keyword()) :: t()
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
  @spec fill_rect(t(), coord(), width(), height(), tile()) :: t()
  def fill_rect(%__MODULE__{} = map, {x, y}, w, h, tile) do
    Enum.reduce(x..(x + w - 1), map, fn cx, acc ->
      Enum.reduce(y..(y + h - 1), acc, fn cy, acc2 ->
        set_tile(acc2, {cx, cy}, tile)
      end)
    end)
  end

  @doc """
  Finds a floor tile in the room and replaces it with the given tile.

  Raises `ArgumentError` if no floor tile exists in the room.
  """
  @spec set_tile_in_room!(t(), coord(), width(), height(), tile()) :: t()
  def set_tile_in_room!(%__MODULE__{} = map, {x, y}, w, h, tile) do
    floor_coord =
      for cx <- x..(x + w - 1),
          cy <- y..(y + h - 1),
          get_tile!(map, {cx, cy}) == :floor do
        {cx, cy}
      end
      |> List.first()

    case floor_coord do
      nil -> raise ArgumentError, "no floor tile in room at (#{x}, #{y}) #{w}x#{h}"
      coord -> set_tile(map, coord, tile)
    end
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
    |> fill_rect({1, 1}, 4, 4, :floor)
    # Room 2: top-right (4x4 at position 10,1)
    |> fill_rect({10, 1}, 4, 4, :floor)
    # Room 3: bottom-center (5x4 at position 5,10)
    |> fill_rect({5, 10}, 5, 4, :floor)
    # Corridor from room 1 to room 2 (horizontal at y=2)
    |> fill_rect({5, 2}, 5, 1, :floor)
    # Corridor from room 1 down to room 3 (vertical at x=3)
    |> fill_rect({3, 5}, 1, 5, :floor)
    # Corridor from room 2 down to room 3 (vertical at x=11)
    |> fill_rect({11, 5}, 1, 5, :floor)
    # Connect vertical corridors to room 3 (horizontal at y=10)
    |> fill_rect({3, 10}, 3, 1, :floor)
    |> fill_rect({10, 10}, 2, 1, :floor)
    # Place stairs after all geometry is carved
    |> set_tile_in_room!({1, 1}, 4, 4, :upstairs)
    |> set_tile_in_room!({5, 10}, 5, 4, :downstairs)
  end

  @doc """
  Converts the map to a list of character lists, one list per row.

  Each cell is a single-character string. Useful for per-character rendering
  where individual cells need different styling.
  """
  @spec to_cells(t()) :: [[String.t()]]
  def to_cells(%__MODULE__{width: width, height: height} = map) do
    for y <- 0..(height - 1) do
      for x <- 0..(width - 1) do
        tile_to_char(get_tile!(map, {x, y}))
      end
    end
  end

  @doc """
  Converts the map to a list of ASCII strings, one per row.

  Walls render as `#`, floors as `.`, doors as `+`.
  """
  @spec to_ascii(t()) :: [String.t()]
  def to_ascii(%__MODULE__{} = map) do
    map |> to_cells() |> Enum.map(&Enum.join/1)
  end

  @doc """
  Returns the spawn point for the map.

  Player spawns at the :upstairs tile. We return the first one we find.
  """
  @spec get_spawn_point(t()) :: {:ok, coord()} | {:error, :no_spawn_point}
  def get_spawn_point(%__MODULE__{tiles: tiles}) do
    case Enum.find(tiles, fn {_coord, tile} -> tile == :upstairs end) do
      nil -> {:error, :no_spawn_point}
      {coord, :upstairs} -> {:ok, coord}
    end
  end

  @doc "Parses a pair of strings into a coord tuple."
  @spec parse_coord(String.t(), String.t()) :: coord()
  def parse_coord(x, y), do: {String.to_integer(x), String.to_integer(y)}

  @spec tile_to_char(tile()) :: String.t()
  for {tile, c} <- @tile_chars do
    defp tile_to_char(unquote(tile)), do: unquote(c)
  end
end

defimpl String.Chars, for: Gameserver.Map do
  def to_string(map) do
    map |> Gameserver.Map.to_ascii() |> Enum.join("\n")
  end
end
