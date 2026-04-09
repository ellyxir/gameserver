defmodule Gameserver.MaxHpStatTest do
  use ExUnit.Case, async: true

  alias Gameserver.BaseStat
  alias Gameserver.MaxHpStat
  alias Gameserver.Stat
  alias Gameserver.Stats

  describe "effective/2" do
    test "derives from con" do
      stats = Stats.new(max_hp: %MaxHpStat{}, con: %BaseStat{base: 12})
      # 10 + 12*2
      assert Stat.effective(stats.max_hp, stats) == 34
    end

    test "includes bonuses from inner base stat" do
      effect = %Gameserver.Effect{name: "fortitude"}
      inner = BaseStat.add_bonus(%BaseStat{}, 20, effect)
      stats = Stats.new(max_hp: %MaxHpStat{base_stat: inner}, con: %BaseStat{base: 10})
      # 10 + 10*2 (from con) + 20 (bonus)
      assert Stat.effective(stats.max_hp, stats) == 50
    end

    test "con bonuses flow through to max hp" do
      effect = %Gameserver.Effect{name: "con buff"}
      con = BaseStat.add_bonus(%BaseStat{base: 10}, 4, effect)
      stats = Stats.new(max_hp: %MaxHpStat{}, con: con)
      # 10 + (10+4)*2
      assert Stat.effective(stats.max_hp, stats) == 38
    end
  end
end
