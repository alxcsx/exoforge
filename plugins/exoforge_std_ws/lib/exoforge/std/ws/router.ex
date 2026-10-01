defmodule Exoforge.Std.Ws.Router do
  @moduledoc """
  HTTP and WebSocket router for the exoforge_std_ws plugin.
  """
  use Plug.Router

  plug Plug.Logger
  plug :match
  plug :dispatch

  get "/health" do
    send_resp(conn, 200, Jason.encode!(%{status: "ok", plugin: "exoforge_std_ws"}))
  end

  get "/ws" do
    conn
    |> WebSockAdapter.upgrade(Exoforge.Std.Ws.SocketHandler, [], timeout: 60_000)
    |> halt()
  end

  match _ do
    send_resp(conn, 404, Jason.encode!(%{error: "not_found"}))
  end
end
