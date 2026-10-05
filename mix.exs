defmodule Exoforge.Project do
  use Mix.Project

  def project do
    [
      app: :exoforge,
      version: "1.0.0",
      elixir: "~> 1.20",
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

  defp deps(_env), do: base_deps() ++ module_deps()

  defp base_deps do
    [
      {:exoforge_core, path: "core"},
      {:jason, "~> 1.4"},
      {:wasmex, "~> 0.15.1"},
      {:horde, "~> 0.9"},
      {:libcluster, "~> 3.4"}
    ]
  end

  defp module_deps do
    Path.wildcard("plugins/*")
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(fn path ->
      app_name = Path.basename(path) |> String.to_atom()
      {app_name, path: path}
    end)
  end

  defp aliases do
    []
  end
end
