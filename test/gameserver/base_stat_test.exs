defmodule Gameserver.BaseStatTest do
  use ExUnit.Case, async: true

  alias Gameserver.BaseStat
  alias Gameserver.Effect
  alias Gameserver.Stat

  @effect %Effect{name: "test buff"}
  @other_effect %Effect{name: "other buff"}

  describe "effective/2" do
    test "returns base when no bonuses" do
      stat = %BaseStat{base: 10, bonuses: []}
      assert Stat.effective(stat, %Gameserver.Stats{}) == 10
    end

    test "sums bonuses with base" do
      stat = %BaseStat{base: 10, bonuses: [{3, @effect}, {5, @other_effect}]}
      assert Stat.effective(stat, %Gameserver.Stats{}) == 18
    end
  end

  describe "add_bonus/3" do
    test "adds a bonus to empty list" do
      stat = %BaseStat{base: 10, bonuses: []}
      stat = BaseStat.add_bonus(stat, 5, @effect)
      assert stat.bonuses == [{5, @effect}]
    end
  end

  describe "remove_bonus/2" do
    test "removes bonus by effect reference" do
      stat = %BaseStat{base: 10, bonuses: [{5, @effect}, {3, @other_effect}]}
      stat = BaseStat.remove_bonus(stat, @effect)
      assert stat.bonuses == [{3, @other_effect}]
    end

    test "removes all bonuses from the same effect" do
      stat = %BaseStat{base: 10, bonuses: [{5, @effect}, {3, @effect}]}
      stat = BaseStat.remove_bonus(stat, @effect)
      assert stat.bonuses == []
    end

    test "no-op when effect not found" do
      stat = %BaseStat{base: 10, bonuses: [{5, @effect}]}
      assert BaseStat.remove_bonus(stat, @other_effect) == stat
    end
  end
end
