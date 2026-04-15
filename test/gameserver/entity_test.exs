defmodule Gameserver.EntityTest do
  use ExUnit.Case, async: true

  alias Gameserver.Entity
  alias Gameserver.Stats
  alias Gameserver.Tick
  alias Gameserver.UUID

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
      stats = Stats.new(attack_power: 2)
      entity = Entity.new(name: "goblin", type: :mob, pos: {3, 4}, stats: stats)
      assert entity.type == :mob
      assert entity.name == "goblin"
      assert entity.stats.attack_power == 2
    end

    test "raises on unknown keys" do
      assert_raise KeyError, fn ->
        Entity.new(name: "alice", type: :user, pos: {0, 0}, mana: 100)
      end
    end

    test "accepts an explicit id" do
      id = UUID.generate()
      entity = Entity.new(id: id, name: "bob", type: :user, pos: {0, 0})
      assert entity.id == id
    end
  end

  describe "new/1 ticks" do
    test "defaults to an empty ticks map" do
      entity = Entity.new(name: "alice", type: :user, pos: {0, 0})
      assert entity.ticks == %{}
    end
  end

  describe "register_tick/2" do
    test "adds a tick to the entity's ticks map" do
      entity = Entity.new(name: "test", type: :mob, pos: {0, 0})

      tick =
        Tick.new(transform: fn e -> {e, :continue} end, source_id: entity.id, repeat_ms: 3000)

      updated = Entity.register_tick(entity, tick)
      assert Map.has_key?(updated.ticks, tick.id)
      assert updated.ticks[tick.id] == tick
    end
  end

  describe "remove_tick/2" do
    test "removes a tick by id and runs on_kill" do
      entity = Entity.new(name: "test", type: :mob, pos: {0, 0})

      on_kill = fn e ->
        %{e | stats: %{e.stats | defense: 99}}
      end

      tick =
        Tick.new(
          transform: fn e -> {e, :continue} end,
          source_id: entity.id,
          repeat_ms: 3000,
          on_kill: on_kill
        )

      entity = Entity.register_tick(entity, tick)
      updated = Entity.remove_tick(entity, tick.id)
      assert updated.ticks == %{}
      assert updated.stats.defense == 99
    end

    test "returns entity unchanged when tick id not found" do
      entity = Entity.new(name: "test", type: :mob, pos: {0, 0})
      updated = Entity.remove_tick(entity, UUID.generate())
      assert updated == entity
    end
  end

  describe "get_tick/2" do
    test "returns the tick when it exists" do
      entity = Entity.new(name: "test", type: :mob, pos: {0, 0})

      tick =
        Tick.new(transform: fn e -> {e, :continue} end, source_id: entity.id, repeat_ms: 3000)

      entity = Entity.register_tick(entity, tick)
      assert {:ok, ^tick} = Entity.get_tick(entity, tick.id)
    end

    test "returns :error when tick id not found" do
      entity = Entity.new(name: "test", type: :mob, pos: {0, 0})
      assert :error = Entity.get_tick(entity, UUID.generate())
    end
  end

  describe "id/1" do
    test "returns the entity id" do
      entity = Entity.new(name: "alice", type: :user, pos: {1, 1})
      assert Entity.id(entity) == entity.id
    end
  end
end
