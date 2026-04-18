defmodule Gameserver.Effects.DirectDmgTest do
  use ExUnit.Case, async: true

  alias Gameserver.Effects.DirectDmg
  alias Gameserver.Entity
  alias Gameserver.Stat
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

    test "returns false when source and target are the same entity" do
      entity = make_entity()
      refute DirectDmg.valid?(%{base: 10}, entity, entity)
    end
  end

  describe "apply/3" do
    test "returns a transform that applies full base damage when target has no defense" do
      source = make_entity()
      target = make_entity()
      transform = DirectDmg.apply(%{base: 10}, source, target)
      updated = transform.(target)
      assert Stat.effective(updated.stats.hp, updated.stats) == 0
    end

    test "returns a transform that subtracts target defense from base damage" do
      source = make_entity()
      target = make_entity(stats: [defense: 3])
      transform = DirectDmg.apply(%{base: 10}, source, target)
      updated = transform.(target)
      assert Stat.effective(updated.stats.hp, updated.stats) == 3
    end

    test "returns a transform that floors damage at zero when defense exceeds base" do
      source = make_entity()
      target = make_entity(stats: [defense: 50])
      transform = DirectDmg.apply(%{base: 10}, source, target)
      updated = transform.(target)
      assert Stat.effective(updated.stats.hp, updated.stats) == 10
    end

    test "returns a transform that does zero damage when defense equals base" do
      source = make_entity()
      target = make_entity(stats: [defense: 10])
      transform = DirectDmg.apply(%{base: 10}, source, target)
      updated = transform.(target)
      assert Stat.effective(updated.stats.hp, updated.stats) == 10
    end

    test "returns a transform that does zero damage with zero base" do
      source = make_entity()
      target = make_entity()
      transform = DirectDmg.apply(%{base: 0}, source, target)
      updated = transform.(target)
      assert Stat.effective(updated.stats.hp, updated.stats) == 10
    end
  end
end
