defmodule Gameserver.Effects.HealTest do
  use ExUnit.Case, async: true

  alias Gameserver.Effects.Heal
  alias Gameserver.Entity
  alias Gameserver.Stat
  alias Gameserver.Stats

  defp make_entity(opts \\ []) do
    stats = Stats.new(Keyword.get(opts, :stats, []))
    Entity.new(name: "test", type: :mob, pos: {0, 0}, stats: stats)
  end

  describe "valid?/3" do
    test "returns true when target is alive" do
      source = make_entity()
      target = make_entity()
      assert Heal.valid?(%{base: 10}, source, target)
    end

    test "returns false when target is dead" do
      source = make_entity()
      target = make_entity(stats: [dead: true])
      refute Heal.valid?(%{base: 10}, source, target)
    end

    test "heals can only heal same type of mob" do
      mob1 = make_entity()
      mob2 = make_entity()
      player1 = %{make_entity() | type: :player}
      player2 = %{make_entity() | type: :player}

      assert Heal.valid?(%{base: 10}, mob1, mob2)
      assert Heal.valid?(%{base: 10}, player1, player2)
      refute Heal.valid?(%{base: 10}, mob1, player2)
      refute Heal.valid?(%{base: 10}, player1, mob2)
    end
  end

  describe "apply/3" do
    test "actually heals" do
      source = make_entity()
      target = make_entity()
      hp_before = Stat.effective(target.stats.hp, target.stats)
      heal_power = 5
      transform = Heal.apply(%{base: heal_power}, source, target)
      updated = transform.(target)
      hp_after = Stat.effective(updated.stats.hp, updated.stats)
      assert hp_after == hp_before + heal_power
    end

    test "doesn't overheal" do
      source = make_entity()
      target = make_entity()
      max_hp = Stat.effective(target.stats.max_hp, target.stats)
      heal_power = max_hp + 1
      transform = Heal.apply(%{base: heal_power}, source, target)
      updated = transform.(target)
      # don't use Stat.effective/2 because it clamps on read
      hp_after = updated.stats.hp.base_stat.base
      assert hp_after == max_hp
    end
  end
end
