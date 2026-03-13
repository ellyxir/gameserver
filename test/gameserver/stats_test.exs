defmodule Gameserver.StatsTest do
  use ExUnit.Case, async: true

  alias Gameserver.Stats

  describe "new/1" do
    test "creates stats with default values" do
      stats = Stats.new()
      assert stats.hp == 10
      assert stats.max_hp == 10
      assert stats.attack_power == 1
    end

    test "accepts keyword overrides" do
      stats = Stats.new(hp: 50, max_hp: 50, attack_power: 5)
      assert stats.hp == 50
      assert stats.max_hp == 50
      assert stats.attack_power == 5
    end

    test "raises on unknown keys" do
      assert_raise KeyError, fn ->
        Stats.new(mana: 100)
      end
    end
  end
end
