defmodule Gameserver.WorldServerTest do
  use ExUnit.Case, async: true

  alias Gameserver.Entity
  alias Gameserver.User
  alias Gameserver.WorldServer

  setup do
    pid = start_supervised!({WorldServer, name: nil})
    {:ok, server: pid}
  end

  describe "genserver lifecycle" do
    test "is started and registered by application" do
      assert Process.whereis(WorldServer) != nil
    end
  end

  describe "join_user/2" do
    test "adds user to the world and returns spawn position", %{server: server} do
      {:ok, user} = User.new("alice")

      assert {:ok, {x, y}} = WorldServer.join_user(user, server)
      assert is_integer(x) and is_integer(y)
    end

    test "returns error when user already joined", %{server: server} do
      {:ok, user} = User.new("alice")

      {:ok, _position} = WorldServer.join_user(user, server)
      assert {:error, :already_joined} = WorldServer.join_user(user, server)
    end

    test "returns error when username already taken", %{server: server} do
      {:ok, alice1} = User.new("alice")
      {:ok, alice2} = User.new("alice")

      {:ok, _position} = WorldServer.join_user(alice1, server)
      assert {:error, :username_not_available} = WorldServer.join_user(alice2, server)
    end

    test "allows same username after original user leaves", %{server: server} do
      {:ok, alice1} = User.new("alice")
      {:ok, alice2} = User.new("alice")

      {:ok, _position} = WorldServer.join_user(alice1, server)
      :ok = WorldServer.leave(alice1.id, server)
      assert {:ok, _position} = WorldServer.join_user(alice2, server)
    end

    test "allows rejoin after leaving", %{server: server} do
      {:ok, user} = User.new("alice")

      {:ok, _position} = WorldServer.join_user(user, server)
      :ok = WorldServer.leave(user.id, server)
      assert {:ok, _position} = WorldServer.join_user(user, server)
    end
  end

  describe "leave/2" do
    test "removes user from the world", %{server: server} do
      {:ok, user} = User.new("alice")
      {:ok, _position} = WorldServer.join_user(user, server)

      assert :ok = WorldServer.leave(user.id, server)
    end

    test "returns error when user not in world", %{server: server} do
      fake_id = Ecto.UUID.generate()

      assert {:error, :not_found} = WorldServer.leave(fake_id, server)
    end
  end

  describe "who/1" do
    test "returns empty list when no users", %{server: server} do
      assert [] = WorldServer.who(server)
    end

    test "returns all users when called with no filter", %{server: server} do
      {:ok, alice} = User.new("alice")
      {:ok, bob} = User.new("bob")
      {:ok, _position} = WorldServer.join_user(alice, server)
      {:ok, _position} = WorldServer.join_user(bob, server)

      result = WorldServer.who(server)

      assert length(result) == 2
      assert {alice.id, "alice"} in result
      assert {bob.id, "bob"} in result
    end

    test "returns single user when given user_id", %{server: server} do
      {:ok, alice} = User.new("alice")
      {:ok, bob} = User.new("bob")
      {:ok, _position} = WorldServer.join_user(alice, server)
      {:ok, _position} = WorldServer.join_user(bob, server)

      assert [{alice.id, "alice"}] == WorldServer.who(alice.id, server)
    end

    test "returns empty list when user_id not found", %{server: server} do
      assert [] = WorldServer.who("nonexistent-id", server)
    end

    test "returns matching users when given list of user_ids", %{server: server} do
      {:ok, alice} = User.new("alice")
      {:ok, bob} = User.new("bob")
      {:ok, charlie} = User.new("charlie")
      {:ok, _position} = WorldServer.join_user(alice, server)
      {:ok, _position} = WorldServer.join_user(bob, server)
      {:ok, _position} = WorldServer.join_user(charlie, server)

      result = WorldServer.who([alice.id, charlie.id], server)

      assert length(result) == 2
      assert {alice.id, "alice"} in result
      assert {charlie.id, "charlie"} in result
      refute {bob.id, "bob"} in result
    end

    test "ignores unknown ids in list", %{server: server} do
      {:ok, alice} = User.new("alice")
      {:ok, _position} = WorldServer.join_user(alice, server)

      result = WorldServer.who([alice.id, "unknown-id"], server)

      assert [{alice.id, "alice"}] == result
    end
  end

  describe "get_position/2" do
    test "returns position for joined player", %{server: server} do
      {:ok, alice} = User.new("alice")
      {:ok, spawn_position} = WorldServer.join_user(alice, server)

      assert {:ok, ^spawn_position} = WorldServer.get_position(alice.id, server)
    end

    test "returns error for unknown player", %{server: server} do
      fake_id = Ecto.UUID.generate()

      assert {:error, :not_found} = WorldServer.get_position(fake_id, server)
    end
  end

  describe "players/1" do
    test "returns empty list when no players", %{server: server} do
      assert [] = WorldServer.players(server)
    end

    test "returns all players with positions", %{server: server} do
      {:ok, alice} = User.new("alice")
      {:ok, bob} = User.new("bob")
      {:ok, alice_pos} = WorldServer.join_user(alice, server)
      {:ok, bob_pos} = WorldServer.join_user(bob, server)

      result = WorldServer.players(server)

      assert length(result) == 2
      assert {alice, alice_pos} in result
      assert {bob, bob_pos} in result
    end
  end

  describe "get_map/1" do
    test "returns the map", %{server: server} do
      assert %Gameserver.Map{} = WorldServer.get_map(server)
    end
  end

  describe "move/3" do
    test "moves player and returns new position", %{server: server} do
      {:ok, user} = User.new("alice")
      {:ok, _spawn} = WorldServer.join_user(user, server)

      # spawn is on upstairs tile at {1,1} in sample_dungeon, move east to {2,1} which is floor
      assert {:ok, {2, 1}} = WorldServer.move(user.id, :east, server)
      assert {:ok, {2, 1}} = WorldServer.get_position(user.id, server)
    end

    test "returns error when moving into a wall", %{server: server} do
      {:ok, user} = User.new("alice")
      {:ok, _spawn} = WorldServer.join_user(user, server)

      # spawn is {1,1}, moving north hits wall at {1,0}
      assert {:error, :collision} = WorldServer.move(user.id, :north, server)
    end

    test "returns error for unknown player", %{server: server} do
      fake_id = Ecto.UUID.generate()
      assert {:error, :not_found} = WorldServer.move(fake_id, :east, server)
    end

    test "returns error when on cooldown", %{server: server} do
      {:ok, user} = User.new("alice")
      {:ok, _spawn} = WorldServer.join_user(user, server)

      {:ok, _pos} = WorldServer.move(user.id, :east, server)
      assert {:error, :cooldown} = WorldServer.move(user.id, :east, server)
    end

    test "allows movement after cooldown expires", %{server: server} do
      {:ok, user} = User.new("alice")
      {:ok, _spawn} = WorldServer.join_user(user, server)

      {:ok, _pos} = WorldServer.move(user.id, :east, server)
      Process.sleep(WorldServer.move_cooldown_ms() + 1)
      assert {:ok, _pos} = WorldServer.move(user.id, :east, server)
    end

    test "position unchanged after collision", %{server: server} do
      {:ok, user} = User.new("alice")
      {:ok, spawn} = WorldServer.join_user(user, server)

      WorldServer.move(user.id, :north, server)
      assert {:ok, ^spawn} = WorldServer.get_position(user.id, server)
    end
  end

  describe "pubsub broadcasts" do
    test "broadcasts entity_joined on successful join", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())
      {:ok, alice} = User.new("alice")

      {:ok, pos} = WorldServer.join_user(alice, server)

      assert_receive {:entity_joined, entity}
      assert entity.id == alice.id
      assert entity.name == "alice"
      assert entity.pos == pos
    end

    test "does not broadcast on failed join", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())
      {:ok, alice} = User.new("alice")
      {:ok, _position} = WorldServer.join_user(alice, server)

      assert_receive {:entity_joined, _}

      {:error, :already_joined} = WorldServer.join_user(alice, server)

      refute_receive {:entity_joined, _}
    end

    test "does not broadcast on username collision", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())
      {:ok, alice1} = User.new("alice")
      {:ok, alice2} = User.new("alice")

      {:ok, _position} = WorldServer.join_user(alice1, server)
      assert_receive {:entity_joined, _}

      {:error, :username_not_available} = WorldServer.join_user(alice2, server)
      refute_receive {:entity_joined, _}
    end

    test "broadcasts entity_left on successful leave", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())
      {:ok, alice} = User.new("alice")
      {:ok, _position} = WorldServer.join_user(alice, server)
      assert_receive {:entity_joined, _}

      :ok = WorldServer.leave(alice.id, server)

      assert_receive {:entity_left, id}
      assert id == alice.id
    end

    test "does not broadcast on failed leave", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())
      fake_id = Ecto.UUID.generate()

      {:error, :not_found} = WorldServer.leave(fake_id, server)

      refute_receive {:entity_left, _}
    end

    test "broadcasts entity_moved on successful move", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.movement_topic())
      {:ok, alice} = User.new("alice")
      {:ok, _position} = WorldServer.join_user(alice, server)

      {:ok, new_pos} = WorldServer.move(alice.id, :east, server)

      assert_receive {:entity_moved, id, ^new_pos}
      assert id == alice.id
    end

    test "does not broadcast on collision", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.movement_topic())
      {:ok, alice} = User.new("alice")
      {:ok, _position} = WorldServer.join_user(alice, server)

      {:error, :collision} = WorldServer.move(alice.id, :north, server)

      refute_receive {:entity_moved, _, _}
    end

    test "does not broadcast on cooldown", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.movement_topic())
      {:ok, alice} = User.new("alice")
      {:ok, _position} = WorldServer.join_user(alice, server)

      {:ok, _pos} = WorldServer.move(alice.id, :east, server)
      assert_receive {:entity_moved, _, _}

      {:error, :cooldown} = WorldServer.move(alice.id, :east, server)
      refute_receive {:entity_moved, _, _}
    end
  end

  describe "join_entity/2" do
    test "adds a mob entity to the world", %{server: server} do
      mob = Entity.new(name: "goblin", type: :mob)

      assert {:ok, {x, y}} = WorldServer.join_entity(mob, server)
      assert is_integer(x) and is_integer(y)
    end

    test "mob skips username uniqueness check", %{server: server} do
      {:ok, _user} = User.new("goblin")
      mob1 = Entity.new(name: "goblin", type: :mob)
      mob2 = Entity.new(name: "goblin", type: :mob)

      {:ok, _pos} = WorldServer.join_entity(mob1, server)
      assert {:ok, _pos} = WorldServer.join_entity(mob2, server)
    end

    test "returns error when mob id already joined", %{server: server} do
      mob = Entity.new(name: "goblin", type: :mob)

      {:ok, _pos} = WorldServer.join_entity(mob, server)
      assert {:error, :already_joined} = WorldServer.join_entity(mob, server)
    end

    test "mob does not appear in who/1", %{server: server} do
      mob = Entity.new(name: "goblin", type: :mob)
      {:ok, _pos} = WorldServer.join_entity(mob, server)

      assert [] = WorldServer.who(server)
    end

    test "mob does not appear in players/1", %{server: server} do
      mob = Entity.new(name: "goblin", type: :mob)
      {:ok, _pos} = WorldServer.join_entity(mob, server)

      assert [] = WorldServer.players(server)
    end

    test "enforces username uniqueness for user entities", %{server: server} do
      user1 = Entity.new(name: "alice", type: :user)
      user2 = Entity.new(name: "alice", type: :user)

      {:ok, _pos} = WorldServer.join_entity(user1, server)
      assert {:error, :username_not_available} = WorldServer.join_entity(user2, server)
    end

    test "mob broadcasts entity_joined", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())
      mob = Entity.new(name: "goblin", type: :mob)

      {:ok, pos} = WorldServer.join_entity(mob, server)

      assert_receive {:entity_joined, entity}
      assert entity.id == mob.id
      assert entity.name == "goblin"
      assert entity.pos == pos
    end

    test "mob position is retrievable", %{server: server} do
      mob = Entity.new(name: "goblin", type: :mob)
      {:ok, pos} = WorldServer.join_entity(mob, server)

      assert {:ok, ^pos} = WorldServer.get_position(mob.id, server)
    end

    test "mob broadcasts entity_left on leave", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())
      mob = Entity.new(name: "goblin", type: :mob)
      {:ok, _pos} = WorldServer.join_entity(mob, server)
      assert_receive {:entity_joined, _}

      :ok = WorldServer.leave(mob.id, server)

      assert_receive {:entity_left, id}
      assert id == mob.id
    end

    test "mob can move", %{server: server} do
      mob = Entity.new(name: "goblin", type: :mob)
      {:ok, _spawn} = WorldServer.join_entity(mob, server)

      # spawn is on upstairs tile at {1,1} in sample_dungeon, move east to {2,1}
      assert {:ok, {2, 1}} = WorldServer.move(mob.id, :east, server)
    end
  end

  describe "join_entity/2 with pre-set position" do
    test "mob with pre-set pos spawns at that pos", %{server: server} do
      mob = Entity.new(name: "goblin", type: :mob, pos: {3, 2})

      assert {:ok, {3, 2}} = WorldServer.join_entity(mob, server)
      assert {:ok, {3, 2}} = WorldServer.get_position(mob.id, server)
    end

    test "mob with pos on a wall is rejected", %{server: server} do
      mob = Entity.new(name: "goblin", type: :mob, pos: {0, 0})

      assert {:error, :collision} = WorldServer.join_entity(mob, server)
    end

    test "mob rejected when tile is occupied by another entity", %{server: server} do
      mob1 = Entity.new(name: "goblin", type: :mob, pos: {3, 2})
      mob2 = Entity.new(name: "spider", type: :mob, pos: {3, 2})

      {:ok, _pos} = WorldServer.join_entity(mob1, server)
      assert {:error, :collision} = WorldServer.join_entity(mob2, server)
    end

    test "mob without pos gets spawn point", %{server: server} do
      mob = Entity.new(name: "goblin", type: :mob)

      assert {:ok, {1, 1}} = WorldServer.join_entity(mob, server)
    end

    test "mob with out-of-bounds pos is rejected", %{server: server} do
      mob = Entity.new(name: "goblin", type: :mob, pos: {999, 999})

      assert {:error, :collision} = WorldServer.join_entity(mob, server)
    end

    test "mob rejected when tile is occupied by a user", %{server: server} do
      {:ok, user} = User.new("alice")
      {:ok, spawn} = WorldServer.join_user(user, server)
      mob = Entity.new(name: "goblin", type: :mob, pos: spawn)

      assert {:error, :collision} = WorldServer.join_entity(mob, server)
    end

    test "user with pre-set pos still gets spawn point", %{server: server} do
      user_entity = Entity.new(name: "alice", type: :user, pos: {5, 10})

      assert {:ok, {1, 1}} = WorldServer.join_entity(user_entity, server)
    end
  end

  describe "entity-entity collision on movement" do
    test "player cannot walk onto a mob's tile", %{server: server} do
      {:ok, user} = User.new("alice")
      {:ok, _spawn} = WorldServer.join_user(user, server)
      # user at {1,1}, place mob at {2,1} (east of spawn)
      mob = Entity.new(name: "goblin", type: :mob, pos: {2, 1})
      {:ok, _pos} = WorldServer.join_entity(mob, server)

      assert {:error, :collision} = WorldServer.move(user.id, :east, server)
    end

    test "mob cannot walk onto a player's tile", %{server: server} do
      {:ok, user} = User.new("alice")
      {:ok, _spawn} = WorldServer.join_user(user, server)
      # mob at {2,1}, user at {1,1} — mob moves west into player
      mob = Entity.new(name: "goblin", type: :mob, pos: {2, 1})
      {:ok, _pos} = WorldServer.join_entity(mob, server)
      Process.sleep(WorldServer.move_cooldown_ms() + 1)

      assert {:error, :collision} = WorldServer.move(mob.id, :west, server)
    end

    test "mob cannot walk onto another mob's tile", %{server: server} do
      mob1 = Entity.new(name: "goblin", type: :mob, pos: {2, 1})
      mob2 = Entity.new(name: "spider", type: :mob, pos: {3, 1})
      {:ok, _pos} = WorldServer.join_entity(mob1, server)
      {:ok, _pos} = WorldServer.join_entity(mob2, server)
      Process.sleep(WorldServer.move_cooldown_ms() + 1)

      assert {:error, :collision} = WorldServer.move(mob1.id, :east, server)
    end

    test "players can stack on each other", %{server: server} do
      {:ok, alice} = User.new("alice")
      {:ok, bob} = User.new("bob")
      {:ok, _spawn} = WorldServer.join_user(alice, server)
      {:ok, _spawn} = WorldServer.join_user(bob, server)

      # both at {1,1}, alice moves east
      {:ok, {2, 1}} = WorldServer.move(alice.id, :east, server)
      Process.sleep(WorldServer.move_cooldown_ms() + 1)
      # bob follows alice — should succeed
      assert {:ok, {2, 1}} = WorldServer.move(bob.id, :east, server)
    end

    test "movement still works when destination is empty", %{server: server} do
      {:ok, user} = User.new("alice")
      {:ok, _spawn} = WorldServer.join_user(user, server)

      assert {:ok, {2, 1}} = WorldServer.move(user.id, :east, server)
    end

    test "entity collision does not broadcast movement", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.movement_topic())
      {:ok, user} = User.new("alice")
      {:ok, _spawn} = WorldServer.join_user(user, server)
      mob = Entity.new(name: "goblin", type: :mob, pos: {2, 1})
      {:ok, _pos} = WorldServer.join_entity(mob, server)

      {:error, :collision} = WorldServer.move(user.id, :east, server)

      refute_receive {:entity_moved, _, _}
    end
  end
end
