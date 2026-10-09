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
      if File.exists?(Path.join(path, "manifest.json")) do
        [Path.join(path, "manifest.json")]
      else
        Path.join([path, "*", "manifest.json"]) |> Path.wildcard()
      end

    files
    |> Enum.map(&parse_manifest/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_manifest(file_path) do
    content = File.read!(file_path) |> String.trim_leading("\uFEFF")

    # Two formats came before this one, and a stale file of either is worth naming: the parse error
    # for an Elixir map literal is "unexpected byte 0x25", which says nothing about what to do.
    if String.starts_with?(content, "%{") do
      raise "this is an Elixir manifest, which is no longer read. Rebuild the plugin to write manifest.json."
    end

    manifest_map = content |> Jason.decode!() |> to_manifest_terms()

    if Map.has_key?(manifest_map, :export) do
      raise "this looks like a contract export, not a manifest. Rebuild the plugin to write manifest.json."
    end

    # A manifest may carry a field this build does not know - a newer plugin, or one written before a
    # field was removed. Dropping it keeps the format additive: adding a field does not break old
    # servers, removing one does not break old manifests.
    {manifest_map, unknown} = Map.split(manifest_map, Map.keys(Manifest.__struct__()))

    if unknown != %{} do
      Logger.warning(
        "[ManifestLoader] #{file_path} declares fields this build does not know: #{inspect(Map.keys(unknown))}"
      )
    end

    manifest_version = Version.parse!(manifest_map.version)

    final_map =
      manifest_map
      # An Elixir plugin's entry point is a module and a native one's is a file, so this is
      # the single field the key alone cannot classify. Everything else is decided by key.
      |> Map.update!(:entry_point, &elixir_module(manifest_map.type, &1))
      # The file does not carry a name: it is the id, and two fields for one value is one to
      # disagree with.
      |> Map.put_new(:name, to_string(manifest_map.id))
      |> Map.put(:version, manifest_version)
      |> Map.put(:physical_path, Path.dirname(file_path))

    struct!(Manifest, final_map)
  rescue
    e ->
      Logger.error("[ManifestLoader] Failed to parse manifest file #{file_path}: #{Exception.message(e)}")
      nil
  end

  # JSON has no atoms, and the kernel keys plugins, services, actions and types by them, so they have
  # to come back. Which values are atoms is decided by their key, never by position: `type` is an atom
  # at the top and in a column, a resource's C# record is `record`, and every `name` in the file is a
  # service, action, event, resource or column name. One field that meant something else would have
  # cost a reader that knows where it is.
  @atom_keys ~w(id type context mode scope transport returns primary_key name)
  @atom_list_keys ~w(dependencies provides drawer actions)
  @atom_map_keys ~w(params payload)

  defp to_manifest_terms(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {String.to_atom(key), to_manifest_terms(key, value)} end)
  end

  defp to_manifest_terms(list) when is_list(list), do: Enum.map(list, &to_manifest_terms/1)

  defp to_manifest_terms(other), do: other

  defp to_manifest_terms(key, value) when key in @atom_keys, do: atom(value)

  # `actions` is a list of names on a resource and a list of definitions on a service, so the key
  # alone does not say which. The shape does: names are strings, definitions are objects.
  defp to_manifest_terms(key, value) when key in @atom_list_keys and is_list(value) do
    if Enum.all?(value, &is_binary/1), do: Enum.map(value, &atom/1), else: to_manifest_terms(value)
  end

  defp to_manifest_terms(key, value) when key in @atom_map_keys do
    Map.new(value || %{}, fn {name, type} -> {atom(name), atom(type)} end)
  end

  defp to_manifest_terms(_key, value), do: to_manifest_terms(value)

  # Created rather than looked up: a manifest names services, actions and types that may not have been
  # mentioned anywhere else yet, and the kernel keys all of them by atom. `Code.eval_string` used to do
  # this implicitly, for every symbol in the file - so this is the same exposure, on a shorter list.
  defp atom(value) when is_binary(value), do: String.to_atom(value)
  defp atom(value), do: value

  defp elixir_module(:elixir, value) when is_binary(value), do: String.to_atom(value)
  defp elixir_module(_type, value), do: value
end
