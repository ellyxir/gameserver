defmodule Mix.Tasks.Bench.Load do
  @moduledoc """
  Simulates N players connecting over WebSocket and moving around the map.

  Measures server-side BEAM metrics and client-side response latency
  to see how the system holds up under concurrent load.

  ## Usage

      mix bench.load [--players 100] [--move-interval 150] [--duration 60] [--ramp-rate 10]

  ## Options

  - `--players` - number of simulated players (default 100)
  - `--move-interval` - ms between moves per player (default: server move cooldown)
  - `--duration` - test duration in seconds (default 60)
  - `--ramp-rate` - players to connect per second during ramp-up (default 10)
  """

  use Mix.Task

  alias Gameserver.Bench.Metrics
  alias Gameserver.Bench.SimPlayer

  @shortdoc "Load test with N simulated WebSocket players"

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {players, move_interval, duration, ramp_rate} = parse_args(args)

    enable_server()
    Mix.Task.run("app.start")

    port = port()
    await_ready!(port)

    table = Metrics.new()

    :telemetry.attach(
      "bench-load-render",
      [:phoenix, :live_view, :render, :stop],
      &handle_render_telemetry/4,
      table
    )

    Mix.shell().info(
      "load test: #{players} players, #{move_interval}ms moves, #{duration}s duration"
    )

    player_pids = spawn_players(players, port, move_interval, ramp_rate)
    joined_count = await_joins(player_pids, players)

    Mix.shell().info("#{joined_count}/#{players} players connected")

    sample_beam_metrics(table, duration)

    Mix.shell().info("stopping players...")
    stop_players(player_pids)

    :telemetry.detach("bench-load-render")

    print_report(table, players, move_interval, duration)

    Metrics.delete(table)

    :ok
  end

  @doc false
  @spec handle_render_telemetry([atom()], map(), map(), Metrics.table()) :: true
  def handle_render_telemetry(_event, measurements, _metadata, table) do
    duration_us = System.convert_time_unit(measurements.duration, :native, :microsecond)
    Metrics.record_render(table, duration_us)
  end

  @spec parse_args([String.t()]) ::
          {players :: pos_integer(), move_interval :: pos_integer(), duration :: pos_integer(),
           ramp_rate :: pos_integer()}
  defp parse_args(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          players: :integer,
          move_interval: :integer,
          duration: :integer,
          ramp_rate: :integer
        ]
      )

    players = Keyword.get(opts, :players, 100)
    move_interval = Keyword.get(opts, :move_interval, Gameserver.WorldServer.move_cooldown_ms())
    duration = Keyword.get(opts, :duration, 60)
    ramp_rate = Keyword.get(opts, :ramp_rate, 10)

    {players, move_interval, duration, ramp_rate}
  end

  @spec enable_server() :: :ok
  defp enable_server do
    Application.put_env(
      :gameserver,
      GameserverWeb.Endpoint,
      Keyword.put(
        Application.get_env(:gameserver, GameserverWeb.Endpoint, []),
        :server,
        true
      )
    )
  end

  @spec spawn_players(
          players :: pos_integer(),
          port :: pos_integer(),
          move_interval :: pos_integer(),
          ramp_rate :: pos_integer()
        ) :: [pid()]
  defp spawn_players(players, port, move_interval, ramp_rate) do
    delay_ms = div(1000, ramp_rate)

    1..players
    |> Enum.reduce([], fn i, pids ->
      if i > 1, do: Process.sleep(delay_ms)

      case start_player(i, port, move_interval) do
        {:ok, pid} ->
          [pid | pids]

        {:error, reason} ->
          Mix.shell().error("player #{i} failed to start: #{inspect(reason)}")
          pids
      end
    end)
    |> Enum.reverse()
  end

  @spec start_player(
          index :: pos_integer(),
          port :: pos_integer(),
          move_interval :: pos_integer()
        ) ::
          {:ok, pid()} | {:error, term()}
  defp start_player(index, port, move_interval) do
    SimPlayer.start_link(index, port: port, move_interval_ms: move_interval, caller: self())
  end

  @spec await_joins(player_pids :: [pid()], expected :: pos_integer()) :: non_neg_integer()
  defp await_joins(_player_pids, expected) do
    deadline = System.monotonic_time(:millisecond) + expected * 500 + 5000

    Enum.reduce_while(1..expected, 0, fn _, count ->
      remaining = deadline - System.monotonic_time(:millisecond)

      if remaining <= 0 do
        Mix.shell().error("timed out waiting for joins (#{count}/#{expected})")
        {:halt, count}
      else
        receive do
          {:sim_player_joined, _user_id} ->
            {:cont, count + 1}
        after
          remaining ->
            Mix.shell().error("timed out waiting for joins (#{count}/#{expected})")
            {:halt, count}
        end
      end
    end)
  end

  @spec sample_beam_metrics(Metrics.table(), duration_s :: pos_integer()) :: non_neg_integer()
  defp sample_beam_metrics(table, duration_s) do
    sample_count = duration_s

    Enum.each(1..sample_count, fn _ ->
      Process.sleep(1000)
      snapshot = collect_beam_snapshot()
      Metrics.record_beam(table, snapshot)
    end)

    sample_count
  end

  @spec collect_beam_snapshot() :: map()
  defp collect_beam_snapshot do
    scheduler_util = :scheduler.utilization(1)
    {total_util, _per_scheduler} = parse_scheduler_util(scheduler_util)

    memory = :erlang.memory()
    memory_mb = Float.round(memory[:total] / 1_048_576, 1)
    process_count = :erlang.system_info(:process_count)

    mailboxes = collect_mailbox_depths()

    %{
      scheduler_util: total_util,
      process_count: process_count,
      memory_mb: memory_mb,
      mailboxes: mailboxes
    }
  end

  @spec parse_scheduler_util(term()) :: {float(), [float()]}
  defp parse_scheduler_util(util_list) do
    per_scheduler =
      util_list
      |> Enum.filter(fn
        {:total, _, _} -> false
        {:weighted, _, _} -> false
        _ -> true
      end)
      |> Enum.map(fn {_id, util, _percent} -> util end)

    total =
      case Enum.find(util_list, fn
             {:total, _, _} -> true
             _ -> false
           end) do
        {:total, util, _} -> Float.round(util * 100, 1)
        _ -> 0.0
      end

    {total, per_scheduler}
  end

  @spec collect_mailbox_depths() :: map()
  defp collect_mailbox_depths do
    servers = %{
      entity_server: Gameserver.EntityServer,
      world_server: Gameserver.WorldServer,
      combat_server: Gameserver.CombatServer
    }

    Map.new(servers, fn {label, name} ->
      depth =
        case GenServer.whereis(name) do
          pid when is_pid(pid) ->
            {:message_queue_len, len} = Process.info(pid, :message_queue_len)
            len

          nil ->
            0
        end

      {label, depth}
    end)
  end

  @spec stop_players(pids :: [pid()]) :: :ok
  defp stop_players(pids) do
    Enum.each(pids, fn pid ->
      if Process.alive?(pid), do: Process.exit(pid, :shutdown)
    end)

    # give worldserver time to process leaves
    Process.sleep(500)
  end

  @spec print_report(
          Metrics.table(),
          players :: pos_integer(),
          move_interval :: pos_integer(),
          duration :: pos_integer()
        ) :: :ok
  defp print_report(table, players, move_interval, duration) do
    renders = table |> Metrics.get_renders() |> Enum.sort()
    beam_snapshots = Metrics.get_beam_snapshots(table)

    Mix.shell().info("""

    == load test results ==
    players:       #{players}
    move interval: #{move_interval} ms
    duration:      #{duration} s
    """)

    print_render_stats(renders)
    print_beam_stats(beam_snapshots)
  end

  @spec print_render_stats(renders :: [non_neg_integer()]) :: :ok
  defp print_render_stats([]) do
    Mix.shell().info("  no render events captured")
  end

  defp print_render_stats(renders) do
    count = length(renders)
    avg = div(Enum.sum(renders), count)

    Mix.shell().info("""
    -- render time (#{count} renders) --
    avg:  #{Metrics.format_us(avg)}
    p50:  #{Metrics.format_us(Metrics.percentile(renders, 50))}
    p95:  #{Metrics.format_us(Metrics.percentile(renders, 95))}
    p99:  #{Metrics.format_us(Metrics.percentile(renders, 99))}
    max:  #{Metrics.format_us(List.last(renders))}
    """)
  end

  @spec print_beam_stats(snapshots :: [map()]) :: :ok
  defp print_beam_stats([]) do
    Mix.shell().info("  no beam snapshots captured")
  end

  defp print_beam_stats(snapshots) do
    avg_util = avg_field(snapshots, :scheduler_util)
    peak_util = max_field(snapshots, :scheduler_util)
    avg_procs = avg_field(snapshots, :process_count) |> round()
    peak_procs = max_field(snapshots, :process_count)
    avg_mem = avg_field(snapshots, :memory_mb)
    peak_mem = max_field(snapshots, :memory_mb)

    Mix.shell().info("""
    -- beam metrics --
    scheduler util: avg #{Float.round(avg_util, 1)}%  peak #{Float.round(peak_util, 1)}%
    process count:  avg #{avg_procs}  peak #{peak_procs}
    memory:         avg #{Float.round(avg_mem, 1)} MB  peak #{Float.round(peak_mem, 1)} MB
    """)

    print_mailbox_stats(snapshots)
  end

  @spec print_mailbox_stats(snapshots :: [map()]) :: :ok
  defp print_mailbox_stats(snapshots) do
    mailbox_snapshots = Enum.map(snapshots, & &1.mailboxes)

    [:entity_server, :world_server, :combat_server]
    |> Enum.each(fn server ->
      depths = Enum.map(mailbox_snapshots, &Map.get(&1, server, 0))
      avg = div(Enum.sum(depths), length(depths))
      peak = Enum.max(depths)
      name = server |> Atom.to_string() |> String.replace("_", " ")
      Mix.shell().info("    #{name}: avg #{avg}  peak #{peak}")
    end)

    Mix.shell().info("")
  end

  @spec avg_field(maps :: [map()], field :: atom()) :: float()
  defp avg_field(maps, field) do
    values = Enum.map(maps, &Map.fetch!(&1, field))
    Enum.sum(values) / length(values)
  end

  @spec max_field(maps :: [map()], field :: atom()) :: number()
  defp max_field(maps, field) do
    maps |> Enum.map(&Map.fetch!(&1, field)) |> Enum.max()
  end

  @spec await_ready!(port :: pos_integer()) :: :ok
  defp await_ready!(port), do: await_ready!(port, 50)

  @spec await_ready!(port :: pos_integer(), retries :: non_neg_integer()) :: :ok
  defp await_ready!(_port, 0), do: Mix.raise("server did not become ready")

  defp await_ready!(port, retries) do
    case :gen_tcp.connect(~c"localhost", port, [], 200) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, _} ->
        Process.sleep(100)
        await_ready!(port, retries - 1)
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
end
