defmodule Gameserver.CombatEvent do
  @moduledoc """
  CombatEvent for PubSub
  Enforces keys, compile time checking
  """

  alias Gameserver.UUID

  @enforce_keys [:attacker_id, :defender_id, :damage, :defender_hp]
  defstruct [:attacker_id, :defender_id, :damage, :defender_hp, dead: false]

  @typedoc """
  A broadcast combat event with attacker/defender IDs and damage dealt
  """
  @type t() :: %__MODULE__{
          attacker_id: UUID.t(),
          defender_id: UUID.t(),
          damage: non_neg_integer(),
          defender_hp: non_neg_integer(),
          dead: boolean()
        }
end
