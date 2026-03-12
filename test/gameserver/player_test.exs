defmodule Gameserver.PlayerTest do
  use ExUnit.Case, async: true

  alias Gameserver.Player
  alias Gameserver.User

  describe "new/2" do
    test "creates a player with user and position" do
      {:ok, user} = User.new("alice")
      position = {5, 3}

      player = Player.new(user, position)

      assert player.user == user
      assert player.position == position
      assert %Gameserver.Cooldowns{} = player.cooldowns
    end
  end

  describe "id/1" do
    test "returns the player's user id" do
      {:ok, user} = User.new("bob")
      player = Player.new(user, {0, 0})

      assert Player.id(player) == user.id
    end
  end
end
