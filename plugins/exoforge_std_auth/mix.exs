defmodule Exoforge.Std.Auth.MixProject do
  use Mix.Project

  def project do
    [
      app: :exoforge_std_auth,
      version: "0.1.0",
      elixir: "~> 1.20",
      deps: deps(),
      compilers: Mix.compilers() ++ [:exoforge_manifest]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:exoforge_core, path: "../../core"},
      {:exoforge_std_database, path: "../exoforge_std_database"},
      {:jason, "~> 1.4"}
    ]
  end
end
