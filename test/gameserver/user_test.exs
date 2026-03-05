defmodule Gameserver.UserTest do
  use ExUnit.Case, async: true

  alias Gameserver.User

  defp valid_uuid?(uuid), do: match?({:ok, _}, Ecto.UUID.cast(uuid))

  describe "new/1" do
    test "creates user with valid username" do
      assert {:ok, %User{username: "alice", id: id}} = User.new("alice")
      assert valid_uuid?(id)
    end

    test "returns :required for empty username" do
      assert {:error, :required} = User.new("")
    end

    test "returns :too_short for username under 3 characters" do
      assert {:error, :too_short} = User.new("ab")
    end

    test "returns :too_long for username over 20 characters" do
      assert {:error, :too_long} = User.new("abcdefghijklmnopqrstu")
    end

    test "returns :invalid_format for username with spaces" do
      assert {:error, :invalid_format} = User.new("hello world")
    end

    test "returns :invalid_format for username with special characters" do
      assert {:error, :invalid_format} = User.new("user@name")
    end

    test "accepts underscores and hyphens" do
      assert {:ok, %User{username: "user_name"}} = User.new("user_name")
      assert {:ok, %User{username: "user-name"}} = User.new("user-name")
    end

    test "accepts alphanumeric characters" do
      assert {:ok, %User{username: "Player123"}} = User.new("Player123")
    end
  end
end
