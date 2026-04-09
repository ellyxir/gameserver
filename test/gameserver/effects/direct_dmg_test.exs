defmodule Gameserver.Effects.DirectDmgTest do
  use ExUnit.Case, async: true

  alias Gameserver.Effects.DirectDmg
  alias Gameserver.Entity
  alias Gameserver.Stats

  defp make_entity(opts \\ []) do
    stats = Stats.new(Keyword.get(opts, :stats, []))
    Entity.new(name: "test", type: :mob, pos: {0, 0}, stats: stats)
  end

  describe "valid?/3" do
    test "returns true when target is alive" do
      source = make_entity()
      target = make_entity()
      assert DirectDmg.valid?(%{base: 10}, source, target)
    end

    test "returns false when target is dead" do
      source = make_entity()
      target = make_entity(stats: [dead: true])
      refute DirectDmg.valid?(%{base: 10}, source, target)
    end
  end

  describe "apply/3" do
    test "returns damage intent with full base damage when target has no defense" do
      source = make_entity()
      target = make_entity()
      assert {:ok, {:damage, 10}} = DirectDmg.apply(%{base: 10}, source, target)
    end

    test "subtracts target defense from base damage" do
      source = make_entity()
      target = make_entity(stats: [defense: 3])
      assert {:ok, {:damage, 7}} = DirectDmg.apply(%{base: 10}, source, target)
    end

    test "floors damage at zero when defense exceeds base" do
      source = make_entity()
      target = make_entity(stats: [defense: 50])
      assert {:ok, {:damage, 0}} = DirectDmg.apply(%{base: 10}, source, target)
    end

    test "returns zero damage when defense equals base" do
      source = make_entity()
      target = make_entity(stats: [defense: 10])
      assert {:ok, {:damage, 0}} = DirectDmg.apply(%{base: 10}, source, target)
    end

    test "returns zero damage with zero base" do
      source = make_entity()
      target = make_entity()
      assert {:ok, {:damage, 0}} = DirectDmg.apply(%{base: 0}, source, target)
    end
  end
end
