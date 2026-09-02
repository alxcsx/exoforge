defmodule Exoforge.PluginBootstrapper do
  alias Exoforge.Domain.Manifest
  alias Exoforge.PluginRegistry
  alias Exoforge.Drivers.Runtime.ElixirPluginRunner

  def run(driver, path) do
    driver.load_modules(path)
    |> Enum.each(&initialize_and_register/1)
  end

  defp initialize_and_register(%Manifest{type: :elixir} = manifest) do
    ElixirPluginRunner.load(manifest)
    PluginRegistry.register(manifest)
  end
end
