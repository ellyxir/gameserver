defmodule GameserverWeb.PageController do
  use GameserverWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
