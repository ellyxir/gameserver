defmodule Gameserver.Effects.DoTTest do
  use ExUnit.Case, async: true

  alias Gameserver.Effects.DoT
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
      assert DoT.valid?(%{base: 1, repeat_ms: 3000, kill_after_ms: 12_000}, source, target)
    end

    test "returns false when target is dead" do
      source = make_entity()
      target = make_entity(stats: [dead: true])
      refute DoT.valid?(%{base: 1, repeat_ms: 3000, kill_after_ms: 12_000}, source, target)
    end
  end

  describe "apply/3" do
    test "returns a transform that registers a tick on the entity" do
      source = make_entity()
      target = make_entity()
      transform = DoT.apply(%{base: 1, repeat_ms: 3000, kill_after_ms: 12_000}, source, target)
      updated = transform.(target)
      assert map_size(updated.ticks) == 1
    end

    test "registered tick applies periodic damage" do
      source = make_entity()
      target = make_entity()
      transform = DoT.apply(%{base: 3, repeat_ms: 3000, kill_after_ms: 12_000}, source, target)
      updated = transform.(target)

      {_tick_id, tick} = Enum.at(updated.ticks, 0)
      {damaged, :continue} = tick.transform.(updated)

      initial_hp = Stat.effective(updated.stats.hp, updated.stats)
      damaged_hp = Stat.effective(damaged.stats.hp, damaged.stats)
      assert damaged_hp == initial_hp - 3
    end

    test "registered tick has correct timing" do
      source = make_entity()
      target = make_entity()
      transform = DoT.apply(%{base: 1, repeat_ms: 2000, kill_after_ms: 10_000}, source, target)
      updated = transform.(target)

      {_tick_id, tick} = Enum.at(updated.ticks, 0)
      assert tick.repeat_ms == 2000
      assert tick.kill_after_ms == 10_000
    end

    test "multiple applications register independent ticks" do
      source = make_entity()
      target = make_entity()
      args = %{base: 1, repeat_ms: 3000, kill_after_ms: 12_000}
      t1 = DoT.apply(args, source, target)
      t2 = DoT.apply(args, source, target)
      updated = target |> t1.() |> t2.()
      assert map_size(updated.ticks) == 2
    end

    test "kill_after_ms defaults to nil when not provided" do
      source = make_entity()
      target = make_entity()
      transform = DoT.apply(%{base: 1, repeat_ms: 3000}, source, target)
      updated = transform.(target)

      {_tick_id, tick} = Enum.at(updated.ticks, 0)
      assert tick.kill_after_ms == nil
    end
  end
end
