defmodule Gameserver.WorldServerTest do
  # async: false because pubsub broadcast tests share the global "world:presence" topic
  use ExUnit.Case, async: false

  alias Gameserver.Entity
  alias Gameserver.EntityServer
  alias Gameserver.User
  alias Gameserver.UUID
  alias Gameserver.WorldServer
  alias Gameserver.WorldServer.StateETS

  alias Gameserver.Map, as: GameMap

  setup do
    entity_server = start_supervised!({EntityServer, name: nil})

    pid =
      start_supervised!(
        {WorldServer, name: nil, entity_server: entity_server, map: GameMap.sample_dungeon()},
        id: :world_server
      )

    {:ok, server: pid, entity_server: entity_server}
  end

  defp start_world_trio(id_suffix) do
    entity_server = start_supervised!({EntityServer, name: nil}, id: :"es_#{id_suffix}")
    state_ets_name = :"state_ets_#{System.unique_integer([:positive])}"
    state_ets = start_supervised!({StateETS, name: state_ets_name}, id: :"ets_#{id_suffix}")

    world =
      start_supervised!(
        {WorldServer, name: nil, entity_server: entity_server, state_ets: state_ets},
        id: :"ws_#{id_suffix}"
      )

    %{world: world, entity_server: entity_server, state_ets: state_ets}
  end

  defp restart_world(%{entity_server: entity_server, state_ets: state_ets}, old_id, new_id) do
    stop_supervised!(old_id)

    world =
      start_supervised!(
        {WorldServer, name: nil, entity_server: entity_server, state_ets: state_ets},
        id: new_id
      )

    %{world: world, entity_server: entity_server, state_ets: state_ets}
  end

  defp await_mob_joins(count) do
    for _ <- 1..count do
      assert_receive {:entity_joined, %Entity{type: :mob} = entity}, 1000
      entity
    end
  end

  describe "genserver lifecycle" do
    test "is started and registered by application" do
      assert Process.whereis(WorldServer) != nil
    end

    test "generates map with configured dimensions" do
      Application.put_env(:gameserver, :map_width, 15)
      Application.put_env(:gameserver, :map_height, 20)

      on_exit(fn ->
        Application.delete_env(:gameserver, :map_width)
        Application.delete_env(:gameserver, :map_height)
      end)

      %{world: world} = start_world_trio(:map_size_test)
      map = WorldServer.get_map(world)

      assert map.width == 15
      assert map.height == 20
    end

    test "stores map seed in state_ets on init" do
      %{world: world, state_ets: state_ets} = start_world_trio(:seed_test)

      seed = StateETS.get_seed(state_ets)
      assert is_integer(seed)
      assert seed == WorldServer.get_map(world).seed
    end

    test "restart produces the same map from persisted seed" do
      %{world: world} = trio = start_world_trio(:restart_test)
      first_map = WorldServer.get_map(world)

      %{world: world2} = restart_world(trio, :ws_restart_test, :ws_restart_test_2)
      second_map = WorldServer.get_map(world2)

      assert first_map.tiles == second_map.tiles
      assert first_map.seed == second_map.seed
    end

    test "rebuilds user entities from entityserver on restart" do
      %{world: world} = trio = start_world_trio(:rebuild_test)

      {:ok, user} = User.new("alice")
      {:ok, pos} = WorldServer.join_user(user, world)

      %{world: world2} = restart_world(trio, :ws_rebuild_test, :ws_rebuild_test_2)

      assert {:ok, ^pos} = WorldServer.get_position(user.id, world2)
      assert [{_, "alice"}] = WorldServer.who(world2)
    end

    test "does not rebuild mob entities on restart" do
      %{world: world, entity_server: entity_server} = trio = start_world_trio(:mob_rebuild_test)

      mob = Entity.new(name: "goblin", type: :mob)
      {:ok, _pos} = WorldServer.join_entity(mob, world)

      %{world: world2} = restart_world(trio, :ws_mob_rebuild_test, :ws_mob_rebuild_test_2)

      assert {:error, :not_found} = WorldServer.get_position(mob.id, world2)
      assert {:error, :not_found} = EntityServer.get_entity(mob.id, entity_server)
    end

    test "spawned mobs have abilities", %{server: server, entity_server: entity_server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())

      _mob_server =
        start_supervised!(
          {Gameserver.MobServer, world_server: server, name: nil},
          id: :ms_ability_test
        )

      [mob | _] = await_mob_joins(3)
      {:ok, entity} = EntityServer.get_entity(mob.id, entity_server)
      refute entity.abilities == []
    end

    test "mobs respawn after worldserver restart" do
      %{world: world} = trio = start_world_trio(:mob_respawn_test)

      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())

      _mob_server =
        start_supervised!(
          {Gameserver.MobServer, world_server: world, name: nil},
          id: :ms_mob_respawn_test
        )

      old_mobs = await_mob_joins(3)
      old_mob_ids = MapSet.new(old_mobs, & &1.id)

      stop_supervised!(:ms_mob_respawn_test)

      %{world: world2} = restart_world(trio, :ws_mob_respawn_test, :ws_mob_respawn_test_2)

      _mob_server2 =
        start_supervised!(
          {Gameserver.MobServer, world_server: world2, name: nil},
          id: :ms_mob_respawn_test_2
        )

      new_mobs = await_mob_joins(3)
      new_mob_ids = MapSet.new(new_mobs, & &1.id)

      assert MapSet.size(new_mob_ids) == 3
      assert MapSet.disjoint?(old_mob_ids, new_mob_ids)
    end
  end

  describe "join_user/2" do
    test "adds user to the world and returns spawn position", %{server: server} do
      {:ok, user} = User.new("alice")

      assert {:ok, {x, y}} = WorldServer.join_user(user, server)
      assert is_integer(x) and is_integer(y)
    end

    test "player entity gets abilities", %{server: server, entity_server: entity_server} do
      {:ok, user} = User.new("alice")
      {:ok, _pos} = WorldServer.join_user(user, server)

      {:ok, entity} = EntityServer.get_entity(user.id, entity_server)
      refute entity.abilities == []
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
      fake_id = UUID.generate()

      assert {:error, :not_found} = WorldServer.leave(fake_id, server)
    end

    test "removes entity from entity server", %{server: server, entity_server: entity_server} do
      {:ok, user} = User.new("alice")
      {:ok, _position} = WorldServer.join_user(user, server)

      :ok = WorldServer.leave(user.id, server)

      assert {:error, :not_found} = EntityServer.get_entity(user.id, entity_server)
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
      fake_id = UUID.generate()

      assert {:error, :not_found} = WorldServer.get_position(fake_id, server)
    end
  end

  describe "world_nodes/1" do
    test "returns empty map when no entities", %{server: server} do
      assert %{} = WorldServer.world_nodes(server)
    end

    test "returns all entities keyed by id", %{server: server} do
      {:ok, alice} = User.new("alice")
      {:ok, alice_pos} = WorldServer.join_user(alice, server)
      mob = Entity.new(name: "goblin", type: :mob, pos: {3, 2})
      {:ok, mob_pos} = WorldServer.join_entity(mob, server)

      nodes = WorldServer.world_nodes(server)

      assert map_size(nodes) == 2
      assert %{pos: ^alice_pos, type: :user, name: "alice"} = nodes[alice.id]
      assert %{pos: ^mob_pos, type: :mob, name: "goblin"} = nodes[mob.id]
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

      # spawn is on the upstairs tile, move east
      {:ok, {sx, sy}} = WorldServer.get_position(user.id, server)
      assert {:ok, pos} = WorldServer.move(user.id, :east, server)
      assert pos == {sx + 1, sy}
    end

    test "returns error when moving into a wall", %{server: server} do
      game_map = WorldServer.get_map(server)
      # place a mob on a floor tile next to a wall
      wall_neighbor =
        Enum.find_value(game_map.tiles, fn
          {{x, y}, :floor} ->
            cond do
              GameMap.collision?(game_map, {x, y - 1}) -> {{x, y}, :north}
              GameMap.collision?(game_map, {x, y + 1}) -> {{x, y}, :south}
              GameMap.collision?(game_map, {x - 1, y}) -> {{x, y}, :west}
              GameMap.collision?(game_map, {x + 1, y}) -> {{x, y}, :east}
              true -> nil
            end

          _ ->
            nil
        end)

      {pos, direction} = wall_neighbor
      mob = Entity.new(name: "walltest", type: :mob, pos: pos)
      {:ok, _} = WorldServer.join_entity(mob, server)

      assert {:error, {:collision, _, :wall}} = WorldServer.move(mob.id, direction, server)
    end

    test "returns error for unknown player", %{server: server} do
      fake_id = UUID.generate()
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

      # move east, wait for cooldown, move back west
      {:ok, _pos} = WorldServer.move(user.id, :east, server)
      Process.sleep(WorldServer.move_cooldown_ms() + 1)
      assert {:ok, _pos} = WorldServer.move(user.id, :west, server)
    end

    test "position unchanged after collision", %{server: server} do
      game_map = WorldServer.get_map(server)

      # find a floor tile next to a wall
      {pos, direction} =
        Enum.find_value(game_map.tiles, fn
          {{x, y}, :floor} ->
            cond do
              GameMap.collision?(game_map, {x, y - 1}) -> {{x, y}, :north}
              GameMap.collision?(game_map, {x, y + 1}) -> {{x, y}, :south}
              true -> nil
            end

          _ ->
            nil
        end)

      mob = Entity.new(name: "wallmob", type: :mob, pos: pos)
      {:ok, _} = WorldServer.join_entity(mob, server)

      WorldServer.move(mob.id, direction, server)
      assert {:ok, ^pos} = WorldServer.get_position(mob.id, server)
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
      fake_id = UUID.generate()

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
      game_map = WorldServer.get_map(server)

      # find a floor tile next to a wall
      {pos, direction} =
        Enum.find_value(game_map.tiles, fn
          {{x, y}, :floor} ->
            cond do
              GameMap.collision?(game_map, {x, y - 1}) -> {{x, y}, :north}
              GameMap.collision?(game_map, {x, y + 1}) -> {{x, y}, :south}
              true -> nil
            end

          _ ->
            nil
        end)

      mob = Entity.new(name: "wallmob", type: :mob, pos: pos)
      {:ok, _} = WorldServer.join_entity(mob, server)

      {:error, {:collision, _, _}} = WorldServer.move(mob.id, direction, server)

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
      {:ok, {sx, sy}} = WorldServer.join_entity(mob, server)

      # spawn is on the upstairs tile, move east
      assert {:ok, pos} = WorldServer.move(mob.id, :east, server)
      assert pos == {sx + 1, sy}
    end
  end

  describe "join_entity/2 with pre-set position" do
    test "mob with pre-set pos spawns at that pos", %{server: server} do
      game_map = WorldServer.get_map(server)
      [room | _] = game_map.rooms
      pos = GameMap.random_tile_in_room(game_map, room)
      mob = Entity.new(name: "goblin", type: :mob, pos: pos)

      assert {:ok, ^pos} = WorldServer.join_entity(mob, server)
      assert {:ok, ^pos} = WorldServer.get_position(mob.id, server)
    end

    test "mob with pos on a wall is rejected", %{server: server} do
      mob = Entity.new(name: "goblin", type: :mob, pos: {0, 0})

      assert {:error, :collision} = WorldServer.join_entity(mob, server)
    end

    test "mob rejected when tile is occupied by another entity", %{server: server} do
      game_map = WorldServer.get_map(server)
      [room | _] = game_map.rooms
      pos = GameMap.random_tile_in_room(game_map, room)
      mob1 = Entity.new(name: "goblin", type: :mob, pos: pos)
      mob2 = Entity.new(name: "spider", type: :mob, pos: pos)

      {:ok, _pos} = WorldServer.join_entity(mob1, server)
      assert {:error, :collision} = WorldServer.join_entity(mob2, server)
    end

    test "mob without pos gets spawn point", %{server: server} do
      game_map = WorldServer.get_map(server)
      {:ok, spawn_point} = GameMap.get_spawn_point(game_map)
      mob = Entity.new(name: "goblin", type: :mob)

      assert {:ok, ^spawn_point} = WorldServer.join_entity(mob, server)
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
      game_map = WorldServer.get_map(server)
      {:ok, spawn_point} = GameMap.get_spawn_point(game_map)
      # users always get spawn point regardless of pos
      user_entity = Entity.new(name: "alice", type: :user, pos: {999, 999})

      assert {:ok, ^spawn_point} = WorldServer.join_entity(user_entity, server)
    end
  end

  describe "entity-entity collision on movement" do
    test "player cannot walk onto a mob's tile", %{server: server} do
      {:ok, user} = User.new("alice")
      {:ok, {sx, sy}} = WorldServer.join_user(user, server)
      mob_pos = {sx + 1, sy}
      mob = Entity.new(name: "goblin", type: :mob, pos: mob_pos)
      {:ok, _pos} = WorldServer.join_entity(mob, server)
      mob_id = mob.id

      assert {:error, {:collision, ^mob_pos, {:mob, ^mob_id}}} =
               WorldServer.move(user.id, :east, server)
    end

    test "mob cannot walk onto a player's tile", %{server: server} do
      {:ok, user} = User.new("alice")
      {:ok, {sx, sy} = spawn} = WorldServer.join_user(user, server)
      mob_pos = {sx + 1, sy}
      mob = Entity.new(name: "goblin", type: :mob, pos: mob_pos)
      {:ok, _pos} = WorldServer.join_entity(mob, server)
      user_id = user.id

      assert {:error, {:collision, ^spawn, {:user, ^user_id}}} =
               WorldServer.move(mob.id, :west, server)
    end

    test "mob cannot walk onto another mob's tile", %{server: server} do
      game_map = WorldServer.get_map(server)

      # find two adjacent floor tiles
      {pos1, pos2, direction} =
        Enum.find_value(game_map.tiles, fn
          {{x, y}, :floor} ->
            cond do
              !GameMap.collision?(game_map, {x + 1, y}) -> {{x, y}, {x + 1, y}, :east}
              !GameMap.collision?(game_map, {x, y + 1}) -> {{x, y}, {x, y + 1}, :south}
              true -> nil
            end

          _ ->
            nil
        end)

      mob1 = Entity.new(name: "goblin", type: :mob, pos: pos1)
      mob2 = Entity.new(name: "spider", type: :mob, pos: pos2)
      {:ok, _pos} = WorldServer.join_entity(mob1, server)
      {:ok, _pos} = WorldServer.join_entity(mob2, server)
      mob2_id = mob2.id

      assert {:error, {:collision, ^pos2, {:mob, ^mob2_id}}} =
               WorldServer.move(mob1.id, direction, server)
    end

    test "players can stack on each other", %{server: server} do
      {:ok, alice} = User.new("alice")
      {:ok, bob} = User.new("bob")
      {:ok, {sx, sy}} = WorldServer.join_user(alice, server)
      {:ok, _spawn} = WorldServer.join_user(bob, server)

      east = {sx + 1, sy}
      {:ok, ^east} = WorldServer.move(alice.id, :east, server)
      Process.sleep(WorldServer.move_cooldown_ms() + 1)
      # bob follows alice — should succeed
      assert {:ok, ^east} = WorldServer.move(bob.id, :east, server)
    end

    test "movement still works when destination is empty", %{server: server} do
      {:ok, user} = User.new("alice")
      {:ok, {sx, sy}} = WorldServer.join_user(user, server)

      assert {:ok, {x, ^sy}} = WorldServer.move(user.id, :east, server)
      assert x == sx + 1
    end

    test "entity collision does not broadcast movement", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.movement_topic())
      {:ok, user} = User.new("alice")
      {:ok, {sx, sy}} = WorldServer.join_user(user, server)
      mob = Entity.new(name: "goblin", type: :mob, pos: {sx + 1, sy})
      {:ok, _pos} = WorldServer.join_entity(mob, server)

      {:error, {:collision, _, _}} = WorldServer.move(user.id, :east, server)

      refute_receive {:entity_moved, _, _}
    end
  end
end
