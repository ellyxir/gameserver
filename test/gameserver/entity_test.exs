defmodule Gameserver.EntityTest do
  use ExUnit.Case, async: true

  alias Gameserver.Entity
  alias Gameserver.Stats

  describe "new/1" do
    test "creates a user entity with defaults" do
      entity = Entity.new(name: "alice", type: :user, pos: {1, 1})
      assert entity.name == "alice"
      assert entity.type == :user
      assert entity.pos == {1, 1}
      assert %Stats{} = entity.stats
      assert %Gameserver.Cooldowns{} = entity.cooldowns
      assert is_binary(entity.id)
    end

    test "creates a mob entity with custom stats" do
      stats = Stats.new(hp: 5, max_hp: 5, attack_power: 2)
      entity = Entity.new(name: "goblin", type: :mob, pos: {3, 4}, stats: stats)
      assert entity.type == :mob
      assert entity.name == "goblin"
      assert entity.stats.hp == 5
      assert entity.stats.attack_power == 2
    end

    test "raises on unknown keys" do
      assert_raise KeyError, fn ->
        Entity.new(name: "alice", type: :user, pos: {0, 0}, mana: 100)
      end
    end

    test "accepts an explicit id" do
      id = Ecto.UUID.generate()
      entity = Entity.new(id: id, name: "bob", type: :user, pos: {0, 0})
      assert entity.id == id
    end
  end

  describe "id/1" do
    test "returns the entity id" do
      entity = Entity.new(name: "alice", type: :user, pos: {1, 1})
      assert Entity.id(entity) == entity.id
    end
  end
end
