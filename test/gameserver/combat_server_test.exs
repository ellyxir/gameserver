defmodule Gameserver.CombatServerTest do
  use ExUnit.Case, async: true

  alias Gameserver.CombatServer
  alias Gameserver.Entity
  alias Gameserver.EntityServer
  alias Gameserver.User
  alias Gameserver.UUID
  alias Gameserver.WorldServer

  setup do
    entity_server = start_supervised!({EntityServer, name: nil})

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

  describe "attack/3" do
    test "adjacent attack applies damage and returns cooldown", ctx do
      {:ok, user} = User.new("alice")
      {:ok, _pos} = WorldServer.join_user(user, ctx.world_server)
      mob = Entity.new(name: "goblin", type: :mob, pos: {2, 1})
      {:ok, _pos} = WorldServer.join_entity(mob, ctx.world_server)

      assert {:ok, {:attack, cooldown_ms}} =
               CombatServer.attack(user.id, mob.id, ctx.combat_server)

      assert is_integer(cooldown_ms) and cooldown_ms > 0

      {:ok, attacker} = EntityServer.get_entity(user.id, ctx.entity_server)
      {:ok, defender} = EntityServer.get_entity(mob.id, ctx.entity_server)
      assert defender.stats.hp == defender.stats.max_hp - attacker.stats.attack_power
    end

    test "returns not_found when attacker does not exist", ctx do
      mob = Entity.new(name: "goblin", type: :mob, pos: {2, 1})
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
      {:ok, _pos} = WorldServer.join_user(user, ctx.world_server)
      # user at {1,1}, mob at {2,2} — diagonally adjacent
      mob = Entity.new(name: "goblin", type: :mob, pos: {2, 2})
      {:ok, _pos} = WorldServer.join_entity(mob, ctx.world_server)

      assert {:ok, {:attack, _cooldown_ms}} =
               CombatServer.attack(user.id, mob.id, ctx.combat_server)
    end

    test "broadcasts entity_updated with reduced hp", ctx do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, EntityServer.entity_topic())
      {:ok, user} = User.new("alice")
      {:ok, _pos} = WorldServer.join_user(user, ctx.world_server)
      mob = Entity.new(name: "goblin", type: :mob, pos: {2, 1})
      {:ok, _pos} = WorldServer.join_entity(mob, ctx.world_server)

      # drain join broadcasts
      assert_receive {:entity_created, _}
      assert_receive {:entity_created, _}

      {:ok, _} = CombatServer.attack(user.id, mob.id, ctx.combat_server)

      assert_receive {:entity_updated, updated_mob}
      assert updated_mob.id == mob.id
      assert updated_mob.stats.hp < updated_mob.stats.max_hp
    end

    test "returns out_of_range when entities are not adjacent", ctx do
      {:ok, user} = User.new("alice")
      {:ok, _pos} = WorldServer.join_user(user, ctx.world_server)
      # user at {1,1}, mob at {3,2} — not adjacent
      mob = Entity.new(name: "goblin", type: :mob, pos: {3, 2})
      {:ok, _pos} = WorldServer.join_entity(mob, ctx.world_server)

      assert {:error, :out_of_range} = CombatServer.attack(user.id, mob.id, ctx.combat_server)
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
      mob = Entity.new(name: "goblin", type: :mob, pos: {2, 1})
      {:ok, _pos} = WorldServer.join_entity(mob, ctx.world_server)

      {:ok, _} = CombatServer.attack(user.id, mob.id, ctx.combat_server)

      {:ok, attacker} = EntityServer.get_entity(user.id, ctx.entity_server)

      assert_receive {:combat_event, event}
      assert event.attacker_id == user.id
      assert event.defender_id == mob.id
      assert event.damage == attacker.stats.attack_power
      assert event.defender_hp == mob.stats.hp - attacker.stats.attack_power
    end

    test "perform_attack modifies defender" do
      attacker = Entity.new(name: "alice", type: :user)
      defender = Entity.new(name: "goblin", type: :mob, pos: {2, 1})
      {:ok, update_fn} = CombatServer.perform_attack(attacker, defender)
      updated_defender = update_fn.(defender)
      assert updated_defender.stats.hp < updated_defender.stats.max_hp
    end

    test "perform_attack clamps defender hp at zero" do
      attacker = Entity.new(name: "alice", type: :user)
      defender = Entity.new(name: "goblin", type: :mob, pos: {2, 1})
      defender = %{defender | stats: %{defender.stats | hp: 1, attack_power: 5}}
      {:ok, update_fn} = CombatServer.perform_attack(attacker, defender)
      updated_defender = update_fn.(defender)
      assert updated_defender.stats.hp == 0
    end
  end
end
