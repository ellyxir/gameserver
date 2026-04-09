defmodule Gameserver.Effects.DirectDmg do
  @moduledoc """
  Immediate damage effect. Calculates damage from a base value minus
  target defense (floored at zero) and returns a damage intent.
  """

  @behaviour Gameserver.Effect

  alias Gameserver.Entity
  alias Gameserver.Stats

  @spec valid?(map(), Entity.t(), Entity.t()) :: boolean()
  def valid?(_args, _source, %Entity{stats: stats}) do
    not stats.dead
  end

  @spec apply(map(), Entity.t(), Entity.t()) :: Gameserver.Effect.result()
  def apply(%{base: base}, _source, %Entity{stats: %Stats{defense: defense}}) do
    damage = calculate_damage(base, defense)
    {:ok, {:damage, damage}}
  end

  @spec calculate_damage(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  defp calculate_damage(base, defense) do
    max(base - defense, 0)
  end
end
