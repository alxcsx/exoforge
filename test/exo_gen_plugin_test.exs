defmodule Mix.Tasks.Exo.Gen.PluginTest do
  use ExUnit.Case, async: false

  @tmp_elixir_plugin "plugins/sample_scaffold_test"
  @tmp_csharp_plugin "plugins_csharp/sample_csharp_scaffold_test"

  setup do
    File.rm_rf!(@tmp_elixir_plugin)
    File.rm_rf!(@tmp_csharp_plugin)

    on_exit(fn ->
      File.rm_rf!(@tmp_elixir_plugin)
      File.rm_rf!(@tmp_csharp_plugin)
    end)

    :ok
  end

  test "scaffolds Elixir plugin with contracts and manifests" do
    Mix.Tasks.Exo.Gen.Plugin.run(["sample_scaffold_test"])

    assert File.dir?(@tmp_elixir_plugin)
    assert File.exists?(Path.join(@tmp_elixir_plugin, "mix.exs"))
    assert File.exists?(Path.join(@tmp_elixir_plugin, "manifest.exs"))
    assert File.exists?(Path.join([@tmp_elixir_plugin, "lib", "sample_scaffold_test.ex"]))
    assert File.exists?(Path.join([@tmp_elixir_plugin, "lib", "exoforge", "services", "sample_scaffold_test.ex"]))
    assert File.exists?(Path.join([@tmp_elixir_plugin, "test", "sample_scaffold_test_test.exs"]))

    # Verify manifest content
    content = File.read!(Path.join(@tmp_elixir_plugin, "manifest.exs"))
    assert content =~ ":sample_scaffold_test"
    assert content =~ "SampleScaffoldTest"
  end

  test "scaffolds C# WASM plugin with csproj and build.sh" do
    Mix.Tasks.Exo.Gen.Plugin.run(["sample_csharp_scaffold_test", "--lang", "csharp"])

    assert File.dir?(@tmp_csharp_plugin)
    assert File.exists?(Path.join(@tmp_csharp_plugin, "sample_csharp_scaffold_test.csproj"))
    assert File.exists?(Path.join(@tmp_csharp_plugin, "SampleCsharpScaffoldTest.cs"))
    assert File.exists?(Path.join(@tmp_csharp_plugin, "build.sh"))
    assert File.exists?(Path.join(@tmp_csharp_plugin, "README.md"))

    content = File.read!(Path.join(@tmp_csharp_plugin, "SampleCsharpScaffoldTest.cs"))
    assert content =~ "ExoService(\"sample_csharp_scaffold_test\")"
    assert content =~ "class SampleCsharpScaffoldTest : PluginBehaviour"
  end
end
