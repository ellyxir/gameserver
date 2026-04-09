defmodule Gameserver.StatsTest do
  use ExUnit.Case, async: true

  alias Gameserver.BaseStat
  alias Gameserver.Stats

  describe "new/1" do
    test "creates stats with default values" do
      stats = Stats.new()
      assert stats.hp == 10
      assert stats.max_hp == 10
      assert stats.attack_power == 1
      assert stats.str == %BaseStat{base: 10}
      assert stats.dex == %BaseStat{base: 10}
      assert stats.con == %BaseStat{base: 10}
    end

    test "accepts keyword overrides" do
      stats = Stats.new(hp: 50, max_hp: 50, attack_power: 5)
      assert stats.hp == 50
      assert stats.max_hp == 50
      assert stats.attack_power == 5
    end

    test "accepts base stat overrides" do
      stats = Stats.new(str: %BaseStat{base: 18}, dex: %BaseStat{base: 14})
      assert stats.str == %BaseStat{base: 18}
      assert stats.dex == %BaseStat{base: 14}
      assert stats.con == %BaseStat{base: 10}
    end

    test "raises on unknown keys" do
      assert_raise KeyError, fn ->
        Stats.new(mana: 100)
      end
    end
  end
end
