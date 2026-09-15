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

    exs_content =
      manifest_map
      |> Map.delete(:physical_path)
      |> inspect(pretty: true, limit: :infinity)
      |> Code.format_string!()
      |> IO.iodata_to_binary()

    out_dir = Mix.Project.app_path()
    out_path = Path.join(out_dir, "manifest.exs")

    File.mkdir_p!(out_dir)
    File.write!(out_path, exs_content)

    Mix.shell().info("#{IO.ANSI.green()}[ExoForge Manifest]#{IO.ANSI.reset()} Generated manifest.exs for :#{app}")

    :ok
  end
end
