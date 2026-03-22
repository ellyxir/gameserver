defmodule Gameserver.EntityServerTest do
  use ExUnit.Case, async: true

  alias Gameserver.Entity
  alias Gameserver.EntityServer

  setup do
    server = start_supervised!({EntityServer, name: nil})
    %{server: server}
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
end
