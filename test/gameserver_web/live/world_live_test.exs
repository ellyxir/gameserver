defmodule GameserverWeb.WorldLiveTest do
  # async: false because tests interact with the global WorldServer
  use GameserverWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  import ExUnit.CaptureLog

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

  # TODO(@ellyxir): replace log-based assertions with state change
  # assertions once movement updates player position
  describe "keyboard input" do
    setup do
      previous_level = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: previous_level) end)
    end

    @tag capture_log: true
    test "wasd keys map to cardinal directions", %{conn: conn} do
      {:ok, user} = User.new("wasduser")
      {:ok, _position} = WorldServer.join(user)
      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      for {key, direction} <- [{"w", "north"}, {"a", "west"}, {"s", "south"}, {"d", "east"}] do
        log =
          capture_log(fn ->
            render_keydown(view, "keydown", %{"key" => key})
          end)

        assert log =~ direction, "expected #{key} to map to #{direction}"
      end
    end

    @tag capture_log: true
    test "arrow keys map to cardinal directions", %{conn: conn} do
      {:ok, user} = User.new("arrowuser")
      {:ok, _position} = WorldServer.join(user)
      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      for {key, direction} <-
            [
              {"ArrowUp", "north"},
              {"ArrowLeft", "west"},
              {"ArrowDown", "south"},
              {"ArrowRight", "east"}
            ] do
        log =
          capture_log(fn ->
            render_keydown(view, "keydown", %{"key" => key})
          end)

        assert log =~ direction, "expected #{key} to map to #{direction}"
      end
    end

    test "unmapped keys don't crash", %{conn: conn} do
      {:ok, user} = User.new("otherkey")
      {:ok, _position} = WorldServer.join(user)
      {:ok, view, _html} = live(conn, ~p"/world?user_id=#{user.id}")

      render_keydown(view, "keydown", %{"key" => "x"})

      assert render(view) =~ "Online Users"
    end
  end
end
