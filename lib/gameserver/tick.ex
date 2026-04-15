defmodule Gameserver.Tick do
  @moduledoc """
  A self-contained unit of periodic work attached to an entity.

  Ticks drive persistent effects like damage over time and temporary buffs.
  Each tick self-schedules via `Process.send_after` in whatever process owns
  the entity — there is no central tick loop.

  The `source_id` is the entity that created the tick.

  The `transform` function runs each tick interval and signals whether to
  continue or self-remove. The `on_kill` function runs cleanup when the
  tick is removed for any reason (stop signal, expiry, or external removal).

  A tick ends when either `transform` returns `:stop` or `kill_after_ms`
  elapses, whichever comes first. Both paths run `on_kill` exactly once.
  """

  alias Gameserver.Entity
  alias Gameserver.UUID

  @typedoc """
  Transform function that runs each tick.
  Returns the updated entity and a signal: `:continue` to keep ticking
  or `:stop` to self-remove (which also triggers `on_kill`).
  """
  @type transform() :: (Entity.t() -> {Entity.t(), :continue | :stop})

  @typedoc """
  Cleanup function that runs when the tick is removed for any reason.
  """
  @type on_kill() :: (Entity.t() -> Entity.t())

  @enforce_keys [:id, :source_id, :transform, :repeat_ms]
  defstruct [:id, :source_id, :transform, :on_kill, :repeat_ms, :kill_after_ms]

  @typedoc "A periodic tick attached to an entity"
  @type t() :: %__MODULE__{
          id: UUID.t(),
          source_id: UUID.t(),
          transform: transform(),
          on_kill: on_kill(),
          repeat_ms: pos_integer(),
          kill_after_ms: pos_integer() | nil
        }

  @typep option() ::
           {:source_id, UUID.t()}
           | {:transform, transform()}
           | {:on_kill, on_kill()}
           | {:repeat_ms, pos_integer()}
           | {:kill_after_ms, pos_integer() | nil}

  @typep options() :: [option()]

  @doc """
  Creates a new tick with a generated UUID.

  Required options: `:source_id`, `:transform`, `:repeat_ms`.
  Optional: `:on_kill` (defaults to identity), `:kill_after_ms` (defaults to nil).
  """
  @spec new(options()) :: t()
  def new(opts) do
    opts =
      opts
      |> Keyword.put(:id, UUID.generate())
      |> Keyword.put_new(:on_kill, &Function.identity/1)
      |> Keyword.put_new(:kill_after_ms, nil)

    struct!(__MODULE__, opts)
  end
end
