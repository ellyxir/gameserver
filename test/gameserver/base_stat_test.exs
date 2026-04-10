defmodule Gameserver.BaseStatTest do
  use ExUnit.Case, async: true

  alias Gameserver.BaseStat
  alias Gameserver.Effect
  alias Gameserver.Stat

  defp effect(name \\ "test buff"), do: Effect.new(name)

  describe "effective/2" do
    test "returns base when no bonuses" do
      stat = %BaseStat{base: 10, bonuses: []}
      assert Stat.effective(stat, %Gameserver.Stats{}) == 10
    end

    test "sums bonuses with base" do
      e1 = effect()
      e2 = effect("other buff")
      stat = %BaseStat{base: 10, bonuses: [{3, e1}, {5, e2}]}
      assert Stat.effective(stat, %Gameserver.Stats{}) == 18
    end
  end

  describe "add_bonus/3" do
    test "adds a bonus to empty list" do
      e = effect()
      stat = %BaseStat{base: 10, bonuses: []}
      stat = BaseStat.add_bonus(stat, 5, e)
      assert [{5, ^e}] = stat.bonuses
    end
  end

  describe "remove_bonus/2" do
    test "removes bonus by effect id" do
      e1 = effect()
      e2 = effect("other buff")
      stat = %BaseStat{base: 10, bonuses: [{5, e1}, {3, e2}]}
      stat = BaseStat.remove_bonus(stat, e1)
      assert stat.bonuses == [{3, e2}]
    end

    test "removes all bonuses with the same id" do
      e = effect()
      stat = %BaseStat{base: 10, bonuses: [{5, e}, {3, e}]}
      stat = BaseStat.remove_bonus(stat, e)
      assert stat.bonuses == []
    end

    test "no-op when effect id not found" do
      e1 = effect()
      e2 = effect("other buff")
      stat = %BaseStat{base: 10, bonuses: [{5, e1}]}
      assert BaseStat.remove_bonus(stat, e2).bonuses == [{5, e1}]
    end

    test "removes only the bonus with the matching id, not same-name effects" do
      effect_a = effect("buff")
      effect_b = effect("buff")
      stat = %BaseStat{base: 10, bonuses: [{5, effect_a}, {3, effect_b}]}
      stat = BaseStat.remove_bonus(stat, effect_a)
      assert stat.bonuses == [{3, effect_b}]
    end
  end
end
