defmodule Gameserver.AbilityTest do
  use ExUnit.Case, async: true

  alias Gameserver.Ability
  alias Gameserver.Effects.DirectDmg

  describe "struct" do
    test "creates ability with all fields" do
      ability = %Ability{
        id: :fireball,
        name: "Fireball",
        tags: [:fire, :spell],
        range: 3,
        cooldown_ms: 2000,
        effects: [{DirectDmg, %{base: 80}}]
      }

      assert ability.id == :fireball
      assert ability.name == "Fireball"
      assert ability.tags == [:fire, :spell]
      assert ability.range == 3
      assert ability.cooldown_ms == 2000
      assert ability.effects == [{DirectDmg, %{base: 80}}]
    end

    test "defaults tags to empty list" do
      ability = %Ability{id: :strike, name: "Strike", range: 1, cooldown_ms: 1000}
      assert ability.tags == []
    end

    test "defaults effects to empty list" do
      ability = %Ability{id: :strike, name: "Strike", range: 1, cooldown_ms: 1000}
      assert ability.effects == []
    end
  end
end
