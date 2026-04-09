defmodule Gameserver.AbilitiesTest do
  use ExUnit.Case, async: true

  alias Gameserver.Abilities
  alias Gameserver.Ability
  alias Gameserver.Effects.DirectDmg

  describe "get/1" do
    test "returns melee_strike ability" do
      assert {:ok, %Ability{id: :melee_strike} = ability} = Abilities.get(:melee_strike)
      assert ability.name == "Melee Strike"
      assert ability.range == 1
      assert ability.cooldown_ms == 1000
      assert ability.tags == [:physical, :melee]
      assert ability.effects == [{DirectDmg, %{base: 1}}]
    end

    test "returns upper_cut ability with more damage and longer cooldown" do
      assert {:ok, %Ability{id: :upper_cut} = ability} = Abilities.get(:upper_cut)
      assert ability.name == "Upper Cut"
      assert ability.range == 1
      assert ability.cooldown_ms == 1500
      assert ability.tags == [:physical, :melee]
      assert ability.effects == [{DirectDmg, %{base: 3}}]
    end

    test "returns error for unknown ability" do
      assert {:error, :not_found} = Abilities.get(:nonexistent)
    end
  end
end
