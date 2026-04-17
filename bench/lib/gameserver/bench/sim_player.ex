defmodule Gameserver.Bench.SimPlayer do
  @moduledoc """
  A simulated player that connects to a LiveView over WebSocket.

  Speaks enough of the LiveView wire protocol to join a LiveView,
  send events, and receive diffs. Used by the load test bench task
  to simulate concurrent players.
  """

  use WebSockex

  alias Gameserver.Bench.TokenParser

  @join_ref "1"

  @typep tokens() :: TokenParser.tokens()

  @typep state() :: %{
           topic: String.t(),
           ref_counter: non_neg_integer(),
           caller: pid()
         }

  # -- Public API: message builders --

  @doc "Builds a LiveView phx_join JSON message from parsed tokens."
  @spec build_join_message(tokens(), url :: String.t()) :: String.t()
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

  # -- WebSockex callbacks --

  @impl WebSockex
  @spec handle_connect(WebSockex.Conn.t(), state()) :: {:ok, state()}
  def handle_connect(_conn, state) do
    {:ok, state}
  end

  @impl WebSockex
  @spec handle_frame(WebSockex.frame(), state()) :: {:ok, state()}
  def handle_frame(_frame, state) do
    {:ok, state}
  end

  @impl WebSockex
  @spec handle_info(term(), state()) :: {:ok, state()}
  def handle_info(_msg, state) do
    {:ok, state}
  end
end
