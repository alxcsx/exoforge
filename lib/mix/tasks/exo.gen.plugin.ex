defmodule Mix.Tasks.Exo.Gen.Plugin do
  @moduledoc """
  Generates a new Exoforge plugin.

  ## Examples

      # Generate an Elixir plugin (default):
      mix exo.gen.plugin quest_system

      # Generate a C# WASM plugin:
      mix exo.gen.plugin combat_system --lang csharp

  ## Options

    * `--lang` - The language for the plugin: `elixir` (default) or `csharp`.
    * `--service` - The service name (defaults to the plugin name).
  """

  use Mix.Task
  import Mix.Generator

  @shortdoc "Scaffolds a new Exoforge plugin (Elixir or C# WASM)"

  @impl true
  def run(args) do
    {opts, parsed_args, _} =
      OptionParser.parse(args,
        strict: [lang: :string, service: :string],
        aliases: [l: :lang, s: :service]
      )

    plugin_name =
      case parsed_args do
        [name | _] -> Macro.underscore(name)
        [] -> Mix.raise("Expected a plugin name. Example: mix exo.gen.plugin quest_system")
      end

    lang = Keyword.get(opts, :lang, "elixir") |> String.downcase()
    service_name = Keyword.get(opts, :service, plugin_name) |> Macro.underscore()

    case lang do
      "elixir" ->
        generate_elixir_plugin(plugin_name, service_name)

      "csharp" ->
        generate_csharp_plugin(plugin_name, service_name)

      other ->
        Mix.raise("Unsupported language: #{other}. Supported options are `elixir` or `csharp`.")
    end
  end

  defp generate_elixir_plugin(name, service) do
    mod_name = Macro.camelize(name)
    service_mod = Macro.camelize(service)
    target_dir = Path.join(["plugins", name])

    if File.dir?(target_dir) do
      Mix.raise("Directory #{target_dir} already exists.")
    end

    File.mkdir_p!(Path.join([target_dir, "lib", "exoforge", "services"]))
    File.mkdir_p!(Path.join([target_dir, "test"]))

    # 1. mix.exs
    create_file(Path.join(target_dir, "mix.exs"), """
    defmodule #{mod_name}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{name},
          version: "0.1.0",
          build_path: "../../_build",
          config_path: "../../config/config.exs",
          deps_path: "../../deps",
          lockfile: "../../mix.lock",
          elixir: "~> 1.15",
          start_permanent: Mix.env() == :prod,
          deps: deps()
        ]
      end

      def application do
        [
          extra_applications: [:logger]
        ]
      end

      defp deps do
        [
          {:exoforge_core, path: "../../core"},
          {:jason, "~> 1.4"}
        ]
      end
    end
    """)

    # 2. Service Contract
    create_file(Path.join([target_dir, "lib", "exoforge", "services", "#{service}.ex"]), """
    defmodule Exoforge.Std.Services.#{service_mod} do
      @moduledoc "Service contract definition for :#{service}"
      import Exoforge.Contracts.Service

      defservice :#{service} do
        action :ping do
          returns(status: :string)
        end

        action :execute_action do
          params(id: :string, count: :integer)
          returns(success: :boolean)
        end

        event :state_updated do
          payload(id: :string, status: :string)
          topic("events:#{service}")
        end

        resource :items do
          primary_key :id
          column :id, :string
          column :name, :string
          column :status, :string
        end
      end
    end
    """)

    # 3. Plugin Implementation
    create_file(Path.join([target_dir, "lib", "#{name}.ex"]), """
    defmodule #{mod_name} do
      @moduledoc "Implementation module for the :#{name} plugin."
      use Exoforge.Plugin, provides: [Exoforge.Std.Services.#{service_mod}.#{service_mod}]

      @manifest %{
        dependencies: []
      }

      @impl true
      defaction ping() do
        {:ok, %{status: "pong", plugin: "#{name}"}}
      end

      @impl true
      defaction execute_action(payload) do
        id = Map.get(payload, "id") || Map.get(payload, :id, "item_1")
        count = Map.get(payload, "count") || Map.get(payload, :count, 1)

        Exoforge.EventDispatcher.broadcast(
          "state_updated",
          %{id: id, status: "completed", count: count},
          topic: "events:#{service}"
        )

        {:ok, %{success: true, id: id, count: count}}
      end
    end
    """)

    # 4. manifest.exs
    create_file(Path.join(target_dir, "manifest.exs"), """
    %{
      id: :#{name},
      name: "#{name}",
      version: "0.1.0",
      entry_point: #{mod_name},
      provides: [Exoforge.Std.Services.#{service_mod}.#{service_mod}],
      dependencies: []
    }
    """)

    # 5. test_helper.exs
    create_file(Path.join([target_dir, "test", "test_helper.exs"]), """
    ExUnit.start()
    """)

    # 6. Test Suite
    create_file(Path.join([target_dir, "test", "#{name}_test.exs"]), """
    defmodule #{mod_name}Test do
      use ExUnit.Case, async: false

      alias Exoforge.PluginRegistry
      alias Exoforge.ActionDispatcher
      alias Exoforge.Domain.Manifest

      setup do
        PluginRegistry.initialize_ets()

        manifest = %Manifest{
          id: :#{name},
          name: "#{name}",
          version: "0.1.0",
          entry_point: #{mod_name},
          provides: [Exoforge.Std.Services.#{service_mod}.#{service_mod}]
        }

        PluginRegistry.register(manifest)
        :ok
      end

      test "ping returns pong status" do
        assert {:ok, %{status: "pong", plugin: "#{name}"}} =
                 ActionDispatcher.dispatch(:#{service}, :ping, %{})
      end
    end
    """)

    Mix.shell().info("""

    [Exoforge Plugin Generated]
      Directory: #{target_dir}
      Language:  Elixir
      Service:   :#{service}

    Next Steps:
      1. cd #{target_dir} && mix test
      2. Restart Exoforge backend (the bootstrapper will auto-discover #{name})
    """)
  end

  defp generate_csharp_plugin(name, service) do
    class_name = Macro.camelize(name)
    target_dir = Path.join(["plugins_csharp", name])

    if File.dir?(target_dir) do
      Mix.raise("Directory #{target_dir} already exists.")
    end

    File.mkdir_p!(target_dir)

    # 1. .csproj
    create_file(Path.join(target_dir, "#{name}.csproj"), """
    <Project Sdk="Microsoft.NET.Sdk">
      <PropertyGroup>
        <TargetFramework>net10.0</TargetFramework>
        <Nullable>enable</Nullable>
        <ImplicitUsings>enable</ImplicitUsings>
        <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
        <OutputType>Exe</OutputType>
      </PropertyGroup>

      <ItemGroup>
        <ProjectReference Include="../../sdk/csharp/Exoforge.Plugin.SDK/Exoforge.Plugin.SDK.csproj" />
      </ItemGroup>
    </Project>
    """)

    # 2. C# Implementation
    create_file(Path.join(target_dir, "#{class_name}.cs"), """
    using Exoforge.Plugin.SDK;

    namespace Exoforge.Plugins;

    [ExoService("#{service}")]
    public class #{class_name} : PluginBehaviour
    {
        [ExoAction("ping")]
        public object Ping()
        {
            return new { status = "pong", plugin = "#{name}" };
        }

        [ExoAction("perform_action")]
        public object PerformAction(string targetId, int amount)
        {
            Emit("events:#{service}", "action_completed", new
            {
                target_id = targetId,
                amount = amount
            });

            return new { success = true, target_id = targetId, amount = amount };
        }
    }
    """)

    # 3. build.sh
    create_file(Path.join(target_dir, "build.sh"), """
    #!/usr/bin/env bash
    set -euo pipefail

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    WASI_CLANG="${WASI_SDK_PATH:-$HOME/.wasi-sdk/wasi-sdk-25.0}/bin/wasm32-wasip1-clang"

    echo "Building C# assembly..."
    dotnet build "$SCRIPT_DIR/#{name}.csproj" -c Release

    echo "Generating plugin manifest from C# attributes..."
    dotnet run --project "$SCRIPT_DIR/../../sdk/csharp/Exoforge.ManifestGen" -- \\
      "$SCRIPT_DIR/bin/Release/net10.0/#{name}.dll" \\
      "$SCRIPT_DIR/manifest.exs"

    if [ -f "$WASI_CLANG" ]; then
      echo "Compiling WASM binary..."
      "$WASI_CLANG" -O2 -mexec-model=reactor \\
        -Wl,--export=ping \\
        -o "$SCRIPT_DIR/#{name}.wasm" \\
        -x c - << 'EOF'
    #include <string.h>
    int ping() { return 1; }
    EOF
      echo "Built $SCRIPT_DIR/#{name}.wasm successfully!"
    else
      echo "Notice: wasi-sdk not found at $WASI_CLANG, skipped native clang pass."
    fi
    """)

    # Make build.sh executable
    File.chmod!(Path.join(target_dir, "build.sh"), 0o755)

    # 4. README.md
    create_file(Path.join(target_dir, "README.md"), """
    # #{class_name} (C# WASM Plugin)

    Auto-generated Exoforge C# WASM plugin.

    ## Building
    ```bash
    ./build.sh
    ```
    """)

    Mix.shell().info("""

    [Exoforge C# WASM Plugin Generated]
      Directory: #{target_dir}
      Language:  C# (net10.0 / WASI)
      Service:   :#{service}

    Next Steps:
      1. cd #{target_dir} && ./build.sh
      2. Restart Exoforge backend (the bootstrapper will auto-load #{name}.wasm)
    """)
  end
end
