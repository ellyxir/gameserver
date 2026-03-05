defmodule Gameserver.User do
  @moduledoc """
  User is used for referencing the user account and is not the `Player` object (not implemented yet).
  """

  import Ecto.Changeset

  defstruct [:id, :username]

  @types %{username: :string}

  @typedoc """
  User type
  id is a UUID that we use to communicate with other game genservers
  username is the account name, which we use also as the player name for now
  """
  @type t() :: %__MODULE__{
          id: Ecto.UUID.t(),
          username: String.t()
        }

  @type user_error() :: :too_long | :too_short | :required | :invalid_format

  @doc """
  create a new user
  """
  @spec new(String.t()) :: {:ok, t()} | {:error, user_error()}
  def new(username) when is_binary(username) do
    changeset = changeset(%{username: username})

    case apply_action(changeset, :insert) do
      {:ok, data} ->
        {:ok, %__MODULE__{id: Ecto.UUID.generate(), username: data.username}}

      {:error, changeset} ->
        {:error, error_reason(changeset)}
    end
  end

  @doc """
  validates the username
  returns a changeset that LiveView can use
  """
  @spec validate_username(String.t()) :: Ecto.Changeset.t()
  def validate_username(username) do
    %{username: username}
    |> changeset()
    |> Map.put(:action, :validate)
  end

  # return changeset for username
  @spec changeset(map()) :: Ecto.Changeset.t()
  defp changeset(params) when is_map(params) do
    {%{}, @types}
    |> cast(params, [:username])
    |> validate_required([:username])
    |> validate_length(:username, min: 3, max: 20)
    |> validate_format(:username, ~r/^[a-zA-Z0-9_-]+$/,
      message: "must contain only readable characters"
    )
  end

  @spec error_reason(Ecto.Changeset.t()) :: user_error()
  defp error_reason(changeset) do
    {_, opts} = changeset.errors[:username]

    case {Keyword.get(opts, :validation), Keyword.get(opts, :kind)} do
      {:length, :max} -> :too_long
      {:length, :min} -> :too_short
      {:required, _} -> :required
      {:format, _} -> :invalid_format
      other -> raise "Unexpected validation error: #{inspect(other)}"
    end
  end
end
