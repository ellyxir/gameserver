defmodule Gameserver.CooldownsTest do
  use ExUnit.Case, async: true

  alias Gameserver.Cooldowns

  describe "new/0" do
    test "creates empty cooldown tracker" do
      assert %Cooldowns{} = Cooldowns.new()
    end
  end

  describe "ready?/2" do
    test "returns true when no cooldown has been started" do
      cd = Cooldowns.new()
      assert Cooldowns.ready?(cd, :move)
    end

    test "returns false while cooldown is active" do
      cd = Cooldowns.new() |> Cooldowns.start(:move, 500)
      refute Cooldowns.ready?(cd, :move)
    end

    test "returns true after cooldown has elapsed" do
      cd = Cooldowns.new() |> Cooldowns.start(:move, 1)
      Process.sleep(2)
      assert Cooldowns.ready?(cd, :move)
    end

    test "restarting a cooldown resets the timer" do
      cd = Cooldowns.new() |> Cooldowns.start(:move, 1)
      Process.sleep(2)
      assert Cooldowns.ready?(cd, :move)

      cd = Cooldowns.start(cd, :move, 500)
      refute Cooldowns.ready?(cd, :move)
    end

    test "different cooldowns are independent" do
      cd = Cooldowns.new() |> Cooldowns.start(:move, 500)
      refute Cooldowns.ready?(cd, :move)
      assert Cooldowns.ready?(cd, :attack)
    end
  end

  describe "check/2" do
    test "returns :ok when ready" do
      cd = Cooldowns.new()
      assert :ok = Cooldowns.check(cd, :move)
    end

    test "returns {:error, :cooldown} when active" do
      cd = Cooldowns.new() |> Cooldowns.start(:move, 500)
      assert {:error, :cooldown} = Cooldowns.check(cd, :move)
    end
  end
end
