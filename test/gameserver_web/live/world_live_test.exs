defmodule GameserverWeb.WorldLiveTest do
  # async: false because tests interact with the global WorldServer
  use GameserverWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gameserver.User
  alias Gameserver.WorldServer

  describe "mount" do
    test "redirects to /game when user_id not provided", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/game"}}} = live(conn, ~p"/world")
    end

    test "redirects to /game when user_id not in WorldServer", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      assert {:error, {:live_redirect, %{to: "/game"}}} =
               live(conn, ~p"/world?user_id=#{fake_id}")
    end

    test "renders world page when user is valid", %{conn: conn} do
      {:ok, user} = User.new("validuser")
      {:ok, _position} = WorldServer.join(user)

      {:ok, _view, html} = live(conn, ~p"/world?user_id=#{user.id}")

      assert html =~ "Online Users"
      assert html =~ "validuser"
    end
  end

  describe "online users list" do
    test "shows all online users", %{conn: conn} do
      {:ok, alice} = User.new("alice")
      {:ok, bob} = User.new("bob")
      {:ok, _position} = WorldServer.join(alice)
      {:ok, _position} = WorldServer.join(bob)

      {:ok, _view, html} = live(conn, ~p"/world?user_id=#{alice.id}")

      assert html =~ "alice"
      assert html =~ "bob"
    end
  end

  describe "player on map" do
    test "renders player as @ on the map", %{conn: conn} do
      {:ok, user} = User.new("mapplayer")
      {:ok, _position} = WorldServer.join(user)

      {:ok, _view, html} = live(conn, ~p"/world?user_id=#{user.id}")

      assert html =~ "@"
    end

    test "shows player position coordinates", %{conn: conn} do
      {:ok, user} = User.new("posplayer")
      {:ok, {x, y}} = WorldServer.join(user)

      {:ok, _view, html} = live(conn, ~p"/world?user_id=#{user.id}")

      assert html =~ "Position: {#{x}, #{y}}"
    end
  end

  describe "disconnect" do
    test "calls leave on WorldServer when LiveView terminates", %{conn: conn} do
      {:ok, user} = User.new("disconnectuser")
      {:ok, _position} = WorldServer.join(user)

      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())

      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      # Verify user is in the world
      assert [{_, "disconnectuser"}] = WorldServer.who(user.id, WorldServer)

      # Terminate the LiveView (simulates browser tab close)
      GenServer.stop(view.pid)

      # Should broadcast user_left
      assert_receive {:user_left, ^user}

      # User should be removed from WorldServer
      assert [] = WorldServer.who(user.id, WorldServer)
    end
  end

  describe "pubsub updates" do
    test "updates when new user joins", %{conn: conn} do
      {:ok, alice} = User.new("pubsubalice")
      {:ok, _position} = WorldServer.join(alice)

      {:ok, view, html} = live(conn, ~p"/world?user_id=#{alice.id}")
      assert html =~ "pubsubalice"
      refute html =~ "newuser"

      # Simulate another user joining
      {:ok, bob} = User.new("newuser")
      {:ok, _position} = WorldServer.join(bob)

      # Wait for pubsub update
      html = render(view)
      assert html =~ "newuser"
    end

    test "updates when user leaves", %{conn: conn} do
      {:ok, alice} = User.new("pubsubalice2")
      {:ok, bob} = User.new("leavinguser")
      {:ok, _position} = WorldServer.join(alice)
      {:ok, _position} = WorldServer.join(bob)

      {:ok, view, html} = live(conn, ~p"/world?user_id=#{alice.id}")
      assert html =~ "leavinguser"

      # Bob leaves
      :ok = WorldServer.leave(bob.id)

      # Wait for pubsub update
      html = render(view)
      refute html =~ "leavinguser"
    end
  end

  describe "keyboard input" do
    test "wasd keys move the player", %{conn: conn} do
      {:ok, user} = User.new("wasduser")
      {:ok, {px, py}} = WorldServer.join(user)
      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      # move east (d key) from spawn {1,1} to {2,1}
      html = render_keydown(view, "keydown", %{"key" => "d"})
      assert html =~ "Position: {#{px + 1}, #{py}}"
    end

    test "arrow keys move the player", %{conn: conn} do
      {:ok, user} = User.new("arrowuser")
      {:ok, {px, py}} = WorldServer.join(user)
      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      html = render_keydown(view, "keydown", %{"key" => "ArrowRight"})
      assert html =~ "Position: {#{px + 1}, #{py}}"
    end

    test "unmapped keys don't crash", %{conn: conn} do
      {:ok, user} = User.new("otherkey")
      {:ok, _position} = WorldServer.join(user)
      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      render_keydown(view, "keydown", %{"key" => "x"})

      assert render(view) =~ "Online Users"
    end
  end

  describe "tile click input" do
    test "clicking adjacent tile moves the player", %{conn: conn} do
      {:ok, user} = User.new("tapper")
      {:ok, {px, py}} = WorldServer.join(user)
      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      # click east of spawn
      html =
        render_click(view, "tile-click", %{
          "x" => to_string(px + 1),
          "y" => to_string(py)
        })

      assert html =~ "Position: {#{px + 1}, #{py}}"
    end

    test "clicking own tile doesn't crash", %{conn: conn} do
      {:ok, user} = User.new("selftapper")
      {:ok, {px, py}} = WorldServer.join(user)
      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      render_click(view, "tile-click", %{"x" => to_string(px), "y" => to_string(py)})

      assert render(view) =~ "Online Users"
    end

    test "clicking into a wall doesn't move", %{conn: conn} do
      {:ok, user} = User.new("walltapper")
      {:ok, {px, py}} = WorldServer.join(user)
      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      # click north of spawn {1,1} hits wall at {1,0}
      render_click(view, "tile-click", %{
        "x" => to_string(px),
        "y" => to_string(py - 1)
      })

      html = render(view)
      assert html =~ "Position: {#{px}, #{py}}"
    end
  end
end
