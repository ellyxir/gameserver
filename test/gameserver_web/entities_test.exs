defmodule GameserverWeb.EntitiesTest do
  use ExUnit.Case, async: true

  alias Gameserver.Entity
  alias GameserverWeb.Entities

  defp make_entities do
    nodes = %{
      "id-a" => %{name: "alice", pos: {1, 1}, type: :user},
      "id-b" => %{name: "bob", pos: {2, 1}, type: :user},
      "id-g" => %{name: "goblin", pos: {3, 2}, type: :mob}
    }

    Entities.add_world_nodes(%Entities{}, nodes)
  end

  describe "add_world_nodes/2" do
    test "adds entities from WorldServer.world_nodes() format" do
      nodes = %{
        "id-a" => %{name: "alice", pos: {1, 1}, type: :user},
        "id-m" => %{name: "goblin", pos: {5, 5}, type: :mob}
      }

      entities = Entities.add_world_nodes(%Entities{}, nodes)

      assert Entities.has_entity?(entities, "id-a")
      assert Entities.get_position(entities, "id-a") == {:ok, {1, 1}}
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
      assert Entities.get_position(%Entities{}, "nope") == {:error, :not_found}
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

  describe "get_name/2" do
    test "returns name for known entity" do
      entities = make_entities()
      assert Entities.get_name(entities, "id-a") == {:ok, "alice"}
      assert Entities.get_name(entities, "id-g") == {:ok, "goblin"}
    end

    test "returns :error for unknown id" do
      assert Entities.get_name(%Entities{}, "nope") == {:error, :not_found}
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
