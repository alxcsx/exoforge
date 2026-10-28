defmodule Exoforge.Project do
  use Mix.Project

  def project do
    [
      app: :exoforge,
      version: "1.0.0",
      elixir: "~> 1.20",
      test_coverage: [summary: [threshold: 0]],
      aliases: aliases(),
      start_permanent: Mix.env() == :prod,
      deps: deps(Mix.env()),
      config_path: "config/config.exs",
      deps_path: "_deps",
      lockfile: "mix.lock"
    ]
  end

  def application do
    [
      extra_applications: extra_applications(Mix.env()),
      mod: {Exoforge.Application, []}
    ]
  end

  defp extra_applications(:dev), do: [:logger, :wx, :observer, :runtime_tools]
  defp extra_applications(_), do: [:logger]

  defp deps(_env), do: base_deps() ++ extension_deps()

  defp base_deps do
    [
      {:exoforge_core, path: "core"},
      {:jason, "~> 1.4"},
      {:libcluster, "~> 3.4"},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end

  defp extension_deps do
    (Path.wildcard("extensions/*") ++ Path.wildcard("plugins/*"))
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(fn path ->
      app_name = Path.basename(path) |> String.to_atom()
      {app_name, path: path}
    end)
    |> Enum.uniq_by(fn {app_name, _} -> app_name end)
  end

  defp aliases do
    []
  end
end
