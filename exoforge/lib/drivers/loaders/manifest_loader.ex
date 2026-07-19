defmodule Exoforge.Drivers.Loaders.ManifestLoader do
  @behaviour Exoforge.Contracts.ModuleLoader
  alias Exoforge.Domain.Manifest
  require Logger

  @impl true
  def load_modules(path) do
    if is_nil(path), do: raise("Modules dir not found. Please set :modules_dir in your config")

    Logger.info("[ManifestLoader] Loading modules from #{path}")

    Path.join([path, "*", "manifest.exs"])
    |> Path.wildcard()
    |> Enum.map(&parse_manifest/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_manifest(file_path) do
    try do
      {manifest_map, _binding} = Code.eval_file(file_path)

      if not is_map(manifest_map) do
        raise "Invalid manifest file: #{file_path}. Expected a map, got: #{inspect(manifest_map)}"
      end

      manifest_version = Version.parse!(manifest_map.version)

      final_map =
        manifest_map
        |> Map.put(:version, manifest_version)
        |> Map.put(:physical_path, Path.dirname(file_path))

      struct!(Manifest, final_map)
    rescue
      e in [SyntaxError, CompileError] ->
        Logger.error("[ManifestLoader] Failed to parse manifest file #{file_path}: #{Exception.message(e)}")
        nil

      e in RuntimeError ->
        Logger.error("[ManifestLoader] Error in manifest file #{file_path}: #{Exception.message(e)}")
        nil

      e in ArgumentError ->
        Logger.error("[ManifestLoader] Rejected #{file_path}: Missing or invalid fields. #{Exception.message(e)}")
        nil

      _e in Version.InvalidRequirementError ->
        Logger.error("[ManifestLoader] Rejected #{file_path}: Invalid Semantic Version format.")
        nil

      e ->
        Logger.error("[ManifestLoader] Rejected #{file_path}: Failed to evaluate file. #{inspect(e)}")
        nil
    end
  end
end
