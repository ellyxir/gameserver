defmodule Gameserver.MobTest do
  use ExUnit.Case, async: true

  alias Gameserver.CombatServer
  alias Gameserver.EntityServer
  alias Gameserver.Mob
  alias Gameserver.UUID
  alias Gameserver.WorldServer

  setup do
    entity_server = start_supervised!({EntityServer, name: nil}, id: :entity_server)

    world_server =
      start_supervised!(
        {WorldServer, name: nil, entity_server: entity_server},
        id: :world_server
      )

    combat_server =
      start_supervised!(
        {CombatServer, name: nil, entity_server: entity_server, world_server: world_server},
        id: :combat_server
      )

    {:ok, entity_server: entity_server, world_server: world_server, combat_server: combat_server}
  end

  describe "aggro" do
    test "sets aggro target when attacked", ctx do
      mob_id = UUID.generate()
      attacker_id = UUID.generate()

      mob = %Mob{
        id: mob_id,
        name: "goblin",
        spawn_pos: {12, 3},
        world_server: ctx.world_server
      }

      {:ok, pid} = Mob.start_link(mob)
      _ = :sys.get_state(pid)

      event = %{attacker_id: attacker_id, defender_id: mob_id, damage: 5, defender_hp: 95}
      send(pid, {:combat_event, event})

      state = :sys.get_state(pid)
      assert state.aggro_target == attacker_id
      assert state.attack_timer != nil
    end

    test "retaliates against aggro target on timer", ctx do
      mob_id = UUID.generate()
      player_id = UUID.generate()

      # join player first to get actual spawn position
      player = Gameserver.Entity.new(id: player_id, name: "hero", type: :user)
      {:ok, {px, py}} = WorldServer.join_entity(player, ctx.world_server)

      # place mob adjacent to player
      mob = %Mob{
        id: mob_id,
        name: "goblin",
        spawn_pos: {px + 1, py},
        world_server: ctx.world_server,
        combat_server: ctx.combat_server
      }

      {:ok, pid} = Mob.start_link(mob)
      _ = :sys.get_state(pid)

      event = %{attacker_id: player_id, defender_id: mob_id, damage: 5, defender_hp: 95}
      send(pid, {:combat_event, event})
      _ = :sys.get_state(pid)

      # manually fire the attack
      send(pid, :attack_target)
      _ = :sys.get_state(pid)

      {:ok, player_entity} = EntityServer.get_entity(player_id, ctx.entity_server)
      assert player_entity.stats.hp == 9
    end

    test "clears aggro when target leaves the world", ctx do
      mob_id = UUID.generate()
      player_id = UUID.generate()

      player = Gameserver.Entity.new(id: player_id, name: "hero", type: :user)
      {:ok, {px, py}} = WorldServer.join_entity(player, ctx.world_server)

      mob = %Mob{
        id: mob_id,
        name: "goblin",
        spawn_pos: {px + 1, py},
        world_server: ctx.world_server,
        combat_server: ctx.combat_server
      }

      {:ok, pid} = Mob.start_link(mob)
      _ = :sys.get_state(pid)

      event = %{attacker_id: player_id, defender_id: mob_id, damage: 5, defender_hp: 95}
      send(pid, {:combat_event, event})
      _ = :sys.get_state(pid)

      :ok = WorldServer.leave(player_id, ctx.world_server)

      send(pid, :attack_target)
      state = :sys.get_state(pid)

      assert state.aggro_target == nil
      assert state.attack_timer == nil
    end

    test "clears aggro when target moves out of range", ctx do
      mob_id = UUID.generate()
      player_id = UUID.generate()

      player = Gameserver.Entity.new(id: player_id, name: "hero", type: :user)
      {:ok, {px, py}} = WorldServer.join_entity(player, ctx.world_server)

      mob = %Mob{
        id: mob_id,
        name: "goblin",
        spawn_pos: {px + 1, py},
        world_server: ctx.world_server,
        combat_server: ctx.combat_server
      }

      {:ok, pid} = Mob.start_link(mob)
      _ = :sys.get_state(pid)

      event = %{attacker_id: player_id, defender_id: mob_id, damage: 5, defender_hp: 95}
      send(pid, {:combat_event, event})
      _ = :sys.get_state(pid)

      # walk player out of range (2 tiles south)
      {:ok, _} = WorldServer.move(player_id, :south, ctx.world_server)
      Process.sleep(WorldServer.move_cooldown_ms() + 10)
      {:ok, _} = WorldServer.move(player_id, :south, ctx.world_server)

      send(pid, :attack_target)
      state = :sys.get_state(pid)

      assert state.aggro_target == nil
      assert state.attack_timer == nil
    end
  end

  describe "init/1" do
    test "creates entity and joins the world", ctx do
      id = UUID.generate()

      mob = %Mob{
        id: id,
        name: "goblin",
        spawn_pos: {12, 3},
        world_server: ctx.world_server
      }

      {:ok, pid} = Mob.start_link(mob)

      # join_world is deferred, wait for it
      _ = :sys.get_state(pid)

      {:ok, pos} = WorldServer.get_position(id, ctx.world_server)
      assert pos == {12, 3}
    end
  end
end
