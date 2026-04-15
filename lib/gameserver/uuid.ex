defmodule Gameserver.UUID do
  @moduledoc """
  Local UUID type and generation, wrapping `Ecto.UUID` to decouple
  domain code from the Ecto dependency.
  """

  @typedoc "A UUID string in the standard 8-4-4-4-12 hex format"
  @type t() :: String.t()

  @doc """
  Generates a new random UUID (v4).
  """
  @spec generate() :: t()
  def generate, do: Ecto.UUID.generate()

  defguard is_uuid(uuid) when is_binary(uuid)
end
