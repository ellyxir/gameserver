defmodule Mix.Tasks.Bench.RenderTime do
  @moduledoc """
  Measures server-side LiveView render duration at configurable map sizes.

  Attaches a telemetry handler to `[:phoenix, :live_view, :render, :stop]`,
  uses the existing Playwright benchmark script to drive player movement,
  and reports render timing statistics.

  ## Usage

      mix bench.render_time [--width 30] [--height 30] [--moves 30]
  """

  use Mix.Task

  @shortdoc "Measure server-side LiveView render time at various map sizes"

  @doc "Runs the benchmark. Accepts `--width`, `--height`, and `--moves` CLI flags."
  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {width, height, moves} = parse_args(args)

    Application.put_env(:gameserver, :map_width, width)
    Application.put_env(:gameserver, :map_height, height)

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

    table = :ets.new(:render_durations, [:bag, :public])

    :telemetry.attach(
      "bench-render-time",
      [:phoenix, :live_view, :render, :stop],
      &__MODULE__.handle_telemetry/4,
      table
    )

    port = port()
    await_ready(port)

    script = Path.join([File.cwd!(), "bench", "liveview_diffs.mjs"])

    unless File.exists?(script) do
      Mix.raise("missing #{script}")
    end

    Mix.shell().info("benchmarking render time on #{width}x#{height} map (#{moves} moves)...")

    node_args = [script, "--port", to_string(port), "--moves", to_string(moves)]

    case System.cmd("node", node_args, stderr_to_stdout: true) do
      {_output, 0} ->
        print_results(table, width, height, moves)

      {output, code} ->
        Mix.shell().error("benchmark failed (exit #{code}):\n#{output}")
    end

    :telemetry.detach("bench-render-time")
    :ets.delete(table)

    :ok
  end

  @doc "Telemetry handler that records render duration in the given ETS table."
  @spec handle_telemetry([atom()], map(), map(), :ets.table()) :: true
  def handle_telemetry(_event, measurements, _metadata, table) do
    duration_us = System.convert_time_unit(measurements.duration, :native, :microsecond)
    :ets.insert(table, {:duration, duration_us})
  end

  @spec parse_args([String.t()]) :: {pos_integer(), pos_integer(), pos_integer()}
  defp parse_args(args) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [width: :integer, height: :integer, moves: :integer])

    width = Keyword.get(opts, :width, 30)
    height = Keyword.get(opts, :height, 30)
    moves = Keyword.get(opts, :moves, 30)
    {width, height, moves}
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

  @spec print_results(:ets.table(), pos_integer(), pos_integer(), pos_integer()) :: :ok
  defp print_results(table, width, height, moves) do
    durations =
      table
      |> :ets.match({:duration, :"$1"})
      |> List.flatten()
      |> Enum.sort()

    if durations == [] do
      Mix.shell().info("no render events captured")
    else
      count = length(durations)
      sum = Enum.sum(durations)
      avg = div(sum, count)
      min = List.first(durations)
      max = List.last(durations)
      p50 = percentile(durations, 50)
      p95 = percentile(durations, 95)
      p99 = percentile(durations, 99)

      Mix.shell().info("""

      -- liveview render time benchmark --

      map:      #{width}x#{height} (#{width * height} tiles)
      moves:    #{moves}
      renders:  #{count}

      min:      #{format_us(min)}
      avg:      #{format_us(avg)}
      p50:      #{format_us(p50)}
      p95:      #{format_us(p95)}
      p99:      #{format_us(p99)}
      max:      #{format_us(max)}
      total:    #{format_us(sum)}
      """)
    end
  end

  @spec percentile([non_neg_integer()], number()) :: non_neg_integer()
  defp percentile(sorted, p) do
    index = max(0, ceil(length(sorted) * p / 100) - 1)
    Enum.at(sorted, index)
  end

  @spec format_us(non_neg_integer()) :: String.t()
  defp format_us(us) when us >= 1000, do: "#{Float.round(us / 1000, 2)} ms"
  defp format_us(us), do: "#{us} µs"
end
