defmodule Exoforge.Std.Dashboard do
  @moduledoc """
  Standard Dashboard plugin for Exoforge.
  Provides the :dashboard_view contract.
  Mounts Phoenix LiveView Endpoint backed by Bandit to serve the Exoforge Game Producer & Designer Studio.
  """
  use Exoforge.Plugin, provides: [:dashboard_view]

  @manifest %{
    dependencies: [Exoforge.Std.Services.Database]
  }

  def children do
    port = Application.get_env(:exoforge, :dashboard_port, 4005)

    endpoint_config =
      Application.get_env(:exoforge_std_dashboard, Exoforge.Std.Dashboard.Endpoint, [])
      |> Keyword.put(:adapter, Bandit.PhoenixAdapter)
      |> Keyword.update(:http, [port: port], fn opts -> Keyword.put(opts, :port, port) end)
      |> Keyword.put_new(:server, true)

    Application.put_env(:exoforge_std_dashboard, Exoforge.Std.Dashboard.Endpoint, endpoint_config)

    [
      {Phoenix.PubSub, name: Exoforge.Std.Dashboard.PubSub},
      Exoforge.Std.Dashboard.Endpoint
    ]
  end

  @impl true
  defaction get_dashboard_mount(_payload) do
    {:ok, %{mount: {:endpoint, Exoforge.Std.Dashboard.Endpoint}, router: Exoforge.Std.Dashboard.Router}}
  end

  @impl true
  defaction get_dashboard_data(_payload) do
    data = Exoforge.Std.Dashboard.Router.build_overview_data()
    {:ok, %{data: data}}
  end
end
