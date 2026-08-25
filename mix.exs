defmodule Exoforge.Project do
  use Mix.Project

  def project do
    [
      app: :exoforge,
      version: "1.0.0",
      elixir: "~> 1.20",
      aliases: aliases(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      build_path: "_build",
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

  defp deps do
    [
      {:exoforge_core, path: "core"}
    ] ++ module_deps()
  end

  defp module_deps do
    Path.wildcard("modules/*")
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
