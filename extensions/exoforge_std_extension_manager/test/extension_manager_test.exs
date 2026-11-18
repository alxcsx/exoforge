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
      assert {:error, {:forbidden_scope, _}} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :remove_extension,
                 %{id: "test_game_extension"},
                 caller_scopes: ["player"]
               )

      assert {:error, {:forbidden_scope, _}} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :upload_extension,
                 %{name: "foo", binary: "bar"},
                 caller_scopes: ["player"]
               )
    end
  end

  defmodule StubResourceStore do
    use Exoforge.Extension, provides: [:resource_store]

    @impl true
    defaction migrate(payload) do
      extension = Map.get(payload, :extension) || Map.get(payload, "extension")

      resources =
        ExtensionRegistry.all_resources()
        |> Enum.filter(fn info ->
          extension == nil or to_string(info.extension_id) == to_string(extension)
        end)

      Enum.reduce_while(resources, {:ok, %{migrated: 0}}, fn info, {:ok, %{migrated: count}} ->
        res = info.resource
        cols = res.columns || []
        names = Enum.map(cols, &String.downcase(to_string(&1[:name] || &1["name"] || "")))

        if Enum.uniq(names) != names do
          {:halt,
           {:error,
            {:invalid_resource,
             %{extension: info.extension_id, table: to_string(res.name), column: List.first(names), reason: :duplicate_column}}}}
        else
          if to_string(res.name) == "fail_migration_table" do
            {:halt, {:error, :simulated_ddl_failure}}
          else
            {:cont, {:ok, %{migrated: count + 1}}}
          end
        end
      end)
    end
  end

  describe "Scoped extension migrations and redeploy rollback" do
    setup do
      Exoforge.ExtensionCase.register_extension(StubResourceStore,
        id: :test_resource_store,
        name: "TestResourceStore",
        version: Version.parse!("0.1.0"),
        type: :elixir,
        provides: [:resource_store]
      )

      on_exit(fn ->
        File.rm_rf("priv/data/uploaded_extensions/ext_a_broken")
        File.rm_rf("priv/data/uploaded_extensions/ext_b_healthy")
        File.rm_rf("priv/data/uploaded_extensions/ext_redeploy_roll")
        File.rm_rf("priv/data/uploaded_extensions/ext_redeploy_mig_fail")
        File.rm_rf("priv/data/uploaded_extensions/ext_redeploy_boot_fail")
        File.rm_rf("priv/data/uploaded_extensions/ext_redeploy_empty_manifest")
        File.rm_rf("priv/data/uploaded_extensions/ext_concurrent_push")

        if :ets.whereis(:exo_extensions_mem) != :undefined do
          ExtensionRegistry.unregister(:ext_a_broken)
          ExtensionRegistry.unregister(:ext_b_healthy)
          ExtensionRegistry.unregister(:ext_redeploy_roll)
          ExtensionRegistry.unregister(:ext_redeploy_mig_fail)
          ExtensionRegistry.unregister(:ext_redeploy_boot_fail)
          ExtensionRegistry.unregister(:ext_redeploy_empty_manifest)
          ExtensionRegistry.unregister(:ext_concurrent_push)
          ExtensionRegistry.unregister(:test_resource_store)
        end
      end)

      :ok
    end

    test "broken resource in extension A does not block pushing extension B" do
      ExtensionRegistry.register(%Exoforge.Domain.Manifest{
        id: :ext_a_broken,
        name: "ExtABroken",
        version: Version.parse!("0.1.0"),
        entry_point: "ext_a_broken",
        type: :native,
        services: [
          %{
            name: :ext_a_broken,
            resources: [
              %{
                name: :broken_table,
                primary_key: :id,
                columns: [
                  %{name: :id, type: :string},
                  %{name: :Id, type: :string}
                ]
              }
            ]
          }
        ]
      })

      manifest_b = """
      {
        "id": "ext_b_healthy",
        "version": "0.1.0",
        "type": "elixir",
        "entry_point": "Elixir.ExtBHealthy",
        "provides": ["ext_b_healthy"],
        "services": [
          {
            "name": "ext_b_healthy",
            "resources": [
              {
                "name": "healthy_table",
                "primary_key": "id",
                "columns": [{"name": "id", "type": "string"}]
              }
            ]
          }
        ]
      }
      """

      elixir_b = """
      defmodule ExtBHealthy do
        use Exoforge.Extension, provides: [:ext_b_healthy]
        defaction ping(_p), do: {:ok, %{ok: true}}
      end
      """

      assert {:ok, %{extension_id: "ext_b_healthy", status: "installed"}} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :upload_extension,
                 %{name: "ext_b_healthy", type: "elixir", elixir_code: elixir_b, manifest: manifest_b},
                 caller_scopes: ["admin"]
               )
    end

    test "migration error names extension and table, and failed redeploy keeps previous version registered" do
      elixir_v1 = """
      defmodule ExtRedeployRoll do
        use Exoforge.Extension, provides: [:ext_redeploy_roll]
        defaction version(_p), do: {:ok, %{v: 1}}
      end
      """

      manifest_v1 = """
      {
        "id": "ext_redeploy_roll",
        "version": "1.0.0",
        "type": "elixir",
        "entry_point": "Elixir.ExtRedeployRoll",
        "provides": ["ext_redeploy_roll"],
        "services": [
          {
            "name": "ext_redeploy_roll",
            "resources": [
              {
                "name": "roll_table",
                "primary_key": "id",
                "columns": [{"name": "id", "type": "string"}]
              }
            ]
          }
        ]
      }
      """

      assert {:ok, %{extension_id: "ext_redeploy_roll"}} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :upload_extension,
                 %{name: "ext_redeploy_roll", type: "elixir", elixir_code: elixir_v1, manifest: manifest_v1},
                 caller_scopes: ["admin"]
               )

      assert %{version: v1} = ExtensionRegistry.fetch_manifest(:ext_redeploy_roll)
      assert to_string(v1) == "1.0.0"

      manifest_v2_bad = """
      {
        "id": "ext_redeploy_roll",
        "version": "2.0.0",
        "type": "elixir",
        "entry_point": "Elixir.ExtRedeployRoll",
        "provides": ["ext_redeploy_roll"],
        "services": [
          {
            "name": "ext_redeploy_roll",
            "resources": [
              {
                "name": "roll_table",
                "primary_key": "id",
                "columns": [
                  {"name": "id", "type": "string"},
                  {"name": "Id", "type": "string"}
                ]
              }
            ]
          }
        ]
      }
      """

      assert {:error,
              {:migration_failed,
               {:invalid_resource, %{extension: :ext_redeploy_roll, table: "roll_table", reason: :duplicate_column}}}} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :upload_extension,
                 %{name: "ext_redeploy_roll", type: "elixir", elixir_code: elixir_v1, manifest: manifest_v2_bad},
                 caller_scopes: ["admin"]
               )

      assert %{version: current_version} = ExtensionRegistry.fetch_manifest(:ext_redeploy_roll)
      assert to_string(current_version) == "1.0.0"
      assert {:ok, %{v: 1}} = ActionDispatcher.dispatch_internal(:ext_redeploy_roll, :version, %{})
    end

    test "redeploy whose migration fails restores previous files on disk and keeps previous version running" do
      elixir_v1 = """
      defmodule ExtRedeployMigFail do
        use Exoforge.Extension, provides: [:ext_redeploy_mig_fail]
        defaction version(_p), do: {:ok, %{v: 1}}
      end
      """

      manifest_v1 = """
      {
        "id": "ext_redeploy_mig_fail",
        "version": "1.0.0",
        "type": "elixir",
        "entry_point": "Elixir.ExtRedeployMigFail",
        "provides": ["ext_redeploy_mig_fail"],
        "services": [
          {
            "name": "ext_redeploy_mig_fail",
            "resources": [
              {
                "name": "ok_table",
                "primary_key": "id",
                "columns": [{"name": "id", "type": "string"}]
              }
            ]
          }
        ]
      }
      """

      assert {:ok, %{extension_id: "ext_redeploy_mig_fail"}} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :upload_extension,
                 %{name: "ext_redeploy_mig_fail", type: "elixir", elixir_code: elixir_v1, manifest: manifest_v1},
                 caller_scopes: ["admin"]
               )

      elixir_v2 = """
      defmodule ExtRedeployMigFail do
        use Exoforge.Extension, provides: [:ext_redeploy_mig_fail]
        defaction version(_p), do: {:ok, %{v: 2}}
      end
      """

      manifest_v2_fail = """
      {
        "id": "ext_redeploy_mig_fail",
        "version": "2.0.0",
        "type": "elixir",
        "entry_point": "Elixir.ExtRedeployMigFail",
        "provides": ["ext_redeploy_mig_fail"],
        "services": [
          {
            "name": "ext_redeploy_mig_fail",
            "resources": [
              {
                "name": "fail_migration_table",
                "primary_key": "id",
                "columns": [{"name": "id", "type": "string"}]
              }
            ]
          }
        ]
      }
      """

      assert {:error, %{error: {:migration_failed, :simulated_ddl_failure}, rollback: :restored}} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :upload_extension,
                 %{name: "ext_redeploy_mig_fail", type: "elixir", elixir_code: elixir_v2, manifest: manifest_v2_fail},
                 caller_scopes: ["admin"]
               )

      assert %{version: current_version} = ExtensionRegistry.fetch_manifest(:ext_redeploy_mig_fail)
      assert to_string(current_version) == "1.0.0"
      assert {:ok, %{v: 1}} = ActionDispatcher.dispatch_internal(:ext_redeploy_mig_fail, :version, %{})

      disk_manifest =
        "priv/data/uploaded_extensions/ext_redeploy_mig_fail/manifest.json"
        |> File.read!()
        |> Jason.decode!()

      assert disk_manifest["version"] == "1.0.0"
      assert File.read!("priv/data/uploaded_extensions/ext_redeploy_mig_fail/lib/ext_redeploy_mig_fail.ex") =~ "v: 1"
      assert Path.wildcard("priv/data/uploaded_extensions/ext_redeploy_mig_fail.bak.*") == []
    end

    test "redeploy whose new boot fails restores previous files on disk and keeps previous version running" do
      elixir_v1 = """
      defmodule ExtRedeployBootFail do
        use Exoforge.Extension, provides: [:ext_redeploy_boot_fail]
        defaction version(_p), do: {:ok, %{v: 1}}
      end
      """

      manifest_v1 = """
      {
        "id": "ext_redeploy_boot_fail",
        "version": "1.0.0",
        "type": "elixir",
        "entry_point": "Elixir.ExtRedeployBootFail",
        "provides": ["ext_redeploy_boot_fail"]
      }
      """

      assert {:ok, %{extension_id: "ext_redeploy_boot_fail"}} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :upload_extension,
                 %{name: "ext_redeploy_boot_fail", type: "elixir", elixir_code: elixir_v1, manifest: manifest_v1},
                 caller_scopes: ["admin"]
               )

      elixir_v2_crash = """
      defmodule ExtRedeployBootFail do
        use Exoforge.Extension, provides: [:ext_redeploy_boot_fail]
        def on_init(_manifest), do: {:error, :boot_boom}
        defaction version(_p), do: {:ok, %{v: 2}}
      end
      """

      manifest_v2 = """
      {
        "id": "ext_redeploy_boot_fail",
        "version": "2.0.0",
        "type": "elixir",
        "entry_point": "Elixir.ExtRedeployBootFail",
        "provides": ["ext_redeploy_boot_fail"]
      }
      """

      assert {:error, %{error: {:boot_failed, _reason}, rollback: :restored}} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :upload_extension,
                 %{name: "ext_redeploy_boot_fail", type: "elixir", elixir_code: elixir_v2_crash, manifest: manifest_v2},
                 caller_scopes: ["admin"]
               )

      assert %{version: current_version} = ExtensionRegistry.fetch_manifest(:ext_redeploy_boot_fail)
      assert to_string(current_version) == "1.0.0"
      assert {:ok, %{v: 1}} = ActionDispatcher.dispatch_internal(:ext_redeploy_boot_fail, :version, %{})

      disk_manifest =
        "priv/data/uploaded_extensions/ext_redeploy_boot_fail/manifest.json"
        |> File.read!()
        |> Jason.decode!()

      assert disk_manifest["version"] == "1.0.0"
      assert File.read!("priv/data/uploaded_extensions/ext_redeploy_boot_fail/lib/ext_redeploy_boot_fail.ex") =~ "v: 1"
      assert Path.wildcard("priv/data/uploaded_extensions/ext_redeploy_boot_fail.bak.*") == []
    end

    test "redeploy whose manifest fails to load ([]) restores previous version and backup" do
      elixir_v1 = """
      defmodule ExtRedeployEmptyManifest do
        use Exoforge.Extension, provides: [:ext_redeploy_empty_manifest]
        defaction version(_p), do: {:ok, %{v: 1}}
      end
      """

      manifest_v1 = """
      {
        "id": "ext_redeploy_empty_manifest",
        "version": "1.0.0",
        "type": "elixir",
        "entry_point": "Elixir.ExtRedeployEmptyManifest",
        "provides": ["ext_redeploy_empty_manifest"]
      }
      """

      assert {:ok, %{extension_id: "ext_redeploy_empty_manifest"}} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :upload_extension,
                 %{name: "ext_redeploy_empty_manifest", type: "elixir", elixir_code: elixir_v1, manifest: manifest_v1},
                 caller_scopes: ["admin"]
               )

      elixir_v2 = """
      defmodule ExtRedeployEmptyManifest do
        use Exoforge.Extension, provides: [:ext_redeploy_empty_manifest]
        defaction version(_p), do: {:ok, %{v: 2}}
      end
      """

      # "{}" causes ManifestLoader.load_extensions/1 to return []
      assert {:error, %{error: :manifest_not_loaded, rollback: :restored}} =
               ActionDispatcher.dispatch(
                 :extension_manager,
                 :upload_extension,
                 %{name: "ext_redeploy_empty_manifest", type: "elixir", elixir_code: elixir_v2, manifest: "{}"},
                 caller_scopes: ["admin"]
               )

      assert %{version: current_version} = ExtensionRegistry.fetch_manifest(:ext_redeploy_empty_manifest)
      assert to_string(current_version) == "1.0.0"
      assert {:ok, %{v: 1}} = ActionDispatcher.dispatch_internal(:ext_redeploy_empty_manifest, :version, %{})
      assert Path.wildcard("priv/data/uploaded_extensions/ext_redeploy_empty_manifest.bak.*") == []
    end

    test "two concurrent pushes of the same extension serialize cleanly without stale restore" do
      push = fn ver, v_num ->
        code = """
        defmodule ExtConcurrentPush do
          use Exoforge.Extension, provides: [:ext_concurrent_push]
          defaction version(_p), do: {:ok, %{v: #{v_num}}}
        end
        """

        manifest = """
        {
          "id": "ext_concurrent_push",
          "version": "#{ver}",
          "type": "elixir",
          "entry_point": "Elixir.ExtConcurrentPush",
          "provides": ["ext_concurrent_push"]
        }
        """

        ActionDispatcher.dispatch(
          :extension_manager,
          :upload_extension,
          %{name: "ext_concurrent_push", type: "elixir", elixir_code: code, manifest: manifest},
          caller_scopes: ["admin"]
        )
      end

      t1 = Task.async(fn -> push.("1.0.0", 1) end)
      t2 = Task.async(fn -> push.("2.0.0", 2) end)

      assert {:ok, %{status: "installed"}} = Task.await(t1, 10_000)
      assert {:ok, %{status: "installed"}} = Task.await(t2, 10_000)

      # Both completed serially; the active manifest and disk version must agree (no stale restore).
      manifest = ExtensionRegistry.fetch_manifest(:ext_concurrent_push)
      assert manifest != nil
      disk_ver =
        "priv/data/uploaded_extensions/ext_concurrent_push/manifest.json"
        |> File.read!()
        |> Jason.decode!()
        |> Map.fetch!("version")

      assert to_string(manifest.version) == disk_ver
      assert Path.wildcard("priv/data/uploaded_extensions/ext_concurrent_push.bak.*") == []
    end
  end
end
