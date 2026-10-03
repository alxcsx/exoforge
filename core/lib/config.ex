defmodule Exoforge.Config do
  @moduledoc "Typed accessors for Exoforge application configuration."

  @doc "Whether `dev:<id>` tokens are accepted (never in production)."
  def allow_dev_tokens?, do: Application.get_env(:exoforge, :allow_dev_tokens, false)

  @doc "Whether a valid admin/studio credential is required to use the gateways and Studio."
  def require_admin_auth?, do: Application.get_env(:exoforge, :require_admin_auth, true)

  @doc "Whether the ingress plugins should start their HTTP servers."
  def start_gateway?, do: Application.get_env(:exoforge, :start_gateway, true)
end
