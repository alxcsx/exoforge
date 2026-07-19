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
    ]
  end

  defp aliases do
    [
      compile: [&compile_all/1, "compile"],
      test: &test_all/1,
      "deps.get": &deps_get_all/1
    ]
  end

  defp test_all(_args) do
    execute_across_workspace(["test"])
  end

  defp compile_all(_args) do
    execute_across_workspace(["compile"])
  end

  defp deps_get_all(_args) do
    execute_across_workspace(["deps.get"])
  end

  defp execute_across_workspace(mix_args) do
    targets = ["core" | component_directories()]

    Enum.each(targets, fn dir ->
      Mix.shell().info("#{IO.ANSI.blue()}[ExoForge Workspace]#{IO.ANSI.reset()} Running 'mix #{Enum.join(mix_args, " ")}' in #{dir}")

      case System.cmd("mix", mix_args, cd: dir, into: IO.stream(:stdio, :line)) do
        {_, 0} -> :ok
        _ -> Mix.raise("Workspace failure: 'mix #{Enum.join(mix_args, " ")}' failed in folder '#{dir}'")
      end
    end)
  end

  defp component_directories do
    "modules/*"
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
  end
end
