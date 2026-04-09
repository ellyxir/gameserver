defprotocol Gameserver.Stat do
  @doc """
  Returns the effective value of a stat, accounting for bonuses and
  any derivation from other stats.

  Base stats (STR, DEX, CON, etc.) return their base value plus bonuses.
  Derived stats (damage, max_hp, etc.) compute a value from other stats
  plus bonuses.
  """
  @spec effective(t(), Gameserver.Stats.t()) :: integer()
  def effective(stat, stats)
end
