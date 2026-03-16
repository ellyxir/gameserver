defmodule Gameserver.UUIDTest do
  use ExUnit.Case, async: true

  alias Gameserver.UUID

  describe "generate/0" do
    test "returns a valid v4 uuid string" do
      uuid = UUID.generate()

      assert Regex.match?(
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
               uuid
             )
    end

    test "returns unique values" do
      a = UUID.generate()
      b = UUID.generate()
      assert a != b
    end
  end
end
