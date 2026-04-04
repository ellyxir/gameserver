defmodule Gameserver.Map do
  @moduledoc """
  Represents a 2D grid map for the game world.

  Tiles are stored in a map keyed by `{x, y}` coordinate pairs.
  Origin `(0, 0)` is top-left, with X increasing rightward and Y increasing downward.
  """

  alias Gameserver.Map.Corridor

  defstruct [:width, :height, :tiles, :seed, rooms: [], edges: []]

  @typedoc "An {x, y} coordinate pair"
  @type coord() :: {integer(), integer()}

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
          tiles: %{coord() => tile()},
          seed: integer() | nil,
          rooms: [room()],
          edges: [{room(), room()}]
        }

  @typedoc false
  @typep new_option() :: {:default, tile()}

  @doc """
  Creates a new map with the given dimensions.

  Defaults to `:wall` so generators can "carve out" rooms/corridors as `:floor`.

  Options:
    - `:default` - the tile type to fill the map with (default: `:wall`)
  """
  @spec new(width(), height(), [new_option()]) :: t()
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

  @typedoc "A room defined by its top-left coordinate, width, and height."
  @type room() :: {coord(), width(), height()}

  @typep rand_state() :: :rand.state()

  @room_padding 2

  defmodule RoomConfig do
    @moduledoc false

    @enforce_keys [:width, :height]
    defstruct width: nil,
              height: nil,
              seed: nil,
              room_count: 8,
              room_dim_min: 3,
              room_dim_max: 7,
              max_attempts: 100

    @typep width() :: pos_integer()
    @typep height() :: pos_integer()

    @type t() :: %__MODULE__{
            width: width(),
            height: height(),
            seed: integer() | nil,
            room_count: non_neg_integer(),
            room_dim_min: pos_integer(),
            room_dim_max: pos_integer(),
            max_attempts: non_neg_integer()
          }
  end

  @doc """
  Generates a random dungeon map with the given dimensions.

  Rooms are placed via random rejection with axis-aligned bounding box overlap checks and
  #{@room_padding}-tile padding (minimum wall tiles between any two rooms).

  Options:
    - `:room_count` - target number of rooms (default: 8)
    - `:room_dim_min` - minimum room dimension in tiles, applies to both width and height (default: 3)
    - `:room_dim_max` - maximum room dimension in tiles, applies to both width and height (default: 7)
    - `:max_attempts` - max placement attempts before giving up (default: 100)
    - `:min_path_rooms` - minimum rooms on the path between stairs (default: 1, no validation)
    - `:seed` - optional seed for reproducibility (see `:rand.seed()`)

  Discards and regenerates layouts where the stairs path crosses fewer than
  `:min_path_rooms` rooms (counting both endpoints), up to 10 retries.
  Falls back to the last generated layout if retries are exhausted.

  Raises `ArgumentError` if `:room_dim_min` is greater than `:room_dim_max`.
  """
  @typedoc false
  @typep generate_option() ::
           {:seed, integer()}
           | {:min_path_rooms, pos_integer()}
           | {:room_count, non_neg_integer()}
           | {:room_dim_min, pos_integer()}
           | {:room_dim_max, pos_integer()}
           | {:max_attempts, non_neg_integer()}

  @max_layout_retries 10

  @spec generate(width(), height(), [generate_option()]) :: t()
  def generate(width, height, opts \\ []) do
    seed = Keyword.get(opts, :seed) || :erlang.unique_integer([:positive])
    min_path_rooms = Keyword.get(opts, :min_path_rooms, 1)
    rand = :rand.seed_s(:exsss, seed)
    room_opts = Keyword.drop(opts, [:seed, :min_path_rooms])

    config =
      struct!(RoomConfig, Keyword.merge([width: width, height: height, seed: seed], room_opts))

    if config.room_dim_min > config.room_dim_max do
      raise ArgumentError,
            "room_dim_min (#{config.room_dim_min}) must be <= room_dim_max (#{config.room_dim_max})"
    end

    do_generate(config, rand, min_path_rooms, @max_layout_retries)
  end

  @spec do_generate(
          RoomConfig.t(),
          rand_state(),
          min_path_rooms :: pos_integer(),
          retries :: non_neg_integer()
        ) :: t()
  defp do_generate(config, rand, min_path_rooms, retries) do
    # generate non-overlapping rooms based on the config
    {rooms, rand} = place_rooms(config, rand)

    # make a new grid, filled with just walls
    game_map = new(config.width, config.height)

    # carve out each room into the grid as floor tiles
    game_map =
      Enum.reduce(rooms, game_map, fn {{rx, ry}, rw, rh}, acc ->
        fill_rect(acc, {rx, ry}, rw, rh, :floor)
      end)

    # connect rooms with L-shaped corridors via MST
    {game_map, rand, edges} = Corridor.connect_rooms(rooms, game_map, rand)

    # check stairs path crosses enough rooms, regenerate if too short
    {upstairs_room, downstairs_room} = stair_pair = stairs_rooms(rooms)
    path_length = Corridor.room_path_length(edges, upstairs_room, downstairs_room)

    if path_length >= min_path_rooms or retries == 0 do
      # place stairs: upstairs in first room, downstairs in farthest room
      game_map = place_stairs(game_map, stair_pair)
      %{game_map | rooms: rooms, edges: edges, seed: config.seed}
    else
      do_generate(config, rand, min_path_rooms, retries - 1)
    end
  end

  @doc """
  Returns the rooms chosen for upstairs and downstairs stair placement.

  Upstairs is in the first room, downstairs is in the room farthest
  from it by euclidean distance between room centers.
  """
  @spec stairs_rooms([room()]) :: {upstairs :: room(), downstairs :: room()}
  def stairs_rooms(rooms) when length(rooms) < 2 do
    raise ArgumentError, "need at least 2 rooms to place stairs, got #{length(rooms)}"
  end

  def stairs_rooms(rooms) do
    [first | rest] = rooms
    first_center = room_center(first)

    farthest =
      Enum.max_by(rest, fn room ->
        {cx, cy} = room_center(room)
        {fx, fy} = first_center
        (cx - fx) ** 2 + (cy - fy) ** 2
      end)

    {first, farthest}
  end

  @spec place_stairs(t(), {room(), room()}) :: t()
  defp place_stairs(map, {upstairs, downstairs}) do
    map = set_tile(map, room_center(upstairs), :upstairs)
    set_tile(map, room_center(downstairs), :downstairs)
  end

  @doc """
  Returns a random floor tile coordinate within the given room.

  Only considers tiles that are `:floor` (excludes stairs).
  Raises if no floor tile exists in the room.
  """
  @spec random_tile_in_room(t(), room()) :: coord()
  def random_tile_in_room(%__MODULE__{} = map, {{rx, ry}, rw, rh}) do
    floor_tiles =
      for x <- rx..(rx + rw - 1),
          y <- ry..(ry + rh - 1),
          get_tile!(map, {x, y}) == :floor,
          do: {x, y}

    case floor_tiles do
      [] -> raise ArgumentError, "no floor tile in room at {#{rx}, #{ry}} #{rw}x#{rh}"
      tiles -> Enum.random(tiles)
    end
  end

  @doc "Returns the center coordinate of a room."
  @spec room_center(room()) :: coord()
  def room_center({{rx, ry}, rw, rh}) do
    {rx + div(rw, 2), ry + div(rh, 2)}
  end

  @spec place_rooms(RoomConfig.t(), rand_state()) :: {[room()], rand_state()}
  defp place_rooms(config, rand) do
    do_place_rooms(config, rand, 0, 0, [])
  end

  @spec do_place_rooms(RoomConfig.t(), rand_state(), non_neg_integer(), non_neg_integer(), [
          room()
        ]) ::
          {[room()], rand_state()}
  defp do_place_rooms(
         %RoomConfig{room_count: room_count},
         rand,
         _attempt_num,
         rooms_placed,
         rooms
       )
       when rooms_placed >= room_count do
    {rooms, rand}
  end

  defp do_place_rooms(
         %RoomConfig{max_attempts: max_attempts},
         rand,
         attempt_num,
         _rooms_placed,
         rooms
       )
       when attempt_num >= max_attempts do
    {rooms, rand}
  end

  defp do_place_rooms(config, rand, attempt_num, rooms_placed, rooms) do
    %RoomConfig{width: w, height: h, room_dim_min: dim_min, room_dim_max: dim_max} = config
    {rw, rand} = uniform_range(dim_min, dim_max, rand)
    {rh, rand} = uniform_range(dim_min, dim_max, rand)
    max_x = max(1, w - rw - 1)
    max_y = max(1, h - rh - 1)
    {rx, rand} = uniform_range(1, max_x, rand)
    {ry, rand} = uniform_range(1, max_y, rand)
    candidate = {{rx, ry}, rw, rh}
    fits_in_grid = rx >= 1 and ry >= 1 and rx + rw < w and ry + rh < h

    if fits_in_grid and not rooms_overlap?(candidate, rooms) do
      do_place_rooms(config, rand, attempt_num + 1, rooms_placed + 1, [candidate | rooms])
    else
      do_place_rooms(config, rand, attempt_num + 1, rooms_placed, rooms)
    end
  end

  # returns a random integer in [min, max] (inclusive)
  # :rand.uniform_s/2 returns 1..n, so we shift it into the desired range
  @spec uniform_range(integer(), integer(), rand_state()) :: {integer(), rand_state()}
  defp uniform_range(min, max, rand) when min <= max do
    {val, rand} = :rand.uniform_s(max - min + 1, rand)
    {val - 1 + min, rand}
  end

  @spec rooms_overlap?(room(), [room()]) :: boolean()
  defp rooms_overlap?(candidate, rooms) do
    Enum.any?(rooms, &aabb_overlap?(candidate, &1, @room_padding))
  end

  @spec aabb_overlap?(room(), room(), non_neg_integer()) :: boolean()
  defp aabb_overlap?({{ax, ay}, aw, ah}, {{bx, by}, bw, bh}, pad) do
    not (ax + aw + pad <= bx or
           bx + bw + pad <= ax or
           ay + ah + pad <= by or
           by + bh + pad <= ay)
  end

  @doc """
  Creates a deterministic sample dungeon for tests.

  Uses `generate/3` with a fixed seed for reproducibility.
  """
  @spec sample_dungeon() :: t()
  def sample_dungeon do
    generate(20, 20, seed: 0)
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

  Spawn point is the first :upstairs tile found on the map.
  """
  @spec get_spawn_point(t()) :: {:ok, coord()} | {:error, :no_spawn_point}
  def get_spawn_point(%__MODULE__{tiles: tiles}) do
    case Enum.find(tiles, fn {_coord, tile} -> tile == :upstairs end) do
      nil -> {:error, :no_spawn_point}
      {coord, :upstairs} -> {:ok, coord}
    end
  end

  @doc "Returns true if the coordinate is blocked (wall or out of bounds)."
  @spec collision?(t(), coord()) :: boolean()
  def collision?(%__MODULE__{} = map, coord) do
    case get_tile(map, coord) do
      {:ok, :wall} -> true
      {:ok, _tile} -> false
      {:error, :out_of_bounds} -> true
    end
  end

  @doc "Returns true if any tile along the path from src to dest is blocked. Excludes src, includes dest."
  @spec collision?(t(), coord(), coord()) :: boolean()
  def collision?(%__MODULE__{} = map, {sx, sy}, {dx, dy}) do
    coords =
      for x <- range(sx, dx), y <- range(sy, dy), {x, y} != {sx, sy} do
        {x, y}
      end

    Enum.any?(coords, &collision?(map, &1))
  end

  defp range(a, a), do: [a]
  defp range(a, b) when a < b, do: a..b
  defp range(a, b), do: a..b//-1

  @doc "Returns the coordinate a given number of units in the given direction. Does not check bounds."
  @spec interpolate(coord(), direction(), pos_integer()) :: coord()
  def interpolate(coord, direction, units \\ 1)
  def interpolate({x, y}, :north, units), do: {x, y - units}
  def interpolate({x, y}, :south, units), do: {x, y + units}
  def interpolate({x, y}, :east, units), do: {x + units, y}
  def interpolate({x, y}, :west, units), do: {x - units, y}

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
