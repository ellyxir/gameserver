defmodule Gameserver.BaseStatTest do
  use ExUnit.Case, async: true

  alias Gameserver.BaseStat
  alias Gameserver.Stat
  alias Gameserver.UUID

  describe "effective/2" do
    test "returns base when no bonuses" do
      stat = %BaseStat{base: 10, bonuses: []}
      assert Stat.effective(stat, %Gameserver.Stats{}) == 10
    end

    test "sums bonuses with base" do
      stat = %BaseStat{base: 10, bonuses: [{3, UUID.generate()}, {5, UUID.generate()}]}
      assert Stat.effective(stat, %Gameserver.Stats{}) == 18
    end
  end

  describe "add_bonus/2" do
    test "adds a bonus with a generated id" do
      stat = %BaseStat{base: 10, bonuses: []}
      {stat, id} = BaseStat.add_bonus(stat, 5)
      assert [{5, ^id}] = stat.bonuses
      assert is_binary(id)
    end
  end

  describe "remove_bonus/2" do
    test "removes bonus by id" do
      id1 = UUID.generate()
      id2 = UUID.generate()
      stat = %BaseStat{base: 10, bonuses: [{5, id1}, {3, id2}]}
      stat = BaseStat.remove_bonus(stat, id1)
      assert stat.bonuses == [{3, id2}]
    end

    test "removes all bonuses with the same id" do
      id = UUID.generate()
      stat = %BaseStat{base: 10, bonuses: [{5, id}, {3, id}]}
      stat = BaseStat.remove_bonus(stat, id)
      assert stat.bonuses == []
    end

    test "no-op when id not found" do
      id1 = UUID.generate()
      id2 = UUID.generate()
      stat = %BaseStat{base: 10, bonuses: [{5, id1}]}
      assert BaseStat.remove_bonus(stat, id2).bonuses == [{5, id1}]
    end
  end
end
