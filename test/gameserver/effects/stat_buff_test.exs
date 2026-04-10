defmodule Gameserver.Effects.StatBuffTest do
  use ExUnit.Case, async: true

  alias Gameserver.Effect
  alias Gameserver.Effects.StatBuff
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
      assert StatBuff.valid?(%{stat: :str, amount: 3, effect_name: "Buff"}, source, target)
    end

    test "returns false when target is dead" do
      source = make_entity()
      target = make_entity(stats: [dead: true])
      refute StatBuff.valid?(%{stat: :str, amount: 3, effect_name: "Buff"}, source, target)
    end
  end

  describe "apply/3" do
    test "returns a transform that adds the correct bonus to the stat" do
      source = make_entity()
      target = make_entity()

      transform =
        StatBuff.apply(%{stat: :str, amount: 3, effect_name: "Battle Shout"}, source, target)

      updated = transform.(target)
      assert Stat.effective(updated.stats.str, updated.stats) == 13
    end

    test "the bonus has the correct %Effect{} backlink" do
      source = make_entity()
      target = make_entity()

      transform =
        StatBuff.apply(%{stat: :str, amount: 3, effect_name: "Battle Shout"}, source, target)

      updated = transform.(target)
      [{3, %Effect{name: "Battle Shout"}}] = updated.stats.str.bonuses
    end

    test "bonus can be removed via the backlink" do
      source = make_entity()
      target = make_entity()

      transform =
        StatBuff.apply(%{stat: :str, amount: 3, effect_name: "Battle Shout"}, source, target)

      updated = transform.(target)
      [{3, effect_ref}] = updated.stats.str.bonuses
      cleaned = Entity.remove_stat_bonus(updated, :str, effect_ref)
      assert Stat.effective(cleaned.stats.str, cleaned.stats) == 10
    end

    test "multiple buffs on the same stat stack additively" do
      source = make_entity()
      target = make_entity()

      t1 = StatBuff.apply(%{stat: :str, amount: 3, effect_name: "Battle Shout"}, source, target)
      t2 = StatBuff.apply(%{stat: :str, amount: 5, effect_name: "War Cry"}, source, target)

      updated = target |> t1.() |> t2.()
      assert Stat.effective(updated.stats.str, updated.stats) == 18
    end

    test "buffs con stat" do
      source = make_entity()
      target = make_entity()

      transform =
        StatBuff.apply(%{stat: :con, amount: 2, effect_name: "Fortify"}, source, target)

      updated = transform.(target)
      assert Stat.effective(updated.stats.con, updated.stats) == 12
    end
  end
end
