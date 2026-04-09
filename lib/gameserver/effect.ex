defmodule Gameserver.Effect do
  @moduledoc """
  Placeholder for effects that can be placed on entities.
  """

  defstruct [:name]

  @typedoc "An effect that can be applied to an entity."
  @type t() :: %__MODULE__{
          name: String.t()
        }
end
