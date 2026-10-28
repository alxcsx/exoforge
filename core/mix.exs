defmodule Exoforge.Core do
  use Mix.Project

  def project do
    [
      app: :exoforge_core,
      version: "0.1.0",
      elixir: "~> 1.20",
      test_coverage: [summary: [threshold: 0]],
      deps: deps()
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:libcluster, "~> 3.4", optional: true}
    ]
  end
end
