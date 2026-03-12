defmodule Gameserver.Player do
  @moduledoc """
  Represents a player in the game world with their position.

  A Player wraps a User with game-world state like position and cooldowns.
  """

  alias Gameserver.Cooldowns
  alias Gameserver.Map, as: GameMap
  alias Gameserver.User

  defstruct [:user, :position, cooldowns: %Cooldowns{}]

  @typedoc "A player in the game world"
  @type t() :: %__MODULE__{
          user: User.t(),
          position: GameMap.coord(),
          cooldowns: Cooldowns.t()
        }

  @doc """
  Creates a new player with the given user and position.
  """
  @spec new(User.t(), GameMap.coord()) :: t()
  def new(%User{} = user, {x, y} = position) when is_integer(x) and is_integer(y) do
    %__MODULE__{user: user, position: position}
  end

  @doc """
  Returns the player's user id.
  """
  @spec id(t()) :: Ecto.UUID.t()
  def id(%__MODULE__{user: %User{id: id}}), do: id
end
