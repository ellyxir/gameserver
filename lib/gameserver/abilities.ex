defmodule Gameserver.Abilities do
  @moduledoc """
  Ability catalog. Looks up ability definitions by id.
  """

  alias Gameserver.Ability
  alias Gameserver.Effects.DirectDmg
  alias Gameserver.Effects.DoT
  alias Gameserver.Effects.Heal
  alias Gameserver.Effects.StatBuff

  @player_abilities [:melee_strike, :poison_strike, :upper_cut, :battle_shout, :heal, :fortify]

  @doc "Returns the default ability list for player entities."
  @spec player_abilities() :: [atom()]
  def player_abilities, do: @player_abilities

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

  def get(:poison_strike) do
    {:ok,
     %Ability{
       id: :poison_strike,
       name: "Poison Strike",
       tags: [:physical, :melee, :dot],
       range: 1,
       cooldown_ms: 1000,
       effects: [
         {DoT, %{base: 1, repeat_ms: 2000, kill_after_ms: 10_000}},
         {DirectDmg, %{base: 1}}
       ]
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
       effects: [{StatBuff, %{stat: :str, amount: 3}}]
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
       effects: [{StatBuff, %{stat: :con, amount: 2}}]
     }}
  end

  def get(:heal) do
    {:ok,
     %Ability{
       id: :heal,
       name: "Heal",
       tags: [:magic, :divine],
       range: 3,
       cooldown_ms: 5000,
       effects: [{Heal, %{base: 5}}]
     }}
  end

  def get(_id), do: {:error, :not_found}
end
