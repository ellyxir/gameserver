defmodule Mix.Tasks.Bench.DiffSize do
  @moduledoc """
  Measures LiveView WebSocket diff sizes during gameplay.

  Starts the Phoenix endpoint, launches a Playwright browser that joins
  the game, hooks the LiveView WebSocket, performs moves, and reports
  frame sizes.

  ## Usage

      mix bench.diff_size [--moves 20] [--username benchplayer]
  """

  use Mix.Task

  @shortdoc "Measure LiveView diff payload sizes"

  @doc "Runs the benchmark. Accepts `--moves` and `--username` CLI flags."
  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    Application.put_env(
      :gameserver,
      GameserverWeb.Endpoint,
      Keyword.put(
        Application.get_env(:gameserver, GameserverWeb.Endpoint, []),
        :server,
        true
      )
    )

    Mix.Task.run("app.start")

    port = port()
    await_ready(port)
    script = Path.join([File.cwd!(), "bench", "liveview_diffs.mjs"])

    unless File.exists?(script) do
      Mix.raise("missing #{script}")
    end

    node_args = [script, "--port", to_string(port)] ++ args

    Mix.shell().info("running diff size benchmark against localhost:#{port}...")

    case System.cmd("node", node_args, stderr_to_stdout: true) do
      {output, 0} ->
        print_results(output)

      {output, code} ->
        Mix.shell().error("benchmark failed (exit #{code}):\n#{output}")
    end

    :ok
  end

  @spec await_ready(pos_integer()) :: :ok | no_return()
  defp await_ready(port), do: await_ready(port, 50)

  defp await_ready(_port, 0), do: Mix.raise("server did not become ready")

  defp await_ready(port, retries) do
    case :gen_tcp.connect(~c"localhost", port, [], 200) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, _} ->
        Process.sleep(100)
        await_ready(port, retries - 1)
    end
  end

  @spec port() :: pos_integer()
  defp port do
    :gameserver
    |> Application.get_env(GameserverWeb.Endpoint, [])
    |> get_in([:http, :port])
    |> case do
      port when is_integer(port) -> port
      _ -> 4000
    end
  end

  @spec print_results(String.t()) :: :ok
  defp print_results(output) do
    case Jason.decode(String.trim(output)) do
      {:ok, data} ->
        map = data["map"]
        idle = data["idle"]
        diffs = data["diffs"]
        replies = data["replies"]

        Mix.shell().info("""

        -- liveview diff size benchmark --

        map:    #{map["rows"]}x#{map["cols"]} (#{map["totalSpans"]} spans, #{map["mobs"]} mobs)
        moves:  #{data["moves"]} (made by player)

        idle traffic (#{idle["duration_s"]}s):
          messages:    #{idle["messages"]}
          bytes/sec:   #{idle["bytes_per_s"]}

        event replies:
          messages:    #{replies["count"]}
          avg size:    #{replies["avg_bytes"]} bytes

        diffs:
          messages:    #{diffs["count"]} (#{diffs["per_move"]}/move)
          min:         #{diffs["min_bytes"]} bytes
          max:         #{diffs["max_bytes"]} bytes
          avg:         #{diffs["avg_bytes"]} bytes
          total:       #{diffs["total_bytes"]} bytes
        """)

      {:error, _} ->
        Mix.shell().info(output)
    end
  end
end
