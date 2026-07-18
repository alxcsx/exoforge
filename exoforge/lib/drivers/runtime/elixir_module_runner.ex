defmodule Exoforge.Drivers.Runtime.ElixirModuleRunner do
  alias Exoforge.Domain.Manifest

  def load(%Manifest{} = manifest) do
    Code.append_path(Path.join(manifest.physical_path, "ebin"))
    Application.load(String.to_atom(manifest.id))
    manifest.entry_point.init(manifest)
  end
end
