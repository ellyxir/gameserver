defmodule Mix.Tasks.Check do
  @moduledoc """
  Runs format, compile, test, dialyzer, and credo
  """
  use Mix.Task

  @shortdoc "Run all checks"

  @impl Mix.Task
  def run(_args) do
    commands = [
      {"format --check-formatted", "Checking formatting..."},
      {"compile --warnings-as-errors", "Compiling..."},
      {"test", "Running tests..."},
      {"dialyzer", "Running dialyzer..."},
      {"credo --strict", "Running credo..."}
    ]

    Enum.each(commands, fn {cmd, msg} ->
      Mix.shell().info(msg)

      case Mix.shell().cmd("mix #{cmd}") do
        0 -> :ok
        _ -> Mix.raise("Failed: mix #{cmd}")
      end
    end)

    Mix.shell().info("All checks passed!")
  end
end
