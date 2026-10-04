defmodule Exoforge.Std.Dashboard do
  @moduledoc """
  Standard Dashboard system plugin for Exoforge.
  Provides the :dashboard contract and mounts the Phoenix LiveView Endpoint
  backed by Bandit to host the Exoforge Game Producer & Designer Studio.
  """
  use Exoforge.Plugin, provides: [:dashboard]

  @manifest %{
    system: true,
    dependencies: [Exoforge.Std.Services.Database, Exoforge.Std.Services.ResourceStore],
    title: "Exoforge Dashboard",
    icon: "🎛️",
    category: "Studio"
  }

  def children do
    port = Exoforge.Endpoints.dashboard_port()

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

  def on_init(_manifest) do
    _ =
      Exoforge.ActionDispatcher.dispatch(:resource_store, :migrate, %{
        resource: "studio_preference"
      })

    :ok
  end

  @impl true
  defaction get_dashboard_mount(_payload) do
    {:ok,
     %{mount: {:endpoint, Exoforge.Std.Dashboard.Endpoint}, router: Exoforge.Std.Dashboard.Router}}
  end

  @impl true
  defaction get_dashboard_data(_payload) do
    data = Exoforge.Std.Dashboard.Router.build_overview_data()
    {:ok, %{data: data}}
  end
end
