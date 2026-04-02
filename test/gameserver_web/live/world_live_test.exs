defmodule GameserverWeb.WorldLiveTest do
  # async: false because tests interact with the global WorldServer
  use GameserverWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gameserver.CombatEvent
  alias Gameserver.Map, as: GameMap
  alias Gameserver.User
  alias Gameserver.UUID
  alias Gameserver.WorldServer

  # clear all entities between tests so mobs from MobServer or previous tests
  # don't cause collision errors when spawning new entities
  setup do
    on_exit(fn ->
      WorldServer.world_nodes()
      |> Enum.each(fn {id, _} -> WorldServer.leave(id) end)
    end)
  end

  defp random_floor_pos(room_index \\ 0) do
    map = WorldServer.get_map()
    room = Enum.at(map.rooms, rem(room_index, length(map.rooms)))
    GameMap.random_tile_in_room(map, room)
  end

  describe "mount" do
    test "redirects to /game when user_id not provided", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/game"}}} = live(conn, ~p"/world")
    end

    test "redirects to /game when user_id not in WorldServer", %{conn: conn} do
      fake_id = UUID.generate()

      assert {:error, {:live_redirect, %{to: "/game"}}} =
               live(conn, ~p"/world?user_id=#{fake_id}")
    end

    test "renders world page when user is valid", %{conn: conn} do
      {:ok, user} = User.new("validuser")
      {:ok, _position} = WorldServer.join_user(user)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      assert has_element?(view, "h2", "Online Users")
      assert has_element?(view, "li", "validuser")
    end

    test "wraps content with Layouts.app", %{conn: conn} do
      {:ok, user} = User.new("layoutuser")
      {:ok, _position} = WorldServer.join_user(user)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      assert has_element?(view, "header.navbar")
    end
  end

  describe "online users list" do
    test "shows all online users", %{conn: conn} do
      {:ok, alice} = User.new("alice")
      {:ok, bob} = User.new("bob")
      {:ok, _position} = WorldServer.join_user(alice)
      {:ok, _position} = WorldServer.join_user(bob)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{alice.id}")

      assert has_element?(view, "li", "alice")
      assert has_element?(view, "li", "bob")
    end
  end

  describe "player hp display" do
    test "renders player hp on mount", %{conn: conn} do
      {:ok, user} = User.new("hpplayer")
      {:ok, _position} = WorldServer.join_user(user)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      assert has_element?(view, "#player-hp")
      assert has_element?(view, "#player-hp", "10/10")
    end

    test "updates hp when player entity changes", %{conn: conn} do
      {:ok, user} = User.new("hpupdate")
      {:ok, _position} = WorldServer.join_user(user)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      alias Gameserver.EntityServer

      {:ok, _updated} =
        EntityServer.update_entity(user.id, fn entity ->
          %{entity | stats: %{entity.stats | hp: 7}}
        end)

      assert has_element?(view, "#player-hp", "7/10")
    end
  end

  describe "player on map" do
    test "renders player as @ on the map", %{conn: conn} do
      {:ok, user} = User.new("mapplayer")
      {:ok, _position} = WorldServer.join_user(user)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      assert has_element?(view, "[data-entity=player]", "@")
    end

    test "shows player position coordinates", %{conn: conn} do
      {:ok, user} = User.new("posplayer")
      {:ok, {x, y}} = WorldServer.join_user(user)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      assert has_element?(view, "#player-position", "Position: {#{x}, #{y}}")
    end

    test "renders other player on the map", %{conn: conn} do
      {:ok, alice} = User.new("alice_map")
      {:ok, bob} = User.new("bob_map")
      {:ok, _position} = WorldServer.join_user(alice)
      {:ok, _position} = WorldServer.join_user(bob)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{alice.id}")

      # Both players share the spawn point, but we should see at least one @
      assert has_element?(view, "[data-entity=player]", "@")
    end

    test "renders other player in distinct style", %{conn: conn} do
      {:ok, alice} = User.new("alice_style")
      {:ok, bob} = User.new("bob_style")
      {:ok, _pos} = WorldServer.join_user(alice)
      {:ok, _pos} = WorldServer.join_user(bob)

      # Move bob so he's not on the same tile as alice
      WorldServer.move(bob.id, :east)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{alice.id}")

      assert has_element?(view, "[data-entity=player]")
      assert has_element?(view, "[data-entity=other-player]")
    end
  end

  describe "disconnect" do
    test "calls leave on WorldServer when LiveView terminates", %{conn: conn} do
      {:ok, user} = User.new("disconnectuser")
      {:ok, _position} = WorldServer.join_user(user)

      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      # Verify user is in the world
      assert [{_, "disconnectuser"}] = WorldServer.who(user.id, WorldServer)

      # Terminate the LiveView (simulates browser tab close)
      GenServer.stop(view.pid)

      # Should broadcast entity_left
      assert_receive {:entity_left, id}
      assert id == user.id

      # User should be removed from WorldServer
      assert [] = WorldServer.who(user.id, WorldServer)
    end
  end

  describe "pubsub updates" do
    test "updates when new user joins", %{conn: conn} do
      {:ok, alice} = User.new("pubsubalice")
      {:ok, _position} = WorldServer.join_user(alice)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{alice.id}")
      assert has_element?(view, "li", "pubsubalice")
      refute has_element?(view, "li", "newuser")

      # Simulate another user joining
      {:ok, bob} = User.new("newuser")
      {:ok, _position} = WorldServer.join_user(bob)

      # Wait for pubsub update
      render(view)
      assert has_element?(view, "li", "newuser")
    end

    test "updates other player position on movement", %{conn: conn} do
      {:ok, alice} = User.new("alice_move")
      {:ok, bob} = User.new("bob_move")
      {:ok, _pos} = WorldServer.join_user(alice)
      {:ok, _pos} = WorldServer.join_user(bob)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{alice.id}")

      # Move bob east — alice's view should update
      WorldServer.move(bob.id, :east)

      # Wait for pubsub update
      render(view)
      assert has_element?(view, "[data-entity=other-player]")
    end

    test "updates when user leaves", %{conn: conn} do
      {:ok, alice} = User.new("pubsubalice2")
      {:ok, bob} = User.new("leavinguser")
      {:ok, _position} = WorldServer.join_user(alice)
      {:ok, _position} = WorldServer.join_user(bob)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{alice.id}")
      assert has_element?(view, "li", "leavinguser")

      # Bob leaves
      :ok = WorldServer.leave(bob.id)

      # Wait for pubsub update
      render(view)
      refute has_element?(view, "li", "leavinguser")
    end
  end

  describe "mob rendering" do
    test "renders mob on the map", %{conn: conn} do
      {:ok, user} = User.new("mobviewer")
      {:ok, _pos} = WorldServer.join_user(user)

      alias Gameserver.Entity
      mob = Entity.new(name: "goblin", type: :mob, pos: random_floor_pos())
      {:ok, _pos} = WorldServer.join_entity(mob)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      # mob rendered as first letter of name in red
      assert has_element?(view, "[data-entity=mob]", "g")
    end

    test "mob appears when it joins after mount", %{conn: conn} do
      {:ok, user} = User.new("mobwatcher")
      {:ok, _pos} = WorldServer.join_user(user)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      alias Gameserver.Entity
      mob = Entity.new(name: "goblin", type: :mob, pos: random_floor_pos())
      {:ok, _pos} = WorldServer.join_entity(mob)

      assert has_element?(view, "[data-entity=mob]")
    end

    test "mob disappears when it leaves", %{conn: conn} do
      {:ok, user} = User.new("mobleftviewer")
      {:ok, _pos} = WorldServer.join_user(user)

      alias Gameserver.Entity
      mob = Entity.new(name: "goblin", type: :mob, pos: random_floor_pos(1))
      {:ok, {mx, my}} = WorldServer.join_entity(mob)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      assert has_element?(view, "[data-entity=mob]")

      WorldServer.leave(mob.id)

      render(view)
      refute has_element?(view, ~s|[data-entity=mob][phx-value-x="#{mx}"][phx-value-y="#{my}"]|)
    end
  end

  describe "keyboard input" do
    test "wasd keys move the player", %{conn: conn} do
      {:ok, user} = User.new("wasduser")
      {:ok, {px, py}} = WorldServer.join_user(user)
      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      # move east (d key) from spawn {1,1} to {2,1}
      render_keydown(view, "keydown", %{"key" => "d"})
      assert has_element?(view, "#player-position", "Position: {#{px + 1}, #{py}}")
    end

    test "arrow keys move the player", %{conn: conn} do
      {:ok, user} = User.new("arrowuser")
      {:ok, {px, py}} = WorldServer.join_user(user)
      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      render_keydown(view, "keydown", %{"key" => "ArrowRight"})
      assert has_element?(view, "#player-position", "Position: {#{px + 1}, #{py}}")
    end

    test "unmapped keys don't crash", %{conn: conn} do
      {:ok, user} = User.new("otherkey")
      {:ok, _position} = WorldServer.join_user(user)
      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      render_keydown(view, "keydown", %{"key" => "x"})

      assert has_element?(view, "h2", "Online Users")
    end
  end

  describe "combat log" do
    test "shows message when player attacks mob", %{conn: conn} do
      {:ok, user} = User.new("fighter")
      {:ok, _pos} = WorldServer.join_user(user)

      alias Gameserver.{CombatServer, Entity}
      mob = Entity.new(name: "goblin", type: :mob, pos: random_floor_pos())
      {:ok, _pos} = WorldServer.join_entity(mob)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      Phoenix.PubSub.broadcast!(
        Gameserver.PubSub,
        CombatServer.combat_topic(),
        {:combat_event,
         %CombatEvent{attacker_id: user.id, defender_id: mob.id, damage: 1, defender_hp: 9}}
      )

      assert has_element?(view, "#combat-log")
      assert has_element?(view, "#combat-log div", "You hit goblin for 1 (9 hp)")
    end

    test "shows message when mob attacks player", %{conn: conn} do
      {:ok, user} = User.new("defender")
      {:ok, _pos} = WorldServer.join_user(user)

      alias Gameserver.{CombatServer, Entity}
      mob = Entity.new(name: "spider", type: :mob, pos: random_floor_pos(1))
      {:ok, _pos} = WorldServer.join_entity(mob)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      Phoenix.PubSub.broadcast!(
        Gameserver.PubSub,
        CombatServer.combat_topic(),
        {:combat_event,
         %CombatEvent{attacker_id: mob.id, defender_id: user.id, damage: 2, defender_hp: 8}}
      )

      assert has_element?(view, "#combat-log div", "spider hits you for 2 (8 hp)")
    end

    test "combat log has auto-scroll hook", %{conn: conn} do
      {:ok, user} = User.new("scrolluser")
      {:ok, _pos} = WorldServer.join_user(user)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      assert has_element?(view, "#combat-log[phx-hook=ScrollBottom]")
    end

    test "shows kill message when defender hp reaches zero", %{conn: conn} do
      {:ok, user} = User.new("slayer")
      {:ok, _pos} = WorldServer.join_user(user)

      alias Gameserver.{CombatServer, Entity}
      mob = Entity.new(name: "rat", type: :mob, pos: random_floor_pos(2))
      {:ok, _pos} = WorldServer.join_entity(mob)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      Phoenix.PubSub.broadcast!(
        Gameserver.PubSub,
        CombatServer.combat_topic(),
        {:combat_event,
         %CombatEvent{
           attacker_id: user.id,
           defender_id: mob.id,
           damage: 1,
           defender_hp: 0,
           dead: true
         }}
      )

      assert has_element?(view, "#combat-log div", "You killed rat!")
    end

    test "caps combat log to recent entries", %{conn: conn} do
      {:ok, user} = User.new("logcapper")
      {:ok, _pos} = WorldServer.join_user(user)

      alias Gameserver.{CombatServer, Entity}
      mob = Entity.new(name: "goblin", type: :mob, pos: random_floor_pos())
      {:ok, _pos} = WorldServer.join_entity(mob)

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      # send more events than the cap (50)
      for i <- 1..51 do
        Phoenix.PubSub.broadcast!(
          Gameserver.PubSub,
          CombatServer.combat_topic(),
          {:combat_event,
           %CombatEvent{
             attacker_id: user.id,
             defender_id: mob.id,
             damage: 1,
             defender_hp: 100 - i
           }}
        )
      end

      render(view)

      # the first message (hp 99) should have been evicted
      refute has_element?(view, "#combat-log div", "(99 hp)")
      # the last message (hp 49) should still be present
      assert has_element?(view, "#combat-log div", "(49 hp)")
    end
  end

  describe "tile click input" do
    test "clicking adjacent tile moves the player", %{conn: conn} do
      {:ok, user} = User.new("tapper")
      {:ok, {px, py}} = WorldServer.join_user(user)
      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      # click east of spawn
      render_click(view, "tile-click", %{
        "x" => to_string(px + 1),
        "y" => to_string(py)
      })

      assert has_element?(view, "#player-position", "Position: {#{px + 1}, #{py}}")
    end

    test "clicking own tile doesn't crash", %{conn: conn} do
      {:ok, user} = User.new("selftapper")
      {:ok, {px, py}} = WorldServer.join_user(user)
      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      render_click(view, "tile-click", %{"x" => to_string(px), "y" => to_string(py)})

      assert has_element?(view, "h2", "Online Users")
    end

    test "clicking into a wall doesn't move", %{conn: conn} do
      {:ok, user} = User.new("walltapper")
      {:ok, {px, py}} = WorldServer.join_user(user)
      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      # click north of spawn {1,1} hits wall at {1,0}
      render_click(view, "tile-click", %{
        "x" => to_string(px),
        "y" => to_string(py - 1)
      })

      assert has_element?(view, "#player-position", "Position: {#{px}, #{py}}")
    end
  end
end
