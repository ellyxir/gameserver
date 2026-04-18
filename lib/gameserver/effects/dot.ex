defmodule Gameserver.Effects.DoT do
  @moduledoc """
  Damage over time effect. Returns a transform that registers a `Tick`
  on the target entity. The tick's transform applies periodic damage
  via `HpStat.apply_damage/2`.

  Damage is applied raw — no defense reduction. Combat formula
  integration is a future issue.

  Args: `:base` (damage per tick), `:repeat_ms` (tick interval),
  `:kill_after_ms` (total duration, nil for permanent).
  The source entity's id is captured as the tick's `source_id`.
  """

  @behaviour Gameserver.Effect

  alias Gameserver.Entity
  alias Gameserver.HpStat
  alias Gameserver.Tick

  @spec valid?(args :: map(), source :: Entity.t(), target :: Entity.t()) :: boolean()
  def valid?(_args, %Entity{id: id}, %Entity{id: id}), do: false
  def valid?(_args, _source, %Entity{stats: %{dead: false}}), do: true
  def valid?(_args, _source, %Entity{stats: %{dead: true}}), do: false

  @spec apply(args :: map(), source :: Entity.t(), target :: Entity.t()) ::
          Gameserver.Effect.transform()
  def apply(%{base: base, repeat_ms: repeat_ms} = args, %Entity{id: source_id}, _target) do
    tick =
      Tick.new(
        transform: fn entity ->
          hp = HpStat.apply_damage(entity.stats.hp, base)
          {%{entity | stats: %{entity.stats | hp: hp}}, :continue}
        end,
        source_id: source_id,
        repeat_ms: repeat_ms,
        kill_after_ms: Map.get(args, :kill_after_ms)
      )

    fn %Entity{} = entity ->
      Entity.register_tick(entity, tick)
    end
  end
end
