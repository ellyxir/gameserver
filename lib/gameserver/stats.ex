defmodule Gameserver.Stats do
  @moduledoc """
  Combat stats shared by players and mobs.
  """

  alias Gameserver.BaseStat

  defstruct str: %BaseStat{base: 10},
            dex: %BaseStat{base: 10},
            con: %BaseStat{base: 10},
            hp: 10,
            max_hp: 10,
            attack_power: 1,
            dead: false

  @typedoc "Combat stats for an entity"
  @type t() :: %__MODULE__{
          str: BaseStat.t(),
          dex: BaseStat.t(),
          con: BaseStat.t(),
          hp: non_neg_integer(),
          max_hp: pos_integer(),
          attack_power: non_neg_integer(),
          dead: boolean()
        }

  @doc """
  Creates a new stats struct with default values.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct!(__MODULE__, opts)
  end
end
