defmodule Mix.Tasks.Compile.ExoforgeManifest do
  use Mix.Task
  alias Exoforge.Domain.Manifest

  @impl true
  def run(_args) do
    config = Mix.Project.config()

    case find_plugin_entrypoint() do
      nil -> :noop
      entrypoint_mod -> generate_manifest(config, entrypoint_mod)
    end
  end

  # Find the first plugin entrypoint by scanning compiled .beam files.
  # This task must be run after compilation (e.g., from plugins project after compile).
  defp find_plugin_entrypoint do
    Mix.Project.compile_path()
    |> Path.join("*.beam")
    |> Path.wildcard()
    |> Enum.map(fn path ->
      path |> Path.basename(".beam") |> String.to_atom()
    end)
    |> Enum.find(fn module ->
      Code.ensure_loaded?(module) and function_exported?(module, :__exoforge_plugin__?, 0)
    end)
  end

  defp generate_manifest(config, entrypoint_mod) do
    app = config[:app]
    version = config[:version]

    system_defaults = %{
      id: app,
      name: to_string(app),
      version: version,
      entry_point: entrypoint_mod,
      provides: entrypoint_mod.provides_contracts()
    }

    user_manifest = entrypoint_mod.manifest_overrides() || %{}
    merged_attrs = Map.merge(system_defaults, user_manifest)
    manifest = struct!(Manifest, merged_attrs)
    manifest_map = Map.from_struct(manifest)

    # JSON, not an Elixir map literal. The server used to evaluate this file, which meant the only
    # copy of a plugin's contracts could be read by exactly one language - and the C# tooling, which
    # generates client stubs from them, has no Elixir.
    #
    # `sanitize_for_json` turns the atoms into strings; the loader turns the ones it needs back, by
    # key. The name is left out because it is the id, and `physical_path` because the loader sets it
    # from where the file was found.
    json_content =
      manifest_map
      |> Map.drop([:physical_path, :name])
      |> Exoforge.PluginRegistry.sanitize_for_json()
      |> Jason.encode!(pretty: true)

    out_dir = Mix.Project.app_path()
    out_path = Path.join(out_dir, "manifest.json")

    File.mkdir_p!(out_dir)
    File.write!(out_path, json_content <> "\n")

    # The Elixir map literal this replaced is a stale copy in a format nothing reads any more. Left
    # there, it is a second manifest to be confused by.
    File.rm(Path.join(out_dir, "manifest.exs"))

    Mix.shell().info("#{IO.ANSI.green()}[ExoForge Manifest]#{IO.ANSI.reset()} Generated manifest.json for :#{app}")

    :ok
  end
end
