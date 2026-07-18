defmodule Exoforge.Drivers.Loaders.ManifestLoader do
  @behaviour Exoforge.Contracts.ModuleLoader
  alias Exoforge.Domain.Manifest
  require Logger

  @impl true
  def load_modules do
    base_dir = Application.get_env(:exoforge, :modules_dir)
    if is_nil(base_dir), do: raise("Modules dir not found. Please set :modules_dir in your config")

    Logger.info("[ManifestLoader] Loading modules from #{base_dir}")

    Path.join([base_dir, "*", "manifest.toml"])
    |> Path.wildcard()
    |> Enum.map(&parse_manifest/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_manifest(file_path) do
    content = File.read!(file_path)

    parsed_toml = TomlElixir.decode(content)

    if Map.has_key?(parsed_toml, "id") do
      %Manifest{
        id: parsed_toml["id"],
        version: parsed_toml["version"],
        entry_point: String.to_atom(parsed_toml["entry_point"]),
        name: Map.get(parsed_toml, "name", parsed_toml["id"]),
        physical_path: Map.get(parsed_toml, "physical_path", Path.dirname(file_path))
      }
    else
      Logger.warning("[ManifestLoader][Invalid Manifest] No id key found in manifest #{file_path}")
      nil
    end
  end
end
