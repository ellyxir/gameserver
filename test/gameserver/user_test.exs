defmodule Gameserver.UserTest do
  use ExUnit.Case, async: true

  alias Gameserver.User

  defp valid_uuid?(uuid), do: match?({:ok, _}, Ecto.UUID.cast(uuid))

  describe "new/1 with keyword list" do
    test "creates user from id and username" do
      id = Ecto.UUID.generate()
      assert {:ok, user} = User.new(id: id, username: "alice")
      assert user.id == id
      assert user.username == "alice"
    end

    test "raises on unknown keys" do
      assert_raise KeyError, fn ->
        User.new(id: Ecto.UUID.generate(), username: "alice", email: "a@b.com")
      end
    end
  end

  describe "new/1 with username string" do
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

  describe "validate_username/1" do
    test "returns changeset with action :validate" do
      changeset = User.validate_username("alice")
      assert changeset.action == :validate
    end

    test "valid username returns valid changeset" do
      changeset = User.validate_username("alice")
      assert changeset.valid?
    end

    test "invalid username returns invalid changeset with errors" do
      changeset = User.validate_username("")
      refute changeset.valid?
      assert {:username, _} = hd(changeset.errors)
    end

    test "too short username has error" do
      changeset = User.validate_username("ab")
      refute changeset.valid?
    end

    test "too long username has error" do
      changeset = User.validate_username("abcdefghijklmnopqrstu")
      refute changeset.valid?
    end
  end
end
