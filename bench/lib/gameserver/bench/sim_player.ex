defmodule Gameserver.Bench.SimPlayer do
  @moduledoc """
  A simulated player that connects to a LiveView over WebSocket.

  Speaks enough of the LiveView wire protocol to join a LiveView,
  send events, and receive diffs. Used by the load test bench task
  to simulate concurrent players.
  """

  use WebSockex

  alias Gameserver.Bench.Metrics
  alias Gameserver.Bench.TokenParser
  alias Gameserver.User
  alias Gameserver.WorldServer

  @join_ref "1"
  @heartbeat_interval_ms 30_000
  @keys ~w(w a s d)

  @typedoc "SimPlayer internal state"
  @type state() :: %{
          topic: String.t(),
          ref_counter: non_neg_integer(),
          caller: pid(),
          user_id: String.t(),
          tokens: TokenParser.tokens(),
          url: String.t(),
          move_interval_ms: pos_integer(),
          joined: boolean(),
          pending_refs: %{String.t() => integer()},
          metrics_table: Metrics.table() | nil
        }

  # -- Public API --

  @doc """
  Starts a simulated player that joins the game and moves periodically.

  Creates a user via the direct API (same BEAM), fetches LiveView
  tokens over HTTP, then connects via WebSocket and joins the LiveView.

  Options:
  - `:port` - server port (default 4000)
  - `:move_interval_ms` - ms between moves (defaults to `WorldServer.move_cooldown_ms()`)
  - `:caller` - pid to notify when joined (default `self()`)
  - `:metrics_table` - ETS table for recording latencies (optional)
  """
  @spec start(player_index :: non_neg_integer(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start(player_index, opts \\ []) do
    port = Keyword.get(opts, :port, 4000)
    move_interval_ms = Keyword.get(opts, :move_interval_ms, WorldServer.move_cooldown_ms())
    caller = Keyword.get(opts, :caller, self())
    metrics_table = Keyword.get(opts, :metrics_table)
    username = "loadtest_#{player_index}"

    with {:ok, user} <- User.new(username),
         {:ok, _position} <- WorldServer.join_user(user),
         {:ok, tokens} <- fetch_tokens(port, user.id) do
      url = "ws://localhost:#{port}/live/websocket?_csrf_token=#{URI.encode_www_form(tokens.csrf_token)}&vsn=2.0.0"
      topic = "lv:#{tokens.phx_id}"

      state = %{
        topic: topic,
        # starts at 2 because the join message uses ref "1"
        ref_counter: 2,
        caller: caller,
        user_id: user.id,
        tokens: tokens,
        url: "http://localhost:#{port}/world?user_id=#{user.id}",
        move_interval_ms: move_interval_ms,
        joined: false,
        pending_refs: %{},
        metrics_table: metrics_table
      }

      extra_headers =
        if tokens.cookie, do: [{"cookie", tokens.cookie}], else: []

      WebSockex.start(url, __MODULE__, state, extra_headers: extra_headers)
    end
  end

  @spec fetch_tokens(port :: non_neg_integer(), user_id :: String.t()) ::
          {:ok, TokenParser.tokens()} | {:error, term()}
  defp fetch_tokens(port, user_id) do
    url = "http://localhost:#{port}/world?user_id=#{user_id}"

    case Req.get(url, redirect: false) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        TokenParser.parse(body, Map.to_list(headers))

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # -- Public API: message builders --

  @doc "Builds a LiveView phx_join JSON message from parsed tokens."
  @spec build_join_message(TokenParser.tokens(), url :: String.t()) :: String.t()
  def build_join_message(tokens, url) do
    topic = "lv:#{tokens.phx_id}"

    payload = %{
      "url" => url,
      "params" => %{"_csrf_token" => tokens.csrf_token, "_mounts" => 0},
      "session" => tokens.phx_session,
      "static" => tokens.phx_static
    }

    Jason.encode!([@join_ref, @join_ref, topic, "phx_join", payload])
  end

  @doc "Builds a LiveView keydown event JSON message."
  @spec build_keydown_message(topic :: String.t(), ref :: String.t(), key :: String.t()) ::
          String.t()
  def build_keydown_message(topic, ref, key) do
    payload = %{
      "type" => "keydown",
      "event" => "keydown",
      "value" => %{"key" => key}
    }

    Jason.encode!([@join_ref, ref, topic, "event", payload])
  end

  @doc "Builds a Phoenix heartbeat JSON message."
  @spec build_heartbeat_message(ref :: String.t()) :: String.t()
  def build_heartbeat_message(ref) do
    Jason.encode!([nil, ref, "phoenix", "heartbeat", %{}])
  end

  # -- Frame parsing --

  @typedoc "A parsed LiveView wire protocol frame"
  @type parsed_frame() ::
          {:phx_reply, ref :: String.t(), payload :: map()}
          | {:diff, payload :: map()}
          | {:unknown, event :: String.t()}

  @doc "Parses a LiveView JSON frame into a tagged tuple."
  @spec parse_frame(json :: String.t()) :: parsed_frame()
  def parse_frame(json) do
    case Jason.decode!(json) do
      [_, ref, _, "phx_reply", payload] -> {:phx_reply, ref, payload}
      [_, _, _, "diff", payload] -> {:diff, payload}
      [_, _, _, event, _] when is_binary(event) -> {:unknown, event}
      _other -> {:unknown, "unrecognized"}
    end
  end

  # -- WebSockex callbacks --

  @impl WebSockex
  @spec handle_connect(WebSockex.Conn.t(), state()) :: {:ok, state()}
  def handle_connect(_conn, state) do
    send(self(), :send_join)
    schedule_heartbeat()
    {:ok, state}
  end

  @impl WebSockex
  @spec handle_frame(WebSockex.frame(), state()) :: {:ok, state()}
  def handle_frame({:text, json}, state) do
    case parse_frame(json) do
      {:phx_reply, @join_ref, %{"status" => "ok"}} when not state.joined ->
        send(state.caller, {:sim_player_joined, state.user_id})
        schedule_move(state.move_interval_ms)
        {:ok, %{state | joined: true}}

      {:phx_reply, ref, _payload} ->
        case Map.pop(state.pending_refs, ref) do
          {nil, _} ->
            {:ok, state}

          {sent_at, pending} ->
            latency_us = System.monotonic_time(:microsecond) - sent_at

            if state.metrics_table do
              Metrics.record_latency(state.metrics_table, latency_us)
            end

            {:ok, %{state | pending_refs: pending}}
        end

      {:diff, _payload} ->
        {:ok, state}

      {:unknown, _event} ->
        {:ok, state}
    end
  end

  def handle_frame(_frame, state) do
    {:ok, state}
  end

  @impl WebSockex
  @spec handle_info(term(), state()) :: {:ok, state()} | {:reply, {:text, String.t()}, state()}
  def handle_info(:send_join, state) do
    msg = build_join_message(state.tokens, state.url)
    {:reply, {:text, msg}, state}
  end

  def handle_info(:move, state) do
    key = Enum.random(@keys)
    ref = to_string(state.ref_counter)
    msg = build_keydown_message(state.topic, ref, key)
    sent_at = System.monotonic_time(:microsecond)
    schedule_move(state.move_interval_ms)

    {:reply, {:text, msg},
     %{
       state
       | ref_counter: state.ref_counter + 1,
         pending_refs: Map.put(state.pending_refs, ref, sent_at)
     }}
  end

  def handle_info(:heartbeat, state) do
    ref = to_string(state.ref_counter)
    msg = build_heartbeat_message(ref)
    schedule_heartbeat()
    {:reply, {:text, msg}, %{state | ref_counter: state.ref_counter + 1}}
  end

  def handle_info(_msg, state) do
    {:ok, state}
  end

  @spec schedule_move(interval_ms :: pos_integer()) :: reference()
  defp schedule_move(interval_ms) do
    jitter = :rand.uniform(div(interval_ms, 2) + 1) - 1
    Process.send_after(self(), :move, interval_ms + jitter)
  end

  @spec schedule_heartbeat() :: reference()
  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat, @heartbeat_interval_ms)
  end
end
