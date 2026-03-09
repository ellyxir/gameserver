defmodule Gameserver.WorldServerTest do
  use ExUnit.Case, async: true

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

  describe "join/2" do
    test "adds user to the world and returns spawn position", %{server: server} do
      {:ok, user} = User.new("alice")

      assert {:ok, {x, y}} = WorldServer.join(user, server)
      assert is_integer(x) and is_integer(y)
    end

    test "returns error when user already joined", %{server: server} do
      {:ok, user} = User.new("alice")

      {:ok, _position} = WorldServer.join(user, server)
      assert {:error, :already_joined} = WorldServer.join(user, server)
    end

    test "returns error when username already taken", %{server: server} do
      {:ok, alice1} = User.new("alice")
      {:ok, alice2} = User.new("alice")

      {:ok, _position} = WorldServer.join(alice1, server)
      assert {:error, :username_not_available} = WorldServer.join(alice2, server)
    end

    test "allows same username after original user leaves", %{server: server} do
      {:ok, alice1} = User.new("alice")
      {:ok, alice2} = User.new("alice")

      {:ok, _position} = WorldServer.join(alice1, server)
      :ok = WorldServer.leave(alice1.id, server)
      assert {:ok, _position} = WorldServer.join(alice2, server)
    end

    test "allows rejoin after leaving", %{server: server} do
      {:ok, user} = User.new("alice")

      {:ok, _position} = WorldServer.join(user, server)
      :ok = WorldServer.leave(user.id, server)
      assert {:ok, _position} = WorldServer.join(user, server)
    end
  end

  describe "leave/2" do
    test "removes user from the world", %{server: server} do
      {:ok, user} = User.new("alice")
      {:ok, _position} = WorldServer.join(user, server)

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
      {:ok, _position} = WorldServer.join(alice, server)
      {:ok, _position} = WorldServer.join(bob, server)

      result = WorldServer.who(server)

      assert length(result) == 2
      assert {alice.id, "alice"} in result
      assert {bob.id, "bob"} in result
    end

    test "returns single user when given user_id", %{server: server} do
      {:ok, alice} = User.new("alice")
      {:ok, bob} = User.new("bob")
      {:ok, _position} = WorldServer.join(alice, server)
      {:ok, _position} = WorldServer.join(bob, server)

      assert [{alice.id, "alice"}] == WorldServer.who(alice.id, server)
    end

    test "returns empty list when user_id not found", %{server: server} do
      assert [] = WorldServer.who("nonexistent-id", server)
    end

    test "returns matching users when given list of user_ids", %{server: server} do
      {:ok, alice} = User.new("alice")
      {:ok, bob} = User.new("bob")
      {:ok, charlie} = User.new("charlie")
      {:ok, _position} = WorldServer.join(alice, server)
      {:ok, _position} = WorldServer.join(bob, server)
      {:ok, _position} = WorldServer.join(charlie, server)

      result = WorldServer.who([alice.id, charlie.id], server)

      assert length(result) == 2
      assert {alice.id, "alice"} in result
      assert {charlie.id, "charlie"} in result
      refute {bob.id, "bob"} in result
    end

    test "ignores unknown ids in list", %{server: server} do
      {:ok, alice} = User.new("alice")
      {:ok, _position} = WorldServer.join(alice, server)

      result = WorldServer.who([alice.id, "unknown-id"], server)

      assert [{alice.id, "alice"}] == result
    end
  end

  describe "get_position/2" do
    test "returns position for joined player", %{server: server} do
      {:ok, alice} = User.new("alice")
      {:ok, spawn_position} = WorldServer.join(alice, server)

      assert {:ok, ^spawn_position} = WorldServer.get_position(alice.id, server)
    end

    test "returns error for unknown player", %{server: server} do
      fake_id = Ecto.UUID.generate()

      assert {:error, :not_found} = WorldServer.get_position(fake_id, server)
    end
  end

  describe "pubsub broadcasts" do
    test "broadcasts user_joined on successful join", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, "world:presence")
      {:ok, alice} = User.new("alice")

      {:ok, _position} = WorldServer.join(alice, server)

      assert_receive {:user_joined, ^alice}
    end

    test "does not broadcast on failed join", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, "world:presence")
      {:ok, alice} = User.new("alice")
      {:ok, _position} = WorldServer.join(alice, server)

      # Clear the first message
      assert_receive {:user_joined, ^alice}

      # Try to join again - should fail
      {:error, :already_joined} = WorldServer.join(alice, server)

      refute_receive {:user_joined, _}
    end

    test "does not broadcast on username collision", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, "world:presence")
      {:ok, alice1} = User.new("alice")
      {:ok, alice2} = User.new("alice")

      {:ok, _position} = WorldServer.join(alice1, server)
      assert_receive {:user_joined, ^alice1}

      {:error, :username_not_available} = WorldServer.join(alice2, server)
      refute_receive {:user_joined, _}
    end

    test "broadcasts user_left on successful leave", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, "world:presence")
      {:ok, alice} = User.new("alice")
      {:ok, _position} = WorldServer.join(alice, server)
      assert_receive {:user_joined, ^alice}

      :ok = WorldServer.leave(alice.id, server)

      assert_receive {:user_left, ^alice}
    end

    test "does not broadcast on failed leave", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, "world:presence")
      fake_id = Ecto.UUID.generate()

      {:error, :not_found} = WorldServer.leave(fake_id, server)

      refute_receive {:user_left, _}
    end
  end
end
