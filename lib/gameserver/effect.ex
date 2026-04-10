defmodule Gameserver.Effect do
  @moduledoc """
  Behaviour for effects applied by abilities.

  Each effect module implements `apply/3` and `valid?/3`.
  `apply/3` returns a transform function that mutates a target entity.
  The engine collects transforms and reduces them over the target.
  Callers must check `valid?/3` before calling `apply/3`.

  Abilities define effects as `{module, args}` tuples, e.g.
  `{Effects.DirectDmg, %{base: 10}}`. The `args` map from that tuple
  is passed as the first argument to both callbacks.
  """

  alias Gameserver.Entity
  alias Gameserver.UUID

  @enforce_keys [:id, :name]
  defstruct [:id, :name]

  @typedoc "An effect reference used in `BaseStat` to track where stat bonuses came from."
  @type t() :: %__MODULE__{
          id: UUID.t(),
          name: String.t()
        }

  @doc """
  Creates a new effect reference with a unique id.
  """
  @spec new(name :: String.t()) :: t()
  def new(name) when is_binary(name) do
    %__MODULE__{id: UUID.generate(), name: name}
  end

  @typedoc "Transform function returned by an effect that mutates a target entity."
  @type transform() :: (Entity.t() -> Entity.t())

  @doc """
  Returns true if the effect can be applied given the current source and target.
  `args` is the config map from the ability's `{module, args}` tuple.
  """
  @callback valid?(args :: map(), source :: Entity.t(), target :: Entity.t()) :: boolean()

  @doc """
  Returns a transform function that applies the effect to a target entity.
  `args` is the config map from the ability's `{module, args}` tuple.
  Assumes `valid?/3` returned true; behaviour is undefined otherwise.
  """
  @callback apply(args :: map(), source :: Entity.t(), target :: Entity.t()) :: transform()
end
