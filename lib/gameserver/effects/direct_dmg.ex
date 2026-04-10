defmodule Gameserver.Effects.DirectDmg do
  @moduledoc """
  Immediate damage effect. Calculates damage from a base value minus
  target defense (floored at zero) and returns a damage intent.
  """

  @behaviour Gameserver.Effect

  alias Gameserver.Entity
  alias Gameserver.Stats

  @spec valid?(args :: map(), source :: Entity.t(), target :: Entity.t()) :: boolean()
  def valid?(_args, _source, %Entity{stats: %{dead: false}}), do: true
  def valid?(_args, _source, %Entity{stats: %{dead: true}}), do: false

  @spec apply(args :: map(), source :: Entity.t(), target :: Entity.t()) ::
          Gameserver.Effect.intent()
  def apply(%{base: base}, _source, %Entity{stats: %Stats{defense: defense}}) do
    {:damage, calculate_damage(base, defense)}
  end

  @spec calculate_damage(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  defp calculate_damage(base, defense) do
    max(base - defense, 0)
  end
end
