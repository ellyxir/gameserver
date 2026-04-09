defmodule Gameserver.MaxHpStat do
  @moduledoc """
  Derived stat for maximum HP. Computes a base value from CON and
  delegates bonus handling to an inner `BaseStat`.
  """

  alias Gameserver.BaseStat

  defstruct base_stat: %BaseStat{}

  @typedoc "A derived max HP stat backed by a BaseStat for bonuses."
  @type t() :: %__MODULE__{
          base_stat: BaseStat.t()
        }
end

defimpl Gameserver.Stat, for: Gameserver.MaxHpStat do
  alias Gameserver.Stat

  @base_hp 10
  @hp_per_con 2

  def effective(%Gameserver.MaxHpStat{base_stat: base_stat}, stats) do
    con = Stat.effective(stats.con, stats)
    derived = @base_hp + con * @hp_per_con
    derived + Stat.effective(base_stat, stats)
  end
end
