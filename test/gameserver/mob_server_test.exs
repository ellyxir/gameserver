defmodule Gameserver.MobServerTest do
  # async: false because we interact with WorldServer
  use ExUnit.Case, async: false

  alias Gameserver.EntityServer
  alias Gameserver.Map, as: GameMap
  alias Gameserver.MobServer
  alias Gameserver.WorldServer

  setup do
    entity_server = start_supervised!({EntityServer, name: nil})

    server =
      start_supervised!(
        {WorldServer, name: :"world_#{System.unique_integer()}", entity_server: entity_server},
        id: :world_server
      )

    %{server: server}
  end

  describe "start_link/1" do
    test "spawns mobs into the world", %{server: server} do
      start_supervised!({MobServer, world_server: server})

      mobs = WorldServer.mobs(server)
      assert length(mobs) == 3

      names = mobs |> Enum.map(fn {entity, _pos} -> entity.name end) |> Enum.sort()
      assert names == ["goblin", "rat", "spider"]
    end

    test "places mobs on floor tiles", %{server: server} do
      start_supervised!({MobServer, world_server: server})

      map = WorldServer.get_map(server)
      mobs = WorldServer.mobs(server)

      Enum.each(mobs, fn {entity, pos} ->
        assert {:ok, :floor} == GameMap.get_tile(map, pos),
               "expected #{entity.name} at #{inspect(pos)} to be on a floor tile"
      end)
    end

    test "mobs are visible to players who join after", %{server: server} do
      start_supervised!({MobServer, world_server: server})

      {:ok, user} = Gameserver.User.new("hero")
      {:ok, _pos} = WorldServer.join_user(user, server)

      mobs = WorldServer.mobs(server)
      assert length(mobs) == 3
    end
  end
end
