defmodule Exoforge.Drivers.Runtime.ElixirModuleRunner do
  alias Exoforge.Domain.Manifest

  def load(%Manifest{} = manifest) do
    ebin_dir = Path.join(manifest.physical_path, "ebin")
    Code.append_path(ebin_dir)
    Application.load(String.to_atom(manifest.name))
    manifest.entry_point.init(manifest)
  end
end
