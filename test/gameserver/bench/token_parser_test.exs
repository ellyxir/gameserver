defmodule Gameserver.Bench.TokenParserTest do
  use ExUnit.Case, async: true

  alias Gameserver.Bench.TokenParser

  @sample_html """
  <!DOCTYPE html>
  <html lang="en">
    <head>
      <meta name="csrf-token" content="test-csrf-token-123" />
    </head>
    <body>
      <div data-phx-main id="phx-F9xKz" data-phx-session="session-token-abc" data-phx-static="static-token-xyz">
        <div>page content</div>
      </div>
    </body>
  </html>
  """

  test "extracts csrf token from meta tag" do
    assert {:ok, tokens} = TokenParser.parse(@sample_html)
    assert tokens.csrf_token == "test-csrf-token-123"
  end

  test "extracts phx-session from data attribute" do
    assert {:ok, tokens} = TokenParser.parse(@sample_html)
    assert tokens.phx_session == "session-token-abc"
  end

  test "extracts phx-static from data attribute" do
    assert {:ok, tokens} = TokenParser.parse(@sample_html)
    assert tokens.phx_static == "static-token-xyz"
  end

  test "extracts phx-id from data-phx-main div" do
    assert {:ok, tokens} = TokenParser.parse(@sample_html)
    assert tokens.phx_id == "phx-F9xKz"
  end

  test "returns error for HTML missing tokens" do
    assert {:error, :missing_tokens} = TokenParser.parse("<html><body>no tokens</body></html>")
  end

  test "returns error when some tokens are missing" do
    html = """
    <html><head><meta name="csrf-token" content="token-123" /></head><body></body></html>
    """

    assert {:error, :missing_tokens} = TokenParser.parse(html)
  end
end
