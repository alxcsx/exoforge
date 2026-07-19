defmodule Exoforge.Domain.ModuleBootstrapper do
  alias Exoforge.Domain.ExoModuleRegistry
  alias Exoforge.Domain.Manifest
  alias Exoforge.Drivers.Runtime.ElixirModuleRunner

  def run(driver, path) do
    driver.load_modules(path)
    |> Enum.each(&initialize_and_register/1)
  end

  defp initialize_and_register(%Manifest{type: :elixir} = manifest) do
    ElixirModuleRunner.load(manifest)
    ExoModuleRegistry.register(manifest)
  end
end
