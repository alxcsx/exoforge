defmodule Exoforge.Std.Dashboard.MixProject do
  use Mix.Project

  def project do
    [
      app: :exoforge_std_dashboard,
      version: "0.1.0",
      elixir: "~> 1.20",
      deps: deps(),
      compilers: Mix.compilers() ++ [:exoforge_manifest]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:exoforge_core, path: "../../core"},
      {:exoforge_std_database, path: "../exoforge_std_database"},
      {:exoforge_std_dashboard_views, path: "../exoforge_std_dashboard_views", only: [:dev, :test]},
      {:exoforge_std_auth, path: "../exoforge_std_auth", only: [:dev, :test]},
      {:exoforge_std_player_data, path: "../exoforge_std_player_data", only: [:dev, :test]},
      {:exoforge_std_plugin_manager, path: "../exoforge_std_plugin_manager", only: [:dev, :test]},
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_html, "~> 4.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:bandit, "~> 1.12"},
      {:jason, "~> 1.4"}
    ]
  end
end
