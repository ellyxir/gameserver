defmodule Gameserver.TickServerTest do
  use ExUnit.Case, async: true

  alias Gameserver.BaseStat
  alias Gameserver.CombatEvent
  alias Gameserver.CombatServer
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
          source_id: entity.id,
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
          source_id: entity.id,
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
          source_id: entity.id,
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
          source_id: entity.id,
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

  describe "tick damage broadcasting" do
    test "does not broadcast or run transform for dead entities", ctx do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, CombatServer.combat_topic())

      source = create_entity(ctx.entity_server)
      target = create_entity(ctx.entity_server)

      tick =
        Tick.new(
          transform: fn e ->
            hp = HpStat.apply_damage(e.stats.hp, 1)
            {%{e | stats: %{e.stats | hp: hp}}, :continue}
          end,
          source_id: source.id,
          repeat_ms: 30,
          kill_after_ms: 150
        )

      {:ok, _} =
        EntityServer.update_entity(
          target.id,
          fn e ->
            e
            |> Entity.register_tick(tick)
            |> Map.update!(:stats, &%{&1 | dead: true})
          end,
          ctx.entity_server
        )

      source_id = source.id
      target_id = target.id

      refute_receive {:combat_event,
                      %CombatEvent{attacker_id: ^source_id, defender_id: ^target_id}},
                     200
    end

    test "broadcasts a combat event when a tick deals damage", ctx do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, CombatServer.combat_topic())

      source = create_entity(ctx.entity_server)
      target = create_entity(ctx.entity_server)

      tick =
        Tick.new(
          transform: fn e ->
            hp = HpStat.apply_damage(e.stats.hp, 2)
            {%{e | stats: %{e.stats | hp: hp}}, :stop}
          end,
          source_id: source.id,
          repeat_ms: 50
        )

      {:ok, _updated} =
        EntityServer.update_entity(
          target.id,
          &Entity.register_tick(&1, tick),
          ctx.entity_server
        )

      assert_receive {:combat_event,
                      %CombatEvent{
                        attacker_id: attacker_id,
                        defender_id: defender_id,
                        damage: 2
                      }},
                     500

      assert attacker_id == source.id
      assert defender_id == target.id
    end
  end

  describe "death via tick" do
    test "marks entity dead when tick damage reduces hp to zero", ctx do
      target =
        create_entity(ctx.entity_server,
          stats: [hp: %HpStat{base_stat: %BaseStat{base: 1}}]
        )

      tick =
        Tick.new(
          transform: fn e ->
            hp = HpStat.apply_damage(e.stats.hp, 1)
            {%{e | stats: %{e.stats | hp: hp}}, :continue}
          end,
          source_id: target.id,
          repeat_ms: 50
        )

      {:ok, _} =
        EntityServer.update_entity(
          target.id,
          &Entity.register_tick(&1, tick),
          ctx.entity_server
        )

      Process.sleep(150)

      {:ok, updated} = EntityServer.get_entity(target.id, ctx.entity_server)
      assert Stat.effective(updated.stats.hp, updated.stats) == 0
      assert updated.stats.dead
    end

    test "broadcasts killing-blow combat event with dead: true", ctx do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, CombatServer.combat_topic())

      source = create_entity(ctx.entity_server)

      target =
        create_entity(ctx.entity_server,
          stats: [hp: %HpStat{base_stat: %BaseStat{base: 1}}]
        )

      tick =
        Tick.new(
          transform: fn e ->
            hp = HpStat.apply_damage(e.stats.hp, 1)
            {%{e | stats: %{e.stats | hp: hp}}, :continue}
          end,
          source_id: source.id,
          repeat_ms: 50
        )

      {:ok, _} =
        EntityServer.update_entity(
          target.id,
          &Entity.register_tick(&1, tick),
          ctx.entity_server
        )

      source_id = source.id
      target_id = target.id

      assert_receive {:combat_event,
                      %CombatEvent{
                        attacker_id: ^source_id,
                        defender_id: ^target_id,
                        dead: true
                      }},
                     500
    end
  end

  describe "ability integration" do
    test "multi-effect ability applies immediate damage and registers a dot tick", ctx do
      alias Gameserver.Ability
      alias Gameserver.Effects.DirectDmg
      alias Gameserver.Effects.DoT

      ability = %Ability{
        id: :test_poison,
        name: "Test Poison",
        tags: [:physical, :melee, :dot],
        range: 1,
        cooldown_ms: 1000,
        effects: [
          {DirectDmg, %{base: 1}},
          {DoT, %{base: 1, repeat_ms: 50, kill_after_ms: 200}}
        ]
      }

      source = create_entity(ctx.entity_server)
      target = create_entity(ctx.entity_server)
      initial_hp = Stat.effective(target.stats.hp, target.stats)

      transforms = CombatServer.execute_ability(ability, source, target)

      update_fn = fn entity ->
        Enum.reduce(transforms, entity, fn transform, acc -> transform.(acc) end)
      end

      {:ok, updated} = EntityServer.update_entity(target.id, update_fn, ctx.entity_server)

      # immediate damage from DirectDmg
      hp_after_hit = Stat.effective(updated.stats.hp, updated.stats)
      assert hp_after_hit == initial_hp - 1

      # DoT registered a tick
      assert map_size(updated.ticks) == 1

      # wait for tick server to execute a few ticks
      Process.sleep(150)

      {:ok, after_ticks} = EntityServer.get_entity(target.id, ctx.entity_server)
      hp_after_ticks = Stat.effective(after_ticks.stats.hp, after_ticks.stats)
      assert hp_after_ticks < hp_after_hit
    end
  end
end
