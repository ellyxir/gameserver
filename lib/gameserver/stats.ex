defmodule Gameserver.Stats do
  @moduledoc """
  Combat stats shared by players and mobs.
  """

  defstruct hp: 10, max_hp: 10, attack_power: 1

  @typedoc "Combat stats for an entity"
  @type t() :: %__MODULE__{
          hp: non_neg_integer(),
          max_hp: pos_integer(),
          attack_power: non_neg_integer()
        }

  @doc """
  Creates a new stats struct with default values.

  Accepts optional keyword overrides for `:hp`, `:max_hp`, and `:attack_power`.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct!(__MODULE__, opts)
  end
end
