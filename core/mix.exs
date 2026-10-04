defmodule Exoforge.Core do
  use Mix.Project

  def project do
    [
      app: :exoforge_core,
      version: "0.1.0",
      elixir: "~> 1.20",
      deps: deps()
    ]
  end

  defp deps do
    [
      {:wasmex, "~> 0.15.1"},
      {:jason, "~> 1.4"},
      {:horde, "~> 0.9"},
      {:libcluster, "~> 3.4", optional: true}
    ]
  end
end
