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
        {WorldServer,
         name: :"world_#{System.unique_integer()}",
         entity_server: entity_server,
         map: Gameserver.Map.sample_dungeon()},
        id: :world_server
      )

    %{server: server}
  end

  defp mob_nodes(server) do
    server
    |> WorldServer.world_nodes()
    |> Enum.filter(fn {_id, node} -> node.type == :mob end)
  end

  defp wait_for_mobs(n) do
    for _ <- 1..n do
      assert_receive {:entity_joined, _}, 1000
    end
  end

  describe "start_link/1" do
    test "spawns mobs into the world", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())
      start_supervised!({MobServer, world_server: server})
      wait_for_mobs(3)

      mobs = mob_nodes(server)
      assert length(mobs) == 3

      names = mobs |> Enum.map(fn {_id, node} -> node.name end) |> Enum.sort()
      assert names == ["goblin", "rat", "spider"]
    end

    test "places mobs on floor tiles", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())
      start_supervised!({MobServer, world_server: server})
      wait_for_mobs(3)

      map = WorldServer.get_map(server)

      Enum.each(mob_nodes(server), fn {_id, node} ->
        assert {:ok, :floor} == GameMap.get_tile(map, node.pos),
               "expected #{node.name} at #{inspect(node.pos)} to be on a floor tile"
      end)
    end

    test "mobs are visible to players who join after", %{server: server} do
      Phoenix.PubSub.subscribe(Gameserver.PubSub, WorldServer.presence_topic())
      start_supervised!({MobServer, world_server: server})
      wait_for_mobs(3)

      {:ok, user} = Gameserver.User.new("hero")
      {:ok, _pos} = WorldServer.join_user(user, server)

      assert length(mob_nodes(server)) == 3
    end
  end
end
