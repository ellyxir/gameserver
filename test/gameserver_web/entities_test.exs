defmodule GameserverWeb.EntitiesTest do
  use ExUnit.Case, async: true

  alias Gameserver.Entity
  alias Gameserver.User
  alias GameserverWeb.Entities

  defp make_entities do
    {:ok, alice} = User.new(id: "id-a", username: "alice")
    {:ok, bob} = User.new(id: "id-b", username: "bob")
    goblin = Entity.new(id: "id-g", name: "goblin", type: :mob, pos: {3, 2})

    %Entities{}
    |> Entities.add_players([{alice, {1, 1}}, {bob, {2, 1}}])
    |> Entities.add_mobs([{goblin, {3, 2}}])
  end

  describe "add_players/2" do
    test "adds players from WorldServer.players() format" do
      {:ok, alice} = User.new(id: "id-a", username: "alice")

      entities =
        %Entities{}
        |> Entities.add_players([{alice, {1, 1}}])

      assert Entities.has_entity?(entities, "id-a")
      assert Entities.get_position(entities, "id-a") == {:ok, {1, 1}}
    end
  end

  describe "add_mobs/2" do
    test "adds mobs from WorldServer.mobs() format" do
      mob = Entity.new(id: "id-m", name: "goblin", type: :mob, pos: {5, 5})

      entities =
        %Entities{}
        |> Entities.add_mobs([{mob, {5, 5}}])

      assert Entities.has_entity?(entities, "id-m")
      assert Entities.get_position(entities, "id-m") == {:ok, {5, 5}}
    end
  end

  describe "add_entity/2" do
    test "adds a single entity from a PubSub join" do
      entity = Entity.new(id: "id-e", name: "rat", type: :mob, pos: {4, 4})

      entities =
        %Entities{}
        |> Entities.add_entity(entity)

      assert Entities.has_entity?(entities, "id-e")
      assert Entities.get_position(entities, "id-e") == {:ok, {4, 4}}
    end
  end

  describe "has_entity?/2" do
    test "returns false for unknown id" do
      refute Entities.has_entity?(%Entities{}, "nope")
    end
  end

  describe "get_position/2" do
    test "returns :error for unknown id" do
      assert Entities.get_position(%Entities{}, "nope") == :error
    end
  end

  describe "update_position/3" do
    test "updates an existing entity's position" do
      entities = make_entities()
      updated = Entities.update_position(entities, "id-a", {9, 9})
      assert Entities.get_position(updated, "id-a") == {:ok, {9, 9}}
    end
  end

  describe "remove/2" do
    test "removes an entity by id" do
      entities = make_entities()
      updated = Entities.remove(entities, "id-a")
      refute Entities.has_entity?(updated, "id-a")
      assert Entities.has_entity?(updated, "id-b")
    end
  end

  describe "players_at/2" do
    test "returns player ids at the given coordinate" do
      entities = make_entities()
      assert Entities.players_at(entities, {1, 1}) == ["id-a"]
      assert Entities.players_at(entities, {99, 99}) == []
    end

    test "does not include mobs" do
      entities = make_entities()
      assert Entities.players_at(entities, {3, 2}) == []
    end
  end

  describe "mob_symbol_at/2" do
    test "returns first letter of mob name at coordinate" do
      entities = make_entities()
      assert Entities.mob_symbol_at(entities, {3, 2}) == "g"
    end

    test "returns nil when no mob at coordinate" do
      entities = make_entities()
      assert Entities.mob_symbol_at(entities, {1, 1}) == nil
    end

    test "does not match player positions" do
      entities = make_entities()
      assert Entities.mob_symbol_at(entities, {1, 1}) == nil
    end
  end

  describe "usernames/1" do
    test "returns all player usernames" do
      entities = make_entities()
      names = Entities.usernames(entities)
      assert "alice" in names
      assert "bob" in names
      assert length(names) == 2
    end

    test "does not include mob names" do
      entities = make_entities()
      refute "goblin" in Entities.usernames(entities)
    end
  end
end
