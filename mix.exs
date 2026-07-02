defmodule Exoforge.Meta do
  use Mix.Project

  def project do
    [
      app: :exoforge_meta,
      version: "1.0.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: [],
      aliases: aliases()
    ]
  end

  defp aliases do
    [
      compile: &compile_all/1,
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
    targets = ["exoforge" | component_directories()]

    Enum.each(targets, fn dir ->
      Mix.shell().info("\n➡️ \e[34m[ExoForge Workspace]\e[0m Running 'mix #{Enum.join(mix_args, " ")}' in #{dir}...")

      case System.cmd("mix", mix_args, cd: dir, into: IO.stream(:stdio, :line)) do
        {_, 0} -> :ok
        _ -> Mix.raise("Workspace failure: 'mix #{Enum.join(mix_args, " ")}' failed in folder '#{dir}'")
      end
    end)
  end

  defp component_directories do
    "components/*"
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
  end
end
