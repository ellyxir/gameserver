defmodule Gameserver.BaseStat do
  @moduledoc """
  A base stat like STR, DEX, CON, or HP. Stores a base integer value
  and a list of bonuses from effects and equipment. Effective value is
  base + sum of bonuses.

  Implements the `Gameserver.Stat` protocol. Derived stats (damage,
  max_hp) use separate modules that compute their base from other stats.
  """

  alias Gameserver.UUID

  defstruct base: 0, bonuses: []

  @typep bonus() :: {amount :: integer(), effect_id :: UUID.t()}

  @typedoc "A base stat with an integer value and a list of bonuses."
  @type t() :: %__MODULE__{
          base: integer(),
          bonuses: [bonus()]
        }

  @doc """
  Adds a bonus to the stat and returns the updated stat with the generated id.
  """
  @spec add_bonus(t(), amount :: integer()) :: {t(), effect_id :: UUID.t()}
  def add_bonus(%__MODULE__{bonuses: bonuses} = base_stat, amt) do
    id = UUID.generate()
    {%{base_stat | bonuses: [{amt, id} | bonuses]}, id}
  end

  @doc """
  Removes all bonuses with the given id.
  """
  @spec remove_bonus(t(), effect_id :: UUID.t()) :: t()
  def remove_bonus(%__MODULE__{bonuses: bonuses} = base_stat, id) when is_binary(id) do
    bonuses = Enum.reject(bonuses, fn {_amt, bonus_id} -> bonus_id == id end)
    %{base_stat | bonuses: bonuses}
  end
end

defimpl Gameserver.Stat, for: Gameserver.BaseStat do
  def effective(
        %Gameserver.BaseStat{base: base, bonuses: bonuses} = _stat,
        %Gameserver.Stats{} = _stats
      ) do
    Enum.reduce(bonuses, base, fn {bonus, _effect_id}, acc -> bonus + acc end)
  end
end
