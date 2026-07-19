defmodule Mix.Tasks.Compile.ExoforgeManifest do
  use Mix.Task
  alias Exoforge.Domain.Manifest

  @impl true
  def run(_args) do
    config = Mix.Project.config()

    case config[:exo_module] do
      nil -> :noop
      exo_config -> generate_manifest(config, exo_config)
    end
  end

  defp generate_manifest(config, exo_config) do
    app = config[:app]
    version = config[:version]
    type = Keyword.get(exo_config, :type, :elixir)
    name = Keyword.get(exo_config, :name, to_string(app))
    entrypoint_mod = Keyword.fetch!(exo_config, :entrypoint)

    manifest = %Manifest{
      id: app,
      name: name,
      version: version,
      type: type,
      # set by the loader.
      physical_path: nil,
      entry_point: entrypoint_mod
    }

    manifest_map = Map.from_struct(manifest)

    exs_content =
      manifest_map
      |> Map.delete(:physical_path)
      |> inspect(pretty: true, limit: :infinity)

    out_dir = Mix.Project.app_path()
    out_path = Path.join(out_dir, "manifest.exs")

    File.mkdir_p!(out_dir)
    File.write!(out_path, exs_content)

    Mix.shell().info("#{IO.ANSI.green()}[ExoForge Manifest]#{IO.ANSI.reset()} Generated manifest.exs for :#{app}")
    :ok
  end
end
