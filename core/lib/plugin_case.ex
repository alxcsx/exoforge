defmodule Exoforge.PluginCase do
  @moduledoc """
  Setup helpers shared by the standard plugin test suites.

  A plugin project depends on `exoforge_core` as a prod-compiled path dependency, so a module under
  core's `test/support` is not there to load; this one lives in `lib` and is inert in a release.
  It knows no particular plugin: the caller names the plugin module and the helper supplies the
  canonical manifest shape, which is what each suite used to write out by hand.
  """

  alias Exoforge.Domain.Manifest
  alias Exoforge.PluginRegistry
  alias Exoforge.Std.Services

  @doc "Initializes the registry and starts the event dispatcher if it is not already running."
  def start_kernel do
    PluginRegistry.initialize_ets()

    unless Process.whereis(Exoforge.EventDispatcher.registry_name()) do
      ExUnit.Callbacks.start_supervised!(Exoforge.EventDispatcher)
    end

    :ok
  end

  @doc "Registers the standard database plugin under its canonical id and contracts."
  def register_database(entry_point) do
    register_plugin(entry_point,
      id: :exoforge_std_database,
      provides: [Services.Database, Services.Lldb]
    )
  end

  @doc "Registers the standard auth plugin, depending on the standard database."
  def register_auth(entry_point) do
    register_plugin(entry_point,
      id: :exoforge_std_auth,
      provides: [Services.Auth],
      dependencies: [Services.Database]
    )
  end

  @doc "Registers a plugin - or a test stub - by its entry point, with the standard defaults."
  def register_plugin(entry_point, opts \\ []) do
    id = Keyword.get(opts, :id) || derive_id(entry_point)

    overrides =
      if is_atom(entry_point) and Code.ensure_loaded?(entry_point) and function_exported?(entry_point, :manifest_overrides, 0) do
        entry_point.manifest_overrides() || %{}
      else
        %{}
      end

    dv = Map.get(overrides, :dashboard_view)
    dv_title = is_map(dv) && (Map.get(dv, :title) || Map.get(dv, "title"))
    dv_icon = is_map(dv) && (Map.get(dv, :icon) || Map.get(dv, "icon"))

    base = %{
      id: id,
      name: to_string(id),
      version: "0.1.0",
      entry_point: entry_point,
      title: dv_title,
      icon: dv_icon,
      provides: [],
      dependencies: []
    }

    merged = Map.merge(base, overrides)
    merged = Enum.reduce(opts, merged, fn {k, v}, acc -> Map.put(acc, k, v) end)

    manifest = struct!(Manifest, merged)
    PluginRegistry.register(manifest)
  end

  @doc "Turns development tokens on for this test, and off after it."
  def allow_dev_tokens do
    Application.put_env(:exoforge, :allow_dev_tokens, true)
    ExUnit.Callbacks.on_exit(fn -> Application.delete_env(:exoforge, :allow_dev_tokens) end)
    :ok
  end

  defp derive_id(entry_point) do
    entry_point |> Module.split() |> List.last() |> Macro.underscore() |> String.to_atom()
  end
end
