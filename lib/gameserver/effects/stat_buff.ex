defmodule Gameserver.Effects.StatBuff do
  @moduledoc """
  Permanent stat buff effect. Returns a transform that adds a bonus
  to a `BaseStat` field on the target entity. The bonus carries an
  `%Effect{}` backlink so it can be found and removed later via
  `BaseStat.remove_bonus/2`.

  Temporary buffs with expiration need the Tick system (issue #8).
  """

  @behaviour Gameserver.Effect

  alias Gameserver.Effect
  alias Gameserver.Entity

  @spec valid?(args :: map(), source :: Entity.t(), target :: Entity.t()) :: boolean()
  def valid?(_args, _source, %Entity{stats: %{dead: false}}), do: true
  def valid?(_args, _source, %Entity{stats: %{dead: true}}), do: false

  @spec apply(args :: map(), source :: Entity.t(), target :: Entity.t()) ::
          Gameserver.Effect.transform()
  def apply(%{stat: stat, amount: amount, effect_name: effect_name}, _source, _target) do
    effect_ref = %Effect{name: effect_name}

    fn %Entity{} = entity ->
      Entity.add_stat_bonus(entity, stat, amount, effect_ref)
    end
  end
end
