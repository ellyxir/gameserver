defmodule Gameserver.EntityServerTest do
  use ExUnit.Case, async: true

  alias Gameserver.Entity
  alias Gameserver.EntityServer
  alias Gameserver.UUID

  setup do
    server = start_supervised!({EntityServer, name: nil})
    %{server: server}
  end

  defp create_entity!(server, opts \\ []) do
    opts = Keyword.put_new(opts, :name, "goblin")
    opts = Keyword.put_new(opts, :type, :mob)
    opts = Keyword.put_new(opts, :pos, {3, 3})
    entity = Entity.new(opts)
    :ok = EntityServer.create_entity(entity, server)
    entity
  end

  describe "create_entity/2" do
    test "stores an entity and returns :ok", %{server: server} do
      entity = Entity.new(name: "goblin", type: :mob, pos: {3, 3})

      assert :ok = EntityServer.create_entity(entity, server)
    end

    test "returns error when entity already exists", %{server: server} do
      entity = Entity.new(name: "goblin", type: :mob, pos: {3, 3})

      assert :ok = EntityServer.create_entity(entity, server)
      assert {:error, :already_exists} = EntityServer.create_entity(entity, server)
    end
  end

  describe "get_entity/2" do
    test "returns entity by id", %{server: server} do
      entity = create_entity!(server)

      assert {:ok, ^entity} = EntityServer.get_entity(entity.id, server)
    end

    test "returns error for unknown id", %{server: server} do
      assert {:error, :not_found} = EntityServer.get_entity(UUID.generate(), server)
    end
  end

  describe "remove_entity/2" do
    test "removes an existing entity", %{server: server} do
      entity = create_entity!(server)

      assert :ok = EntityServer.remove_entity(entity.id, server)
      assert {:error, :not_found} = EntityServer.get_entity(entity.id, server)
    end

    test "returns error for unknown id", %{server: server} do
      assert {:error, :not_found} = EntityServer.remove_entity(UUID.generate(), server)
    end
  end

  describe "update_entity/3" do
    test "applies update function and returns updated entity", %{server: server} do
      entity = create_entity!(server, pos: {3, 3})

      assert {:ok, updated} =
               EntityServer.update_entity(entity.id, &%{&1 | pos: {4, 3}}, server)

      assert updated.pos == {4, 3}
      assert {:ok, ^updated} = EntityServer.get_entity(entity.id, server)
    end

    test "returns error for unknown id", %{server: server} do
      assert {:error, :not_found} =
               EntityServer.update_entity(UUID.generate(), &%{&1 | pos: {0, 0}}, server)
    end

    test "returns error and preserves state when update function raises", %{server: server} do
      entity = create_entity!(server, pos: {3, 3})

      assert {:error, {:update_failed, _reason}} =
               EntityServer.update_entity(entity.id, fn _e -> raise "boom" end, server)

      assert {:ok, ^entity} = EntityServer.get_entity(entity.id, server)
    end
  end

  describe "list_entities/1" do
    test "returns all entities", %{server: server} do
      goblin = create_entity!(server, name: "goblin")
      rat = create_entity!(server, name: "rat", pos: {5, 5})

      entities = EntityServer.list_entities(server)
      assert length(entities) == 2
      assert goblin in entities
      assert rat in entities
    end

    test "returns empty list when no entities", %{server: server} do
      assert [] = EntityServer.list_entities(server)
    end
  end

  describe "pubsub broadcasts" do
    setup %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, EntityServer.entity_topic())
      %{server: server}
    end

    test "broadcasts on create_entity", %{server: server} do
      entity = Entity.new(name: "goblin", type: :mob, pos: {3, 3})
      :ok = EntityServer.create_entity(entity, server)

      assert_receive {:entity_created, ^entity}
    end

    test "does not broadcast on duplicate create", %{server: server} do
      entity = create_entity!(server)
      assert_receive {:entity_created, ^entity}

      {:error, :already_exists} = EntityServer.create_entity(entity, server)
      refute_receive {:entity_created, ^entity}
    end

    test "broadcasts on remove_entity", %{server: server} do
      entity = create_entity!(server)
      assert_receive {:entity_created, _}

      :ok = EntityServer.remove_entity(entity.id, server)
      assert_receive {:entity_removed, id} when id == entity.id
    end

    test "does not broadcast on failed remove", %{server: server} do
      fake_id = UUID.generate()
      {:error, :not_found} = EntityServer.remove_entity(fake_id, server)
      refute_receive {:entity_removed, ^fake_id}
    end

    test "broadcasts on update_entity", %{server: server} do
      entity = create_entity!(server, pos: {3, 3})
      assert_receive {:entity_created, _}

      {:ok, updated} = EntityServer.update_entity(entity.id, &%{&1 | pos: {4, 3}}, server)
      assert_receive {:entity_updated, ^updated}
    end

    test "does not broadcast on failed update", %{server: server} do
      fake_id = UUID.generate()

      {:error, :not_found} =
        EntityServer.update_entity(fake_id, &%{&1 | pos: {0, 0}}, server)

      refute_receive {:entity_updated, %{id: ^fake_id}}
    end
  end
end
