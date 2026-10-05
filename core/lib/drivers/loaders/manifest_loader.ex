defmodule Exoforge.Drivers.Loaders.ManifestLoader do
  alias Exoforge.Domain.Manifest
  require Logger

  def load_plugins(nil), do: raise("Modules dir not found. Please set :scan_path in your config")

  def load_plugins(paths) when is_list(paths) do
    paths
    |> Enum.flat_map(&load_plugins/1)
    |> Enum.uniq_by(& &1.id)
  end

  def load_plugins(path) when is_binary(path) do
    Logger.info("[ManifestLoader] Loading modules from #{path}")

    files =
      if File.exists?(Path.join(path, "manifest.exs")) do
        [Path.join(path, "manifest.exs")]
      else
        Path.join([path, "*", "manifest.exs"]) |> Path.wildcard()
      end

    files
    |> Enum.map(&parse_manifest/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_manifest(file_path) do
    try do
      content = File.read!(file_path) |> String.trim_leading("\uFEFF")
      {manifest_map, _binding} = Code.eval_string(content, [], file: file_path)

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
      e ->
        Logger.error("[ManifestLoader] Failed to parse manifest file #{file_path}: #{Exception.message(e)}")
        nil
    end
  end
end
