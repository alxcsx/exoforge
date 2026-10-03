defmodule Exoforge.Endpoints do
  @moduledoc """
  Default network ports for the standard ingress plugins.

  Each value is overridable via application config; these are the fallbacks,
  defined once so the plugins, routers, and OpenAPI spec agree.
  """

  @ws_default 4000
  @http_default 4001
  @dashboard_default 4005

  def ws_port,
    do: Application.get_env(:exoforge, :ws_port) || Application.get_env(:exoforge, :gateway_port, @ws_default)

  def http_port, do: Application.get_env(:exoforge, :http_port, @http_default)
  def dashboard_port, do: Application.get_env(:exoforge, :dashboard_port, @dashboard_default)
end
