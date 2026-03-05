defmodule Gameserver.WorldServerTest do
  use ExUnit.Case, async: false

  alias Gameserver.WorldServer

  describe "genserver lifecycle" do
    test "is started and registered by application" do
      assert Process.whereis(WorldServer) != nil
    end
  end
end
