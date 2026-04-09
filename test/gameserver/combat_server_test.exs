defmodule Gameserver.CombatServerTest do
  # set async to false due to pubsub messages mixing during tests
  use ExUnit.Case, async: false

  alias Gameserver.CombatServer
  alias Gameserver.Entity
  alias Gameserver.EntityServer
  alias Gameserver.Map, as: GameMap
  alias Gameserver.Stat
  alias Gameserver.User
  alias Gameserver.UUID
  alias Gameserver.WorldServer

  setup do
    entity_server = start_supervised!({EntityServer, name: nil})

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

  # returns a floor tile adjacent to the spawn point
  defp spawn_adjacent_pos(world_server) do
    map = WorldServer.get_map(world_server)
    {:ok, {sx, sy}} = GameMap.get_spawn_point(map)

    [{sx + 1, sy}, {sx - 1, sy}, {sx, sy + 1}, {sx, sy - 1}]
    |> Enum.find(fn pos -> !GameMap.collision?(map, pos) end)
  end

  # returns a floor tile NOT adjacent to the spawn point
  defp non_spawn_adjacent_pos(world_server) do
    map = WorldServer.get_map(world_server)
    [_, room | _] = map.rooms
    GameMap.random_tile_in_room(map, room)
  end

  describe "attack/3" do
    test "adjacent attack applies damage and returns cooldown", ctx do
      {:ok, user} = User.new("alice")
      {:ok, _pos} = WorldServer.join_user(user, ctx.world_server)
      mob = Entity.new(name: "goblin", type: :mob, pos: spawn_adjacent_pos(ctx.world_server))
      {:ok, _pos} = WorldServer.join_entity(mob, ctx.world_server)

      assert {:ok, {:attack, cooldown_ms}} =
               CombatServer.attack(user.id, mob.id, ctx.combat_server)

      assert is_integer(cooldown_ms) and cooldown_ms > 0

      {:ok, attacker} = EntityServer.get_entity(user.id, ctx.entity_server)
      {:ok, defender} = EntityServer.get_entity(mob.id, ctx.entity_server)
      defender_hp = Stat.effective(defender.stats.hp, defender.stats)
      # default hp is 10, attack_power is 1
      assert defender_hp == 10 - attacker.stats.attack_power
    end

    test "returns not_found when attacker does not exist", ctx do
      mob = Entity.new(name: "goblin", type: :mob, pos: spawn_adjacent_pos(ctx.world_server))
      {:ok, _pos} = WorldServer.join_entity(mob, ctx.world_server)
      fake_id = UUID.generate()

      assert {:error, :not_found} = CombatServer.attack(fake_id, mob.id, ctx.combat_server)
    end

    test "returns not_found when defender does not exist", ctx do
      {:ok, user} = User.new("alice")
      {:ok, _pos} = WorldServer.join_user(user, ctx.world_server)
      fake_id = UUID.generate()

      assert {:error, :not_found} = CombatServer.attack(user.id, fake_id, ctx.combat_server)
    end

    test "diagonal adjacency counts as in range", ctx do
      {:ok, user} = User.new("alice")
      {:ok, {sx, sy}} = WorldServer.join_user(user, ctx.world_server)
      map = WorldServer.get_map(ctx.world_server)
      # find a diagonal floor tile
      diag_pos =
        [{sx + 1, sy + 1}, {sx - 1, sy - 1}, {sx + 1, sy - 1}, {sx - 1, sy + 1}]
        |> Enum.find(fn pos -> !GameMap.collision?(map, pos) end)

      mob = Entity.new(name: "goblin", type: :mob, pos: diag_pos)
      {:ok, _pos} = WorldServer.join_entity(mob, ctx.world_server)

      assert {:ok, {:attack, _cooldown_ms}} =
               CombatServer.attack(user.id, mob.id, ctx.combat_server)
    end

    test "broadcasts entity_updated with reduced hp", ctx do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, EntityServer.entity_topic())
      {:ok, user} = User.new("alice")
      {:ok, _pos} = WorldServer.join_user(user, ctx.world_server)
      mob = Entity.new(name: "goblin", type: :mob, pos: spawn_adjacent_pos(ctx.world_server))
      {:ok, _pos} = WorldServer.join_entity(mob, ctx.world_server)

      # drain join broadcasts
      assert_receive {:entity_created, _}
      assert_receive {:entity_created, _}

      {:ok, _} = CombatServer.attack(user.id, mob.id, ctx.combat_server)

      assert_receive {:entity_updated, updated_mob}
      assert updated_mob.id == mob.id

      assert Stat.effective(updated_mob.stats.hp, updated_mob.stats) <
               Stat.effective(updated_mob.stats.max_hp, updated_mob.stats)
    end

    test "returns out_of_range when entities are not adjacent", ctx do
      {:ok, user} = User.new("alice")
      {:ok, _pos} = WorldServer.join_user(user, ctx.world_server)
      mob = Entity.new(name: "goblin", type: :mob, pos: non_spawn_adjacent_pos(ctx.world_server))
      {:ok, _pos} = WorldServer.join_entity(mob, ctx.world_server)

      assert {:error, :out_of_range} = CombatServer.attack(user.id, mob.id, ctx.combat_server)
    end

    test "returns target_dead when defender is already dead", ctx do
      {:ok, user} = User.new("alice")
      {:ok, _pos} = WorldServer.join_user(user, ctx.world_server)
      mob = Entity.new(name: "goblin", type: :mob, pos: spawn_adjacent_pos(ctx.world_server))
      mob = %{mob | stats: %{mob.stats | dead: true}}
      {:ok, _pos} = WorldServer.join_entity(mob, ctx.world_server)

      assert {:error, :target_dead} = CombatServer.attack(user.id, mob.id, ctx.combat_server)
    end

    test "does not broadcast combat event on failed attack", ctx do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, CombatServer.combat_topic())
      {:ok, user} = User.new("alice")
      {:ok, _pos} = WorldServer.join_user(user, ctx.world_server)
      fake_id = UUID.generate()

      {:error, :not_found} = CombatServer.attack(user.id, fake_id, ctx.combat_server)
      refute_receive {:combat_event, _}
    end

    test "broadcasts combat event on successful attack", ctx do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, CombatServer.combat_topic())
      {:ok, user} = User.new("alice")
      {:ok, _pos} = WorldServer.join_user(user, ctx.world_server)
      mob = Entity.new(name: "goblin", type: :mob, pos: spawn_adjacent_pos(ctx.world_server))
      {:ok, _pos} = WorldServer.join_entity(mob, ctx.world_server)

      {:ok, _} = CombatServer.attack(user.id, mob.id, ctx.combat_server)

      {:ok, attacker} = EntityServer.get_entity(user.id, ctx.entity_server)

      assert_receive {:combat_event, event}
      assert event.attacker_id == user.id
      assert event.defender_id == mob.id
      assert event.damage == attacker.stats.attack_power
      mob_hp = Stat.effective(mob.stats.hp, mob.stats)
      assert event.defender_hp == mob_hp - attacker.stats.attack_power
    end

    test "perform_attack modifies defender" do
      attacker = Entity.new(name: "alice", type: :user)
      defender = Entity.new(name: "goblin", type: :mob, pos: {1, 1})
      update_fn = CombatServer.perform_attack(attacker, defender)
      updated_defender = update_fn.(defender)

      assert Stat.effective(updated_defender.stats.hp, updated_defender.stats) <
               Stat.effective(updated_defender.stats.max_hp, updated_defender.stats)
    end

    test "perform_attack clamps defender hp at zero" do
      attacker = Entity.new(name: "alice", type: :user)
      attacker = %{attacker | stats: %{attacker.stats | attack_power: 50}}

      defender = Entity.new(name: "goblin", type: :mob, pos: {1, 1})
      update_fn = CombatServer.perform_attack(attacker, defender)
      updated_defender = update_fn.(defender)
      assert Stat.effective(updated_defender.stats.hp, updated_defender.stats) == 0
    end

    test "perform_attack doesnt allow zombies" do
      attacker = Entity.new(name: "alice", type: :user)
      defender = Entity.new(name: "goblin", type: :mob, pos: {1, 1})
      defender = %{defender | stats: %{defender.stats | dead: true}}
      update_fn = CombatServer.perform_attack(attacker, defender)
      updated_defender = update_fn.(defender)
      assert updated_defender.stats.dead
    end

    test "perform_attack sets dead" do
      attacker = Entity.new(name: "alice", type: :user)
      attacker = %{attacker | stats: %{attacker.stats | attack_power: 50}}
      defender = Entity.new(name: "goblin", type: :mob, pos: {1, 1})
      update_fn = CombatServer.perform_attack(attacker, defender)
      updated_defender = update_fn.(defender)
      assert updated_defender.stats.dead
    end
  end
end
