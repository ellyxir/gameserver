defmodule Gameserver.Bench.TokenParser do
  @moduledoc """
  Parses LiveView session tokens from rendered HTML.

  Extracts the csrf-token, phx-session, phx-static, and LiveView
  topic id needed to connect a WebSocket client to a LiveView.
  """

  @typedoc "Parsed tokens needed to connect to a LiveView over WebSocket"
  @type tokens() :: %{
          csrf_token: String.t(),
          phx_session: String.t(),
          phx_static: String.t(),
          phx_id: String.t()
        }

  @csrf_regex ~r/meta name="csrf-token" content="([^"]+)"/
  @session_regex ~r/data-phx-session="([^"]+)"/
  @static_regex ~r/data-phx-static="([^"]+)"/
  @id_regex ~r/data-phx-main id="([^"]+)"/

  @doc "Parses LiveView connection tokens from HTML."
  @spec parse(html :: String.t()) :: {:ok, tokens()} | {:error, :missing_tokens}
  def parse(html) do
    with {:ok, csrf_token} <- extract(html, @csrf_regex),
         {:ok, phx_session} <- extract(html, @session_regex),
         {:ok, phx_static} <- extract(html, @static_regex),
         {:ok, phx_id} <- extract(html, @id_regex) do
      {:ok,
       %{
         csrf_token: csrf_token,
         phx_session: phx_session,
         phx_static: phx_static,
         phx_id: phx_id
       }}
    end
  end

  @spec extract(String.t(), Regex.t()) :: {:ok, String.t()} | {:error, :missing_tokens}
  defp extract(html, regex) do
    case Regex.run(regex, html) do
      [_, value] -> {:ok, value}
      _ -> {:error, :missing_tokens}
    end
  end
end
