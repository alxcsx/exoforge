defmodule Database.MixProject do
  use Mix.Project

  def project do
    [
      app: :database,
      version: "0.1.0",
      elixir: "~> 1.20",
      deps: deps(),
      compilers: Mix.compilers() ++ [:exoforge_manifest],
      exo_module: [
        entrypoint: Exoforge.Std.Database
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:exoforge_core, path: "../../core"}
    ]
  end
end
