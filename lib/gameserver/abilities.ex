defmodule Gameserver.Abilities do
  @moduledoc """
  Ability catalog. Looks up ability definitions by id.
  """

  alias Gameserver.Ability
  alias Gameserver.Effects.DirectDmg

  @doc "Returns the ability with the given id, or `{:error, :not_found}`."
  @spec get(atom()) :: {:ok, Ability.t()} | {:error, :not_found}
  def get(:melee_strike) do
    {:ok,
     %Ability{
       id: :melee_strike,
       name: "Melee Strike",
       tags: [:physical, :melee],
       range: 1,
       cooldown_ms: 1000,
       effects: [{DirectDmg, %{base: 10}}]
     }}
  end

  def get(:upper_cut) do
    {:ok,
     %Ability{
       id: :upper_cut,
       name: "Upper Cut",
       tags: [:physical, :melee],
       range: 1,
       cooldown_ms: 1500,
       effects: [{DirectDmg, %{base: 18}}]
     }}
  end

  def get(_id), do: {:error, :not_found}
end
