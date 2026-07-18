defmodule Exoforge.Domain.ModuleBootstrapper do
  alias Exoforge.Domain.ExoModuleRegistry
  alias Exoforge.Domain.Manifest
  alias Exoforge.Drivers.Runtime.ElixirModuleRunner

  def run do
    loader = Application.get_env(:exoforge, :module_loader, Exoforge.Drivers.Loaders.ManifestLoader)

    loader.load_modules()
    |> Enum.each(&initialize_and_register/1)
  end

  defp initialize_and_register(%Manifest{type: "elixir"} = manifest) do
    ElixirModuleRunner.load(manifest)
    ExoModuleRegistry.register(manifest)
  end
end
