defmodule Gameserver.TickTest do
  use ExUnit.Case, async: true

  alias Gameserver.Tick
  alias Gameserver.UUID

  describe "new/1" do
    test "generates a UUID id" do
      tick = Tick.new(transform: &{&1, :continue}, source_id: UUID.generate(), repeat_ms: 3000)
      assert is_binary(tick.id)
      assert String.length(tick.id) == 36
    end

    test "stores the transform function" do
      transform = fn entity -> {entity, :continue} end
      tick = Tick.new(transform: transform, source_id: UUID.generate(), repeat_ms: 3000)
      assert tick.transform == transform
    end

    test "stores repeat_ms" do
      tick = Tick.new(transform: &{&1, :continue}, source_id: UUID.generate(), repeat_ms: 5000)
      assert tick.repeat_ms == 5000
    end

    test "defaults on_kill to identity" do
      tick = Tick.new(transform: &{&1, :continue}, source_id: UUID.generate(), repeat_ms: 3000)
      assert tick.on_kill.(:anything) == :anything
    end

    test "defaults kill_after_ms to nil" do
      tick = Tick.new(transform: &{&1, :continue}, source_id: UUID.generate(), repeat_ms: 3000)
      assert tick.kill_after_ms == nil
    end

    test "accepts optional on_kill" do
      on_kill = fn entity -> Map.put(entity, :cleaned, true) end

      tick =
        Tick.new(
          transform: &{&1, :continue},
          source_id: UUID.generate(),
          repeat_ms: 3000,
          on_kill: on_kill
        )

      assert tick.on_kill == on_kill
    end

    test "accepts optional kill_after_ms" do
      tick =
        Tick.new(
          transform: &{&1, :continue},
          source_id: UUID.generate(),
          repeat_ms: 3000,
          kill_after_ms: 15_000
        )

      assert tick.kill_after_ms == 15_000
    end
  end
end
