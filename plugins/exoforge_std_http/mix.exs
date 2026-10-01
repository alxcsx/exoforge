defmodule Exoforge.Std.Http.MixProject do
  use Mix.Project

  def project do
    [
      app: :exoforge_std_http,
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
      {:exoforge_std_auth, path: "../exoforge_std_auth"},
      {:bandit, "~> 1.12"},
      {:jason, "~> 1.4"}
    ]
  end
end
