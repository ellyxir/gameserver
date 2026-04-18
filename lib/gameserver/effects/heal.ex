defmodule Gameserver.Effects.Heal do
  @moduledoc """
  Direct Heal
  """

  @behaviour Gameserver.Effect

  alias Gameserver.Entity
  alias Gameserver.HpStat
  alias Gameserver.Stat
  alias Gameserver.Stats

  @spec valid?(args :: map(), source :: Entity.t(), target :: Entity.t()) :: boolean()

  # players can heal players, mobs can heal mobs and target is not dead
  def valid?(_args, %Entity{type: type}, %Entity{stats: %Stats{dead: false}, type: type}),
    do: true

  def valid?(_args, _source, _target), do: false

  @spec apply(args :: map(), source :: Entity.t(), target :: Entity.t()) ::
          Gameserver.Effect.transform()
  def apply(%{base: base}, _source, %Entity{}) do
    fn %Entity{stats: stats} = entity ->
      # avoid overhealing
      max_hp = Stat.effective(stats.max_hp, stats)
      current_hp = Stat.effective(stats.hp, stats)
      clamped_heal = min(base, max_hp - current_hp)
      hp = HpStat.apply_delta(stats.hp, clamped_heal)
      %{entity | stats: %{stats | hp: hp}}
    end
  end
end
