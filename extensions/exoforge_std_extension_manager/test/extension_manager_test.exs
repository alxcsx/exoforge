defmodule Exoforge.Std.ExtensionManagerTest do
  use ExUnit.Case, async: false

  alias Exoforge.ActionDispatcher
  alias Exoforge.ExtensionRegistry

  setup do
    Exoforge.ExtensionCase.start_kernel()

    Exoforge.ExtensionCase.register_extension(TestEntryPoint,
      id: :test_game_extension,
      name: "TestGameExtension",
      version: Version.parse!("1.0.0"),
      type: :elixir,
      provides: [:test_game_service]
    )

    # Registered so ActionDispatcher can route to it.
    Exoforge.ExtensionCase.register_extension(Exoforge.Std.ExtensionManager,
      id: :exoforge_std_extension_manager,
      name: "ExoforgeStdExtensionManager",
      version: Version.parse!("0.1.0"),
      type: :elixir,
      provides: [:extension_manager]
    )

    on_exit(fn ->
      # Clean up test directories if created
      File.rm_rf("extensions_csharp/test_uploaded_binary")
      File.rm_rf("extensions_csharp/invalid_test_binary")
      File.rm_rf("extensions/test_uploaded_elixir")
      File.rm_rf("priv/data/uploaded_extensions/test_uploaded_binary")
      File.rm_rf("priv/data/uploaded_extensions/test_uploaded_elixir")
    end)

    :ok
  end

  describe "Extension Manager Service Actions" do
    test "list_extensions returns all registered extensions and count with icon and title" do
      assert {:ok, result} =
               ActionDispatcher.dispatch(:extension_manager, :list_extensions, %{}, caller_scopes: ["studio"])

      assert is_list(result.extensions)
      assert result.count >= 2
      assert Enum.any?(result.extensions, &(&1["id"] == "test_game_extension"))

      em = Enum.find(result.extensions, &(&1["id"] == "exoforge_std_extension_manager"))
      assert em != nil
      assert em["icon"] == "⚙️"
      assert em["title"] == "Extension Manager"
    end

    test "export_extension_info returns extensions with icon and title" do
      assert {:ok, result} =
               ActionDispatcher.dispatch(:extension_manager, :export_extension_info, %{}, caller_scopes: ["studio"])

      assert is_map(result.export)
      assert is_list(result.export["extensions"])

      em = Enum.find(result.export["extensions"], &(&1["id"] == "exoforge_std_extension_manager"))
      assert em != nil
      assert em["icon"] == "⚙️"
      assert em["title"] == "Extension Manager"
    end

    test "csharp_attributes and export_extension_info include companion C# files" do
      assert {:ok, result} =
               ActionDispatcher.dispatch_internal(:extension_manager, :csharp_attributes, %{})

      assert is_list(result.files)
      cron_attr = Enum.find(result.files, &(&1["filename"] == "ExoCronAttribute.cs"))
      assert cron_attr != nil
      assert cron_attr["content"] =~ "ExoCronAttribute"

      assert {:ok, exp_res} =
               ActionDispatcher.dispatch(:extension_manager, :export_extension_info, %{}, caller_scopes: ["studio"])

      exp_attrs = exp_res.export["csharp_attributes"]
      assert is_list(exp_attrs)
      assert Enum.any?(exp_attrs, &(&1["filename"] == "ExoCronAttribute.cs"))
    end

    test "get_extension returns metadata for known extension" do
      assert {:ok, result} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :get_extension,
                 %{id: "test_game_extension"},
                 caller_scopes: ["studio"]
               )

      assert result.extension["id"] == "test_game_extension"
      assert result.extension["name"] == "TestGameExtension"
      assert result.extension["type"] == "elixir"
      assert "test_game_service" in result.extension["provides"]
    end

    test "get_extension returns :not_found for unknown extension" do
      assert {:error, :not_found} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :get_extension,
                 %{id: "nonexistent_extension"},
                 caller_scopes: ["studio"]
               )
    end

    test "get_system_info returns BEAM runtime and cluster statistics" do
      assert {:ok, result} =
               ActionDispatcher.dispatch(:extension_manager, :get_system_info, %{}, caller_scopes: ["studio"])

      sys = result.system
      assert is_binary(sys["node"])
      assert is_integer(sys["uptime_seconds"])
      assert is_integer(sys["memory_bytes"])
      assert sys["extensions_count"] >= 2
      assert is_binary(sys["elixir_version"])
      assert is_binary(sys["otp_release"])
      assert is_binary(sys["title_id"])
      assert is_binary(sys["studio_id"])
      assert is_binary(sys["project_name"])
      assert is_binary(sys["studio_name"])
      assert is_binary(sys["target_rid"])
      assert is_binary(sys["os"])
      assert is_binary(sys["arch"])
    end

    test "get_system_info respects EXOFORGE_TARGET_RID environment override" do
      prev = System.get_env("EXOFORGE_TARGET_RID")
      on_exit(fn ->
        if prev, do: System.put_env("EXOFORGE_TARGET_RID", prev), else: System.delete_env("EXOFORGE_TARGET_RID")
      end)

      System.put_env("EXOFORGE_TARGET_RID", "linux-musl-x64")
      assert {:ok, result} =
               ActionDispatcher.dispatch(:extension_manager, :get_system_info, %{}, caller_scopes: ["studio"])
      assert result.system["target_rid"] == "linux-musl-x64"
    end

    test "upload_extension rejects a binary that is not an extension" do
      bad_binary = "This is not an extension binary at all"

      assert {:error, :invalid_package} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :upload_extension,
                 %{name: "invalid_test_binary", binary: bad_binary},
                 caller_scopes: ["admin"]
               )
    end

    test "upload_extension accepts valid Elixir extension code, persists, compiles, and registers it" do
      elixir_code = """
      defmodule TestUploadedElixir do
        use Exoforge.Extension, provides: [:test_uploaded_elixir]

        defaction ping(payload) do
          {:ok, %{pong: payload}}
        end
      end
      """

      manifest_content = """
      {
        "id": "test_uploaded_elixir",
        "version": "0.1.0",
        "type": "elixir",
        "entry_point": "Elixir.TestUploadedElixir",
        "provides": ["test_uploaded_elixir"],
        "dependencies": []
      }
      """

      assert {:ok, result} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :upload_extension,
                 %{
                   name: "test_uploaded_elixir",
                   type: "elixir",
                   elixir_code: elixir_code,
                   manifest: manifest_content
                 },
                 caller_scopes: ["admin"]
               )

      assert result.extension_id == "test_uploaded_elixir"
      assert result.type == "elixir"

      target_dir = "priv/data/uploaded_extensions/test_uploaded_elixir"
      assert File.exists?(Path.join([target_dir, "lib", "test_uploaded_elixir.ex"]))
      assert File.exists?(Path.join(target_dir, "manifest.json"))

      assert {:ok, extension_info} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :get_extension,
                 %{id: "test_uploaded_elixir"},
                 caller_scopes: ["studio"]
               )

      assert extension_info.extension["type"] == "elixir"
      assert extension_info.extension["size_bytes"] > 0

      # Remove extension with delete_files
      assert {:ok, rem_res} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :remove_extension,
                 %{id: "test_uploaded_elixir", delete_files: true},
                 caller_scopes: ["admin"]
               )

      assert rem_res.status == "removed"
      assert rem_res.type == "elixir"
      refute File.exists?(target_dir)
    end

    test "remove_extension unregisters extension from registry" do
      assert {:ok, result} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :remove_extension,
                 %{id: "test_game_extension"},
                 caller_scopes: ["admin"]
               )

      assert result.status == "removed"
      assert ExtensionRegistry.fetch_manifest(:test_game_extension) == nil
    end

    test "remove_extension returns :not_found for unknown extension" do
      assert {:error, :not_found} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :remove_extension,
                 %{id: "unknown_remove_xyz"},
                 caller_scopes: ["admin"]
               )
    end

    test "scope authorization enforces admin scope on mutating actions" do
      assert {:error, :forbidden_scope} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :remove_extension,
                 %{id: "test_game_extension"},
                 caller_scopes: ["player"]
               )

      assert {:error, :forbidden_scope} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :upload_extension,
                 %{name: "foo", binary: "bar"},
                 caller_scopes: ["player"]
               )
    end
  end
end
