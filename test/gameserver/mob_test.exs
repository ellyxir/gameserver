defmodule Gameserver.MobTest do
  use ExUnit.Case, async: true

  alias Gameserver.EntityServer
  alias Gameserver.Mob
  alias Gameserver.UUID
  alias Gameserver.WorldServer

  setup do
    entity_server = start_supervised!({EntityServer, name: nil}, id: :entity_server)

    world_server =
      start_supervised!(
        {WorldServer, name: nil, entity_server: entity_server},
        id: :world_server
      )

    {:ok, entity_server: entity_server, world_server: world_server}
  end

  describe "init/1" do
    test "creates entity and joins the world", ctx do
      id = UUID.generate()

      mob = %Mob{
        id: id,
        name: "goblin",
        spawn_pos: {12, 3},
        world_server: ctx.world_server
      }

      {:ok, pid} = Mob.start_link(mob)

      # join_world is deferred, wait for it
      _ = :sys.get_state(pid)

      {:ok, pos} = WorldServer.get_position(id, ctx.world_server)
      assert pos == {12, 3}
    end
  end
end
