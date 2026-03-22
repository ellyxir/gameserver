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
end
