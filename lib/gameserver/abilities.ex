defmodule Gameserver.Abilities do
  @moduledoc """
  Ability catalog. Looks up ability definitions by id.
  """

  alias Gameserver.Ability
  alias Gameserver.Effects.DirectDmg
  alias Gameserver.Effects.StatBuff

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
       effects: [{DirectDmg, %{base: 1}}]
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
       effects: [{DirectDmg, %{base: 3}}]
     }}
  end

  def get(:battle_shout) do
    {:ok,
     %Ability{
       id: :battle_shout,
       name: "Battle Shout",
       tags: [:physical, :buff],
       range: 0,
       cooldown_ms: 5000,
       effects: [{StatBuff, %{stat: :str, amount: 3, effect_name: "Battle Shout"}}]
     }}
  end

  def get(:fortify) do
    {:ok,
     %Ability{
       id: :fortify,
       name: "Fortify",
       tags: [:physical, :buff],
       range: 0,
       cooldown_ms: 5000,
       effects: [{StatBuff, %{stat: :con, amount: 2, effect_name: "Fortify"}}]
     }}
  end

  def get(_id), do: {:error, :not_found}
end
