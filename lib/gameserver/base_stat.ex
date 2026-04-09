defmodule Gameserver.BaseStat do
  @moduledoc """
  A base stat like STR, DEX, CON, or HP. Stores a base integer value
  and a list of bonuses from effects and equipment. Effective value is
  base + sum of bonuses.

  Implements the `Gameserver.Stat` protocol. Derived stats (damage,
  max_hp) use separate modules that compute their base from other stats.
  """

  alias Gameserver.Effect

  defstruct base: 0, bonuses: []

  @typedoc "A base stat with an integer value and a list of effect-linked bonuses."
  @type t() :: %__MODULE__{
          base: integer(),
          bonuses: [{integer(), Effect.t()}]
        }

  @spec add_bonus(t(), integer(), Effect.t()) :: t()
  def add_bonus(%__MODULE__{bonuses: bonuses} = base_stat, amt, %Effect{} = effect) do
    bonuses = [{amt, effect} | bonuses]
    %{base_stat | bonuses: bonuses}
  end

  @spec remove_bonus(t(), Effect.t()) :: t()
  def remove_bonus(%__MODULE__{bonuses: bonuses} = base_stat, %Effect{} = effect) do
    bonuses = Enum.reject(bonuses, fn {_amt, e} -> e == effect end)
    %{base_stat | bonuses: bonuses}
  end
end

defimpl Gameserver.Stat, for: Gameserver.BaseStat do
  def effective(
        %Gameserver.BaseStat{base: base, bonuses: bonuses} = _stat,
        %Gameserver.Stats{} = _stats
      ) do
    Enum.reduce(bonuses, base, fn {bonus, _effect}, acc -> bonus + acc end)
  end
end
