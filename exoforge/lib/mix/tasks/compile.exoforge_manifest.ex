defmodule Mix.Tasks.Compile.ExoforgeManifest do
  use Mix.Task

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

    entrypoint_mod = Keyword.fetch!(exo_config, :entrypoint)
    entrypoint = to_string(entrypoint_mod)

    toml_content = """
        [module]
        name = "#{app}"
        version = "#{version}"
        type = "#{type}"
        entrypoint = "#{entrypoint}"
    """

    out_dir = Mix.Project.app_path()
    out_path = Path.join(out_dir, "manifest.toml")

    File.mkdir_p!(out_dir)
    File.write!(out_path, toml_content)

    Mix.shell().info("[:exoforge_manifest] Generated manifest.toml for :#{app}")
    :ok
  end
end
