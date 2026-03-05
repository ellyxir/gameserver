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
end
