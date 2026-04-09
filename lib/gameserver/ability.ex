defmodule Gameserver.Ability do
  @moduledoc """
  An ability definition.

  Players, mobs, items, and the environment can all have abilities.
  Abilities have a list of `Effect` which actually change entities.
  """

  @enforce_keys [:id, :name, :range, :cooldown_ms]
  defstruct [:id, :name, :range, :cooldown_ms, tags: [], effects: []]

  @typep effect_entry() :: {module(), map()}

  @typedoc "An ability definition"
  @type t() :: %__MODULE__{
          id: atom(),
          name: String.t(),
          tags: [atom()],
          range: pos_integer(),
          cooldown_ms: pos_integer(),
          effects: [effect_entry()]
        }
end
