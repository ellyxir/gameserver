defmodule Gameserver.Stats do
  @moduledoc """
  Combat stats shared by players and mobs.
  """

  alias Gameserver.BaseStat
  alias Gameserver.HpStat
  alias Gameserver.MaxHpStat

  defstruct str: %BaseStat{base: 10},
            dex: %BaseStat{base: 10},
            con: %BaseStat{base: 10},
            hp: %HpStat{base_stat: %BaseStat{base: 10}},
            max_hp: %MaxHpStat{},
            attack_power: 1,
            defense: 0,
            dead: false

  @typedoc "Combat stats for an entity"
  @type t() :: %__MODULE__{
          str: BaseStat.t(),
          dex: BaseStat.t(),
          con: BaseStat.t(),
          hp: HpStat.t(),
          max_hp: MaxHpStat.t(),
          attack_power: non_neg_integer(),
          defense: non_neg_integer(),
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
