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
    test "adds user to the world", %{server: server} do
      {:ok, user} = User.new("alice")

      assert :ok = WorldServer.join(user, server)
    end

    test "returns error when user already joined", %{server: server} do
      {:ok, user} = User.new("alice")

      :ok = WorldServer.join(user, server)
      assert {:error, :already_joined} = WorldServer.join(user, server)
    end

    test "allows rejoin after leaving", %{server: server} do
      {:ok, user} = User.new("alice")

      :ok = WorldServer.join(user, server)
      :ok = WorldServer.leave(user, server)
      assert :ok = WorldServer.join(user, server)
    end
  end

  describe "leave/2" do
    test "removes user from the world", %{server: server} do
      {:ok, user} = User.new("alice")
      :ok = WorldServer.join(user, server)

      assert :ok = WorldServer.leave(user, server)
    end

    test "returns error when user not in world", %{server: server} do
      {:ok, user} = User.new("alice")

      assert {:error, :not_found} = WorldServer.leave(user, server)
    end
  end

  describe "who/1" do
    test "returns empty list when no users", %{server: server} do
      assert [] = WorldServer.who(server)
    end

    test "returns all users when called with no filter", %{server: server} do
      {:ok, alice} = User.new("alice")
      {:ok, bob} = User.new("bob")
      :ok = WorldServer.join(alice, server)
      :ok = WorldServer.join(bob, server)

      result = WorldServer.who(server)

      assert length(result) == 2
      assert {alice.id, "alice"} in result
      assert {bob.id, "bob"} in result
    end

    test "returns single user when given user_id", %{server: server} do
      {:ok, alice} = User.new("alice")
      {:ok, bob} = User.new("bob")
      :ok = WorldServer.join(alice, server)
      :ok = WorldServer.join(bob, server)

      assert [{alice.id, "alice"}] == WorldServer.who(alice.id, server)
    end

    test "returns empty list when user_id not found", %{server: server} do
      assert [] = WorldServer.who("nonexistent-id", server)
    end

    test "returns matching users when given list of user_ids", %{server: server} do
      {:ok, alice} = User.new("alice")
      {:ok, bob} = User.new("bob")
      {:ok, charlie} = User.new("charlie")
      :ok = WorldServer.join(alice, server)
      :ok = WorldServer.join(bob, server)
      :ok = WorldServer.join(charlie, server)

      result = WorldServer.who([alice.id, charlie.id], server)

      assert length(result) == 2
      assert {alice.id, "alice"} in result
      assert {charlie.id, "charlie"} in result
      refute {bob.id, "bob"} in result
    end

    test "ignores unknown ids in list", %{server: server} do
      {:ok, alice} = User.new("alice")
      :ok = WorldServer.join(alice, server)

      result = WorldServer.who([alice.id, "unknown-id"], server)

      assert [{alice.id, "alice"}] == result
    end
  end
end
