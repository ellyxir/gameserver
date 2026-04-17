defmodule Gameserver.Bench.SimPlayerTest do
  use ExUnit.Case, async: true

  alias Gameserver.Bench.SimPlayer

  describe "build_join_message/2" do
    test "formats a liveview phx_join message" do
      tokens = %{
        csrf_token: "csrf-123",
        phx_session: "session-abc",
        phx_static: "static-xyz",
        phx_id: "phx-F9xKz"
      }

      msg = SimPlayer.build_join_message(tokens, "http://localhost:4000/world?user_id=test")
      decoded = Jason.decode!(msg)

      assert [join_ref, ref, topic, "phx_join", payload] = decoded
      assert join_ref == "1"
      assert ref == "1"
      assert topic == "lv:phx-F9xKz"
      assert payload["session"] == "session-abc"
      assert payload["static"] == "static-xyz"
      assert payload["params"]["_csrf_token"] == "csrf-123"
      assert payload["url"] == "http://localhost:4000/world?user_id=test"
    end
  end

  describe "build_keydown_message/3" do
    test "formats a liveview keydown event message" do
      msg = SimPlayer.build_keydown_message("lv:phx-F9xKz", "5", "d")
      decoded = Jason.decode!(msg)

      assert ["1", "5", "lv:phx-F9xKz", "event", payload] = decoded
      assert payload["type"] == "keydown"
      assert payload["event"] == "keydown"
      assert payload["value"]["key"] == "d"
    end
  end

  describe "build_heartbeat_message/1" do
    test "formats a phoenix heartbeat message" do
      msg = SimPlayer.build_heartbeat_message("10")
      decoded = Jason.decode!(msg)

      assert [nil, "10", "phoenix", "heartbeat", %{}] = decoded
    end
  end

  describe "parse_frame/1" do
    test "parses a phx_reply frame" do
      frame = Jason.encode!(["1", "1", "lv:phx-F9xKz", "phx_reply", %{"status" => "ok"}])
      assert {:phx_reply, "1", %{"status" => "ok"}} = SimPlayer.parse_frame(frame)
    end

    test "parses a diff frame" do
      frame = Jason.encode!(["1", nil, "lv:phx-F9xKz", "diff", %{"0" => "changed"}])
      assert {:diff, %{"0" => "changed"}} = SimPlayer.parse_frame(frame)
    end

    test "returns unknown for unrecognized events" do
      frame = Jason.encode!(["1", "2", "lv:phx-F9xKz", "something_else", %{}])
      assert {:unknown, "something_else"} = SimPlayer.parse_frame(frame)
    end
  end
end
