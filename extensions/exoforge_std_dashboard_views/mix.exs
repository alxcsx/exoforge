defmodule Exoforge.Std.DashboardViews.MixProject do
  use Mix.Project

  def project do
    [
      app: :exoforge_std_dashboard_views,
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
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_html, "~> 4.0"},
      {:jason, "~> 1.4"}
    ]
  end
end
