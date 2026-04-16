defmodule Gameserver.Ability do
  @moduledoc """
  An ability definition.

  Players, mobs, items, and the environment can all have abilities.
  Abilities have a list of `Effect` which actually change entities.
  """

  @enforce_keys [:id, :name, :range, :cooldown_ms]
  defstruct [:id, :name, :range, :cooldown_ms, tags: [], effects: []]

  @typep effect_entry() :: {module(), map()}

  @type tag() ::
          :physical | :melee | :buff | :debuff | :fire | :magic | :dot | :item | :consumable

  @typedoc "An ability definition"
  @type t() :: %__MODULE__{
          id: atom(),
          name: String.t(),
          tags: [tag()],
          range: non_neg_integer(),
          cooldown_ms: pos_integer(),
          effects: [effect_entry()]
        }
end
