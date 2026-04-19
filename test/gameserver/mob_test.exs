defmodule Gameserver.MobTest do
  use ExUnit.Case, async: true

  alias Gameserver.CombatEvent
  alias Gameserver.CombatServer
  alias Gameserver.EntityServer
  alias Gameserver.Map, as: GameMap
  alias Gameserver.Mob
  alias Gameserver.UUID
  alias Gameserver.WorldServer

  defp floor_pos(server, room_index \\ 0) do
    map = WorldServer.get_map(server)
    room = Enum.at(map.rooms, rem(room_index, length(map.rooms)))
    GameMap.random_tile_in_room(map, room)
  end

  setup do
    entity_server = start_supervised!({EntityServer, name: nil}, id: :entity_server)

    world_server =
      start_supervised!(
        {WorldServer, name: nil, entity_server: entity_server, map: GameMap.sample_dungeon()},
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
        spawn_pos: floor_pos(ctx.world_server),
        entity_server: ctx.entity_server,
        world_server: ctx.world_server
      }

      {:ok, pid} = Mob.start_link(mob)
      _ = :sys.get_state(pid)

      event = %CombatEvent{
        attacker_id: attacker_id,
        defender_id: mob_id,
        damage: 5,
        defender_hp: 95
      }

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
        abilities: [:melee_strike],
        entity_server: ctx.entity_server,
        world_server: ctx.world_server,
        combat_server: ctx.combat_server
      }

      {:ok, pid} = Mob.start_link(mob)
      _ = :sys.get_state(pid)

      # subscribe to combat events so we can wait for the retaliation
      Phoenix.PubSub.subscribe(Gameserver.PubSub, CombatServer.combat_topic())

      event = %CombatEvent{
        attacker_id: player_id,
        defender_id: mob_id,
        damage: 5,
        defender_hp: 95
      }

      send(pid, {:combat_event, event})

      # wait for the mob's retaliation attack (fires via 0ms timer)
      assert_receive {:combat_event, %CombatEvent{attacker_id: ^mob_id, defender_id: ^player_id}}

      {:ok, player_entity} = EntityServer.get_entity(player_id, ctx.entity_server)
      player_hp = Gameserver.Stat.effective(player_entity.stats.hp, player_entity.stats)
      assert player_hp == 9
    end

    test "moves when not aggro'd", ctx do
      mob_id = UUID.generate()

      mob = %Mob{
        id: mob_id,
        name: "goblin",
        spawn_pos: floor_pos(ctx.world_server),
        entity_server: ctx.entity_server,
        world_server: ctx.world_server
      }

      {:ok, pid} = Mob.start_link(mob)
      _ = :sys.get_state(pid)

      {:ok, pos_before} = WorldServer.get_position(mob_id, ctx.world_server)

      # send multiple moves since random direction may hit a wall
      for _ <- 1..10 do
        send(pid, :mob_move)
        _ = :sys.get_state(pid)
      end

      {:ok, pos_after} = WorldServer.get_position(mob_id, ctx.world_server)
      assert pos_after != pos_before
    end

    test "does not move while aggro'd", ctx do
      mob_id = UUID.generate()
      player_id = UUID.generate()

      player = Gameserver.Entity.new(id: player_id, name: "hero", type: :user)
      {:ok, {px, py}} = WorldServer.join_entity(player, ctx.world_server)

      mob = %Mob{
        id: mob_id,
        name: "goblin",
        spawn_pos: {px + 1, py},
        abilities: [:melee_strike],
        entity_server: ctx.entity_server,
        world_server: ctx.world_server,
        combat_server: ctx.combat_server
      }

      {:ok, pid} = Mob.start_link(mob)
      _ = :sys.get_state(pid)

      {:ok, pos_before} = WorldServer.get_position(mob_id, ctx.world_server)

      event = %CombatEvent{
        attacker_id: player_id,
        defender_id: mob_id,
        damage: 5,
        defender_hp: 95
      }

      send(pid, {:combat_event, event})
      _ = :sys.get_state(pid)

      send(pid, :mob_move)
      _ = :sys.get_state(pid)

      {:ok, pos_after} = WorldServer.get_position(mob_id, ctx.world_server)
      assert pos_after == pos_before
    end

    test "dead mob leaves the world", ctx do
      mob_id = UUID.generate()
      player_id = UUID.generate()

      player = Gameserver.Entity.new(id: player_id, name: "hero", type: :user)
      {:ok, {px, py}} = WorldServer.join_entity(player, ctx.world_server)

      mob = %Mob{
        id: mob_id,
        name: "goblin",
        spawn_pos: {px + 1, py},
        entity_server: ctx.entity_server,
        world_server: ctx.world_server,
        combat_server: ctx.combat_server
      }

      {:ok, pid} = Mob.start_link(mob)
      _ = :sys.get_state(pid)

      event = %CombatEvent{
        attacker_id: player_id,
        defender_id: mob_id,
        damage: 50,
        defender_hp: 0,
        dead: true
      }

      # check that the process exits
      ref = Process.monitor(pid)
      send(pid, {:combat_event, event})
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

      # check that mob left the world server
      assert {:error, :not_found} = WorldServer.get_position(mob_id, ctx.world_server)
    end

    test "dead mob respawns after delay", ctx do
      mob_id = UUID.generate()
      player_id = UUID.generate()

      mob_server =
        start_supervised!(
          {Gameserver.MobServer,
           world_server: ctx.world_server, mob_count: 0, entity_server: ctx.entity_server},
          id: :mob_server
        )

      player = Gameserver.Entity.new(id: player_id, name: "hero", type: :user)
      {:ok, {px, py}} = WorldServer.join_entity(player, ctx.world_server)

      spawn_pos = {px + 1, py}

      mob = %Mob{
        id: mob_id,
        name: "goblin",
        spawn_pos: spawn_pos,
        entity_server: ctx.entity_server,
        world_server: ctx.world_server,
        combat_server: ctx.combat_server,
        mob_server: mob_server,
        respawn_delay_ms: 100
      }

      {:ok, pid} = Mob.start_link(mob)
      _ = :sys.get_state(pid)

      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())

      event = %CombatEvent{
        attacker_id: player_id,
        defender_id: mob_id,
        damage: 50,
        defender_hp: 0,
        dead: true
      }

      ref = Process.monitor(pid)
      send(pid, {:combat_event, event})
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

      # mob should be gone
      assert {:error, :not_found} = WorldServer.get_position(mob_id, ctx.world_server)

      # wait for respawn (100ms delay + buffer)
      assert_receive {:entity_joined, _new_entity}, 1000

      # a new mob with the same name should exist at the spawn position
      nodes =
        WorldServer.world_nodes(ctx.world_server)
        |> Enum.filter(fn {_id, node} -> node.name == "goblin" and node.type == :mob end)

      assert length(nodes) == 1
      [{_new_id, node}] = nodes
      assert node.pos == spawn_pos
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
        entity_server: ctx.entity_server,
        world_server: ctx.world_server,
        combat_server: ctx.combat_server
      }

      {:ok, pid} = Mob.start_link(mob)
      _ = :sys.get_state(pid)

      event = %CombatEvent{
        attacker_id: player_id,
        defender_id: mob_id,
        damage: 5,
        defender_hp: 95
      }

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
        abilities: [:melee_strike],
        entity_server: ctx.entity_server,
        world_server: ctx.world_server,
        combat_server: ctx.combat_server
      }

      {:ok, pid} = Mob.start_link(mob)
      _ = :sys.get_state(pid)

      event = %CombatEvent{
        attacker_id: player_id,
        defender_id: mob_id,
        damage: 5,
        defender_hp: 95
      }

      send(pid, {:combat_event, event})
      _ = :sys.get_state(pid)

      # walk player out of range by moving away from the mob
      # find a direction with at least 2 open tiles
      game_map = WorldServer.get_map(ctx.world_server)
      {:ok, player_pos} = WorldServer.get_position(player_id, ctx.world_server)

      direction =
        Enum.find([:south, :north, :east, :west], fn dir ->
          one = GameMap.interpolate(player_pos, dir)
          two = GameMap.interpolate(one, dir)
          !GameMap.collision?(game_map, one) and !GameMap.collision?(game_map, two)
        end)

      {:ok, _} = WorldServer.move(player_id, direction, ctx.world_server)
      Process.sleep(WorldServer.move_cooldown_ms() + 10)
      {:ok, _} = WorldServer.move(player_id, direction, ctx.world_server)

      # The mob's auto-fired :attack_target (from the combat event) already
      # set a melee_strike cooldown by hitting the player while still in range.
      # Wait for the mob's own retry to fire after that cooldown elapses, hit
      # the adjacency check, see the player is out of range, and clear aggro.
      state = wait_until(2500, fn -> aggro_cleared(pid) end)

      assert state, "expected aggro to clear within 2.5s, but it did not"
      assert state.aggro_target == nil
      assert state.attack_timer == nil
    end
  end

  defp aggro_cleared(pid) do
    state = :sys.get_state(pid)
    if state.aggro_target == nil, do: state
  end

  defp wait_until(timeout_ms, fun) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until(deadline, fun)
  end

  defp do_wait_until(deadline, fun) do
    case fun.() do
      nil ->
        if System.monotonic_time(:millisecond) > deadline do
          nil
        else
          Process.sleep(50)
          do_wait_until(deadline, fun)
        end

      result ->
        result
    end
  end

  describe "ability selection" do
    test "uses an ability from its abilities list (not hardcoded melee_strike)", ctx do
      mob_id = UUID.generate()
      player_id = UUID.generate()

      player = Gameserver.Entity.new(id: player_id, name: "hero", type: :user)
      {:ok, {px, py}} = WorldServer.join_entity(player, ctx.world_server)

      # only :upper_cut (base damage 3, distinct from :melee_strike's 1)
      mob = %Mob{
        id: mob_id,
        name: "goblin",
        spawn_pos: {px + 1, py},
        abilities: [:upper_cut],
        entity_server: ctx.entity_server,
        world_server: ctx.world_server,
        combat_server: ctx.combat_server
      }

      {:ok, pid} = Mob.start_link(mob)
      _ = :sys.get_state(pid)

      Phoenix.PubSub.subscribe(Gameserver.PubSub, CombatServer.combat_topic())

      send(
        pid,
        {:combat_event,
         %CombatEvent{attacker_id: player_id, defender_id: mob_id, damage: 1, defender_hp: 9}}
      )

      assert_receive {:combat_event, %CombatEvent{attacker_id: ^mob_id, defender_id: ^player_id}}

      {:ok, player_entity} = EntityServer.get_entity(player_id, ctx.entity_server)
      player_hp = Gameserver.Stat.effective(player_entity.stats.hp, player_entity.stats)
      # upper_cut deals 3 damage, melee_strike would do 1
      assert player_hp == 7
    end

    test "mob with empty abilities clears aggro on :attack_target", ctx do
      mob_id = UUID.generate()
      attacker_id = UUID.generate()

      mob = %Mob{
        id: mob_id,
        name: "goblin",
        spawn_pos: floor_pos(ctx.world_server),
        abilities: [],
        entity_server: ctx.entity_server,
        world_server: ctx.world_server,
        combat_server: ctx.combat_server
      }

      {:ok, pid} = Mob.start_link(mob)
      _ = :sys.get_state(pid)

      # set aggro via combat_event
      send(
        pid,
        {:combat_event,
         %CombatEvent{attacker_id: attacker_id, defender_id: mob_id, damage: 5, defender_hp: 5}}
      )

      _ = :sys.get_state(pid)

      send(pid, :attack_target)
      state = :sys.get_state(pid)

      assert state.aggro_target == nil
      assert state.attack_timer == nil
    end

    test "when all abilities on cooldown, mob keeps aggro and reschedules", ctx do
      mob_id = UUID.generate()
      player_id = UUID.generate()

      player = Gameserver.Entity.new(id: player_id, name: "hero", type: :user)
      {:ok, {px, py}} = WorldServer.join_entity(player, ctx.world_server)

      mob = %Mob{
        id: mob_id,
        name: "goblin",
        spawn_pos: {px + 1, py},
        abilities: [:melee_strike],
        entity_server: ctx.entity_server,
        world_server: ctx.world_server,
        combat_server: ctx.combat_server
      }

      {:ok, pid} = Mob.start_link(mob)
      _ = :sys.get_state(pid)

      # put :melee_strike on cooldown via entity cooldowns
      {:ok, _} =
        EntityServer.update_entity(
          mob_id,
          fn entity ->
            cds = Gameserver.Cooldowns.start(entity.cooldowns, :melee_strike, 60_000)
            %{entity | cooldowns: cds}
          end,
          ctx.entity_server
        )

      send(
        pid,
        {:combat_event,
         %CombatEvent{attacker_id: player_id, defender_id: mob_id, damage: 5, defender_hp: 95}}
      )

      _ = :sys.get_state(pid)

      send(pid, :attack_target)
      state = :sys.get_state(pid)

      assert state.aggro_target == player_id
      assert state.attack_timer != nil
    end

    test "retries with another ability when one is on cooldown", ctx do
      mob_id = UUID.generate()
      player_id = UUID.generate()

      player = Gameserver.Entity.new(id: player_id, name: "hero", type: :user)
      {:ok, {px, py}} = WorldServer.join_entity(player, ctx.world_server)

      mob = %Mob{
        id: mob_id,
        name: "goblin",
        spawn_pos: {px + 1, py},
        abilities: [:melee_strike, :upper_cut],
        entity_server: ctx.entity_server,
        world_server: ctx.world_server,
        combat_server: ctx.combat_server
      }

      {:ok, pid} = Mob.start_link(mob)
      _ = :sys.get_state(pid)

      # put only :melee_strike on cooldown; :upper_cut is still ready
      {:ok, _} =
        EntityServer.update_entity(
          mob_id,
          fn entity ->
            cds = Gameserver.Cooldowns.start(entity.cooldowns, :melee_strike, 60_000)
            %{entity | cooldowns: cds}
          end,
          ctx.entity_server
        )

      Phoenix.PubSub.subscribe(Gameserver.PubSub, CombatServer.combat_topic())

      send(
        pid,
        {:combat_event,
         %CombatEvent{attacker_id: player_id, defender_id: mob_id, damage: 5, defender_hp: 95}}
      )

      # mob should attack successfully, regardless of which ability random picked first.
      # if random picked :melee_strike first, retry kicks in; if :upper_cut, direct success.
      # either way the only ready ability is :upper_cut, so player loses 3 hp.
      assert_receive {:combat_event, %CombatEvent{attacker_id: ^mob_id, defender_id: ^player_id}}

      {:ok, player_entity} = EntityServer.get_entity(player_id, ctx.entity_server)
      player_hp = Gameserver.Stat.effective(player_entity.stats.hp, player_entity.stats)
      # upper_cut deals 3, melee_strike (on cooldown) would have been 1
      assert player_hp == 7
    end
  end

  describe "init/1" do
    test "creates entity and joins the world", ctx do
      id = UUID.generate()
      spawn_pos = floor_pos(ctx.world_server)

      mob = %Mob{
        id: id,
        name: "goblin",
        spawn_pos: spawn_pos,
        entity_server: ctx.entity_server,
        world_server: ctx.world_server
      }

      {:ok, pid} = Mob.start_link(mob)

      # join_world is deferred, wait for it
      _ = :sys.get_state(pid)

      {:ok, pos} = WorldServer.get_position(id, ctx.world_server)
      assert pos == spawn_pos
    end
  end
end
