defmodule Gameserver.TickServerTest do
  use ExUnit.Case, async: true

  alias Gameserver.Entity
  alias Gameserver.EntityServer
  alias Gameserver.HpStat
  alias Gameserver.Stat
  alias Gameserver.Stats
  alias Gameserver.Tick
  alias Gameserver.TickServer

  setup do
    entity_server = start_supervised!({EntityServer, name: nil}, id: :entity_server)

    tick_server =
      start_supervised!(
        {TickServer, name: nil, entity_server: entity_server},
        id: :tick_server
      )

    {:ok, entity_server: entity_server, tick_server: tick_server}
  end

  defp create_entity(entity_server, opts \\ []) do
    stats = Stats.new(Keyword.get(opts, :stats, []))
    entity = Entity.new(name: "test", type: :mob, pos: {0, 0}, stats: stats)
    :ok = EntityServer.create_entity(entity, entity_server)
    entity
  end

  describe "tick execution" do
    test "schedules and executes a tick that damages the entity", ctx do
      entity = create_entity(ctx.entity_server)
      initial_hp = Stat.effective(entity.stats.hp, entity.stats)

      tick =
        Tick.new(
          transform: fn e ->
            hp = HpStat.apply_damage(e.stats.hp, 1)
            {%{e | stats: %{e.stats | hp: hp}}, :continue}
          end,
          repeat_ms: 50
        )

      {:ok, _updated} =
        EntityServer.update_entity(
          entity.id,
          &Entity.register_tick(&1, tick),
          ctx.entity_server
        )

      Process.sleep(150)

      {:ok, updated} = EntityServer.get_entity(entity.id, ctx.entity_server)
      current_hp = Stat.effective(updated.stats.hp, updated.stats)
      assert current_hp < initial_hp
    end

    test "stops ticking when transform returns :stop", ctx do
      entity = create_entity(ctx.entity_server)

      tick =
        Tick.new(
          transform: fn e -> {e, :stop} end,
          repeat_ms: 50
        )

      {:ok, _updated} =
        EntityServer.update_entity(
          entity.id,
          &Entity.register_tick(&1, tick),
          ctx.entity_server
        )

      Process.sleep(100)

      {:ok, updated} = EntityServer.get_entity(entity.id, ctx.entity_server)
      assert updated.ticks == %{}
    end

    test "removes tick after kill_after_ms expires", ctx do
      entity = create_entity(ctx.entity_server)

      tick =
        Tick.new(
          transform: fn e -> {e, :continue} end,
          repeat_ms: 50,
          kill_after_ms: 100
        )

      {:ok, _updated} =
        EntityServer.update_entity(
          entity.id,
          &Entity.register_tick(&1, tick),
          ctx.entity_server
        )

      Process.sleep(200)

      {:ok, updated} = EntityServer.get_entity(entity.id, ctx.entity_server)
      assert updated.ticks == %{}
    end

    test "runs on_kill when tick is removed by kill_after_ms", ctx do
      entity = create_entity(ctx.entity_server)

      tick =
        Tick.new(
          transform: fn e -> {e, :continue} end,
          on_kill: fn e -> %{e | stats: %{e.stats | defense: 99}} end,
          repeat_ms: 50,
          kill_after_ms: 100
        )

      {:ok, _updated} =
        EntityServer.update_entity(
          entity.id,
          &Entity.register_tick(&1, tick),
          ctx.entity_server
        )

      Process.sleep(200)

      {:ok, updated} = EntityServer.get_entity(entity.id, ctx.entity_server)
      assert updated.ticks == %{}
      assert updated.stats.defense == 99
    end
  end
end
