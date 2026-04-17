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
      <div id="phx-F9xKz" data-phx-main data-phx-session="session-token-abc" data-phx-static="static-token-xyz">
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

  test "extracts cookie from response headers with list values" do
    headers = [{"set-cookie", ["_session=abc123; path=/; HttpOnly"]}]
    assert {:ok, tokens} = TokenParser.parse(@sample_html, headers)
    assert tokens.cookie == "_session=abc123"
  end

  test "extracts cookie from response headers with string value" do
    headers = [{"set-cookie", "_session=xyz789; path=/"}]
    assert {:ok, tokens} = TokenParser.parse(@sample_html, headers)
    assert tokens.cookie == "_session=xyz789"
  end

  test "cookie is nil when no set-cookie header" do
    assert {:ok, tokens} = TokenParser.parse(@sample_html, [])
    assert tokens.cookie == nil
  end
end
