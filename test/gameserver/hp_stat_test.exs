defmodule Gameserver.HpStatTest do
  use ExUnit.Case, async: true

  alias Gameserver.BaseStat
  alias Gameserver.Effect
  alias Gameserver.HpStat
  alias Gameserver.MaxHpStat
  alias Gameserver.Stat
  alias Gameserver.Stats

  # con 10 -> max_hp = 10 + 10*2 = 30
  @default_max %MaxHpStat{}

  describe "effective/2" do
    test "returns base hp value" do
      stats = Stats.new(hp: %HpStat{base_stat: %BaseStat{base: 30}}, max_hp: @default_max)
      assert Stat.effective(stats.hp, stats) == 30
    end

    test "clamps to max hp" do
      stats = Stats.new(hp: %HpStat{base_stat: %BaseStat{base: 999}}, max_hp: @default_max)
      assert Stat.effective(stats.hp, stats) == 30
    end

    test "temp hp bonus adds to effective value" do
      effect = %Effect{name: "temp hp"}
      inner = BaseStat.add_bonus(%BaseStat{base: 20}, 5, effect)
      stats = Stats.new(hp: %HpStat{base_stat: inner}, max_hp: @default_max)
      assert Stat.effective(stats.hp, stats) == 25
    end

    test "temp hp bonus still clamps to max hp" do
      effect = %Effect{name: "temp hp"}
      inner = BaseStat.add_bonus(%BaseStat{base: 28}, 10, effect)
      stats = Stats.new(hp: %HpStat{base_stat: inner}, max_hp: @default_max)
      assert Stat.effective(stats.hp, stats) == 30
    end
  end

  describe "apply_damage/2" do
    test "reduces base hp by damage amount" do
      hp = %HpStat{base_stat: %BaseStat{base: 10}}
      hp = HpStat.apply_damage(hp, 3)
      assert hp.base_stat.base == 7
    end

    test "floors at zero" do
      hp = %HpStat{base_stat: %BaseStat{base: 5}}
      hp = HpStat.apply_damage(hp, 50)
      assert hp.base_stat.base == 0
    end
  end
end
