defmodule Gameserver.Effect do
  @moduledoc """
  Behaviour for effects applied by abilities.

  Each effect module implements `apply/3` and `valid?/3`.
  Effects return intent describing what they want to happen.
  Caller handles the bookkeeping (adding effect to an entity for example)
  Callers must check `valid?/3` before calling `apply/3`.

  Abilities define effects as `{module, args}` tuples, e.g.
  `{Effects.DirectDmg, %{base: 10}}`. The `args` map from that tuple
  is passed as the first argument to both callbacks.
  """

  alias Gameserver.Entity

  @enforce_keys [:name]
  defstruct [:name]

  @typedoc "A named effect reference used in `BaseStat` module to track where stat bonuses came from."
  @type t() :: %__MODULE__{
          name: String.t()
        }

  @typedoc "Intent returned by an effect describing what should happen."
  # there will be other intents such as DoTs
  @type intent() :: {:damage, damage :: non_neg_integer()}

  @typedoc "Result of applying an effect."
  @type result() :: {:ok, intent()}

  @doc """
  Returns true if the effect can be applied given the current source and target.
  `args` is the config map from the ability's `{module, args}` tuple.
  """
  @callback valid?(args :: map(), source :: Entity.t(), target :: Entity.t()) :: boolean()

  @doc """
  Applies the effect and returns intent describing what should happen.
  `args` is the config map from the ability's `{module, args}` tuple.
  Assumes `valid?/3` returned true; behaviour is undefined otherwise.
  """
  @callback apply(args :: map(), source :: Entity.t(), target :: Entity.t()) :: result()
end
