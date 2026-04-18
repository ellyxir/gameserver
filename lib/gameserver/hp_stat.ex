defmodule Gameserver.HpStat do
  @moduledoc """
  Current HP stat. Wraps a `BaseStat` for temp HP bonuses and clamps
  the effective value to never exceed effective max HP.
  """

  alias Gameserver.BaseStat

  defstruct base_stat: %BaseStat{}

  @typedoc "Current HP stat clamped to max HP."
  @type t() :: %__MODULE__{
          base_stat: BaseStat.t()
        }

  @spec apply_damage(t(), non_neg_integer()) :: t()
  def apply_damage(%__MODULE__{} = hp_stat, dmg) do
    apply_delta(hp_stat, -dmg)
  end

  @doc """
  applies the health change
  positive delta will heal, negative will damage
  """
  @spec apply_delta(t(), integer()) :: t()
  def apply_delta(%__MODULE__{base_stat: base_stat} = hp, delta) do
    updated_hp = max(0, base_stat.base + delta)
    %{hp | base_stat: %{base_stat | base: updated_hp}}
  end
end

defimpl Gameserver.Stat, for: Gameserver.HpStat do
  alias Gameserver.Stat

  def effective(%Gameserver.HpStat{base_stat: base_stat}, stats) do
    raw = Stat.effective(base_stat, stats)
    max_hp = Stat.effective(stats.max_hp, stats)
    min(raw, max_hp)
  end
end
