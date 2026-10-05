defmodule Exoforge.Std.PluginManagerTest do
  use ExUnit.Case, async: false

  alias Exoforge.ActionDispatcher
  alias Exoforge.PluginRegistry
  alias Exoforge.Domain.Manifest

  @wasm_magic <<0, 97, 115, 109>>

  setup do
    PluginRegistry.initialize_ets()

    test_manifest = %Manifest{
      id: :test_game_plugin,
      name: "TestGamePlugin",
      version: Version.parse!("1.0.0"),
      type: :elixir,
      entry_point: TestEntryPoint,
      provides: [:test_game_service],
      dependencies: []
    }

    PluginRegistry.register(test_manifest)

    # Register plugin_manager manifest so ActionDispatcher can route to it
    pm_manifest = %Manifest{
      id: :exoforge_std_plugin_manager,
      name: "ExoforgeStdPluginManager",
      version: Version.parse!("0.1.0"),
      type: :elixir,
      entry_point: Exoforge.Std.PluginManager,
      provides: [:plugin_manager],
      dependencies: []
    }

    PluginRegistry.register(pm_manifest)

    on_exit(fn ->
      # Clean up test directories if created
      File.rm_rf("plugins_csharp/test_uploaded_wasm")
      File.rm_rf("plugins_csharp/invalid_test_wasm")
      File.rm_rf("plugins/test_uploaded_elixir")
      File.rm_rf("priv/data/uploaded_plugins/test_uploaded_wasm")
      File.rm_rf("priv/data/uploaded_plugins/test_uploaded_elixir")
    end)

    :ok
  end

  describe "Plugin Manager Service Actions" do
    test "list_plugins returns all registered plugins and count" do
      assert {:ok, result} =
               ActionDispatcher.dispatch(:plugin_manager, :list_plugins, %{},
                 caller_scopes: ["studio"]
               )

      assert is_list(result.plugins)
      assert result.count >= 2
      assert Enum.any?(result.plugins, &(&1["id"] == "test_game_plugin"))
      assert Enum.any?(result.plugins, &(&1["id"] == "exoforge_std_plugin_manager"))
    end

    test "get_plugin returns metadata for known plugin" do
      assert {:ok, result} =
               ActionDispatcher.dispatch(
                 :plugin_manager,
                 :get_plugin,
                 %{id: "test_game_plugin"},
                 caller_scopes: ["studio"]
               )

      assert result.plugin["id"] == "test_game_plugin"
      assert result.plugin["name"] == "TestGamePlugin"
      assert result.plugin["type"] == "elixir"
      assert "test_game_service" in result.plugin["provides"]
    end

    test "get_plugin returns :not_found for unknown plugin" do
      assert {:error, :not_found} =
               ActionDispatcher.dispatch(
                 :plugin_manager,
                 :get_plugin,
                 %{id: "nonexistent_plugin"},
                 caller_scopes: ["studio"]
               )
    end

    test "get_system_info returns BEAM runtime and cluster statistics" do
      assert {:ok, result} =
               ActionDispatcher.dispatch(:plugin_manager, :get_system_info, %{},
                 caller_scopes: ["studio"]
               )

      sys = result.system
      assert is_binary(sys["node"])
      assert is_integer(sys["uptime_seconds"])
      assert is_integer(sys["memory_bytes"])
      assert sys["plugins_count"] >= 2
      assert is_binary(sys["elixir_version"])
      assert is_binary(sys["otp_release"])
    end

    test "export_plugin_info produces a complete bundle for external SDKs and CLI" do
      assert {:ok, result} =
               ActionDispatcher.dispatch(:plugin_manager, :export_plugin_info, %{},
                 caller_scopes: ["studio"]
               )

      export = result.export
      assert is_binary(export["cluster"])
      assert is_integer(export["timestamp"])
      assert export["plugins_count"] >= 2
      assert is_list(export["plugins"])

      test_p = Enum.find(export["plugins"], &(&1["id"] == "test_game_plugin"))
      assert test_p != nil
      assert "test_game_service" in test_p["provides"]
    end

    test "upload_plugin rejects invalid binaries without WASM magic bytes" do
      bad_binary = "This is not a valid WASM binary at all"

      assert {:error, :invalid_package} =
               ActionDispatcher.dispatch(
                 :plugin_manager,
                 :upload_plugin,
                 %{name: "invalid_test_wasm", binary: bad_binary},
                 caller_scopes: ["admin"]
               )
    end

    test "upload_plugin accepts valid WASM binary with magic header and writes to disk" do
      # Minimal mock WASM binary starting with \0asm header + 4-byte version
      valid_wasm = @wasm_magic <> <<1, 0, 0, 0>>

      assert {:ok, result} =
               ActionDispatcher.dispatch(
                 :plugin_manager,
                 :upload_plugin,
                 %{
                   name: "test_uploaded_wasm",
                   binary: valid_wasm,
                   manifest: %{
                     id: :test_uploaded_wasm,
                     name: "TestUploadedWasm",
                     version: "0.1.0",
                     type: :wasm,
                     entry_point: TestUploadedWasm,
                     provides: [:test_uploaded_service],
                     dependencies: []
                   }
                 },
                 caller_scopes: ["admin"]
               )

      assert result.plugin_id == "test_uploaded_wasm"
      assert result.status in ["installed", "saved_pending_restart"]

      # Verify files were persisted to disk
      target_dir = "priv/data/uploaded_plugins/test_uploaded_wasm"
      assert File.exists?(Path.join(target_dir, "test_uploaded_wasm.wasm"))
      assert File.exists?(Path.join(target_dir, "manifest.exs"))
    end

    test "upload_plugin accepts valid Elixir plugin code, persists, compiles, and registers it" do
      elixir_code = """
      defmodule TestUploadedElixir do
        use Exoforge.Plugin, provides: [:test_uploaded_elixir]

        defaction ping(payload) do
          {:ok, %{pong: payload}}
        end
      end
      """

      manifest_content = """
      %{
        id: :test_uploaded_elixir,
        name: "TestUploadedElixir",
        version: "0.1.0",
        type: :elixir,
        entry_point: TestUploadedElixir,
        provides: [:test_uploaded_elixir],
        dependencies: []
      }
      """

      assert {:ok, result} =
               ActionDispatcher.dispatch(
                 :plugin_manager,
                 :upload_plugin,
                 %{
                   name: "test_uploaded_elixir",
                   type: "elixir",
                   elixir_code: elixir_code,
                   manifest: manifest_content
                 },
                 caller_scopes: ["admin"]
               )

      assert result.plugin_id == "test_uploaded_elixir"
      assert result.type == "elixir"

      target_dir = "priv/data/uploaded_plugins/test_uploaded_elixir"
      assert File.exists?(Path.join([target_dir, "lib", "test_uploaded_elixir.ex"]))
      assert File.exists?(Path.join(target_dir, "manifest.exs"))

      assert {:ok, plugin_info} =
               ActionDispatcher.dispatch(
                 :plugin_manager,
                 :get_plugin,
                 %{id: "test_uploaded_elixir"},
                 caller_scopes: ["studio"]
               )

      assert plugin_info.plugin["type"] == "elixir"
      assert plugin_info.plugin["size_bytes"] > 0

      # Remove plugin with delete_files
      assert {:ok, rem_res} =
               ActionDispatcher.dispatch(
                 :plugin_manager,
                 :remove_plugin,
                 %{id: "test_uploaded_elixir", delete_files: true},
                 caller_scopes: ["admin"]
               )

      assert rem_res.status == "removed"
      assert rem_res.type == "elixir"
      refute File.exists?(target_dir)
    end

    test "remove_plugin unregisters plugin from registry" do
      assert {:ok, result} =
               ActionDispatcher.dispatch(
                 :plugin_manager,
                 :remove_plugin,
                 %{id: "test_game_plugin"},
                 caller_scopes: ["admin"]
               )

      assert result.status == "removed"
      assert PluginRegistry.fetch_manifest(:test_game_plugin) == nil
    end

    test "remove_plugin returns :not_found for unknown plugin" do
      assert {:error, :not_found} =
               ActionDispatcher.dispatch(
                 :plugin_manager,
                 :remove_plugin,
                 %{id: "unknown_remove_xyz"},
                 caller_scopes: ["admin"]
               )
    end

    test "scope authorization enforces admin scope on mutating actions" do
      # Non-admin caller should fail
      assert {:error, :forbidden_scope} =
               ActionDispatcher.dispatch(
                 :plugin_manager,
                 :remove_plugin,
                 %{id: "test_game_plugin"},
                 caller_scopes: ["player"]
               )

      assert {:error, :forbidden_scope} =
               ActionDispatcher.dispatch(
                 :plugin_manager,
                 :upload_plugin,
                 %{name: "foo", binary: "bar"},
                 caller_scopes: ["player"]
               )
    end
  end
end
