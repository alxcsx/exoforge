defmodule Exoforge.Drivers.Runtime.ElixirPluginRunner do
  alias Exoforge.Domain.Manifest

  def load(%Manifest{} = manifest) do
    Code.append_path(Path.join(manifest.physical_path, "ebin"))

    DynamicSupervisor.start_child(
      Exoforge.PluginSupervisor,
      {manifest.entry_point, manifest}
    )
  end
end
