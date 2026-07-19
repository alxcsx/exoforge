defmodule Exoforge.Core do
  use Mix.Project

  def project do
    [
      app: :exoforge_core,
      version: "0.1.0",
      elixir: "~> 1.20",
      deps: deps(),
      build_path: "../_build",
      config_path: "../config/config.exs",
      deps_path: "../_deps",
      lockfile: "../mix.lock"
    ]
  end

  defp deps do
    []
  end
end
