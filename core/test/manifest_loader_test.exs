defmodule Exoforge.Drivers.Loaders.ManifestLoaderTest do
  use ExUnit.Case, async: true

  alias Exoforge.Drivers.Loaders.ManifestLoader

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "manifest_loader_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  defp create_fake_ext(base_dir, ext_name, version) do
    ext_dir = Path.join(base_dir, ext_name)
    File.mkdir_p!(ext_dir)

    manifest_content = Jason.encode!(%{
      "id" => ext_name,
      "name" => ext_name,
      "version" => version,
      "entry_point" => "TestExt",
      "type" => "native"
    })

    File.write!(Path.join(ext_dir, "manifest.json"), manifest_content)
    ext_dir
  end

  test "loads extensions from a single path string", %{tmp_dir: tmp_dir} do
    create_fake_ext(tmp_dir, "my_ext", "1.0.0")

    manifests = ManifestLoader.load_extensions(tmp_dir)
    assert length(manifests) == 1
    assert hd(manifests).id == :my_ext
    assert to_string(hd(manifests).version) == "1.0.0"
  end

  test "loads extensions from a list of paths", %{tmp_dir: tmp_dir} do
    dir1 = Path.join(tmp_dir, "dir1")
    dir2 = Path.join(tmp_dir, "dir2")
    create_fake_ext(dir1, "ext_a", "1.0.0")
    create_fake_ext(dir2, "ext_b", "2.0.0")

    manifests = ManifestLoader.load_extensions([dir1, dir2])
    ids = Enum.map(manifests, & &1.id) |> Enum.sort()

    assert ids == [:ext_a, :ext_b]
  end

  test "loads extensions from a comma-separated path string", %{tmp_dir: tmp_dir} do
    dir1 = Path.join(tmp_dir, "dir1")
    dir2 = Path.join(tmp_dir, "dir2")
    create_fake_ext(dir1, "ext_a", "1.0.0")
    create_fake_ext(dir2, "ext_b", "2.0.0")

    manifests = ManifestLoader.load_extensions("#{dir1},#{dir2}")
    ids = Enum.map(manifests, & &1.id) |> Enum.sort()

    assert ids == [:ext_a, :ext_b]
  end

  test "loads extensions from a JSON array string", %{tmp_dir: tmp_dir} do
    dir1 = Path.join(tmp_dir, "dir1")
    dir2 = Path.join(tmp_dir, "dir2")
    create_fake_ext(dir1, "ext_a", "1.0.0")
    create_fake_ext(dir2, "ext_b", "2.0.0")

    json_paths = Jason.encode!([dir1, dir2])
    manifests = ManifestLoader.load_extensions(json_paths)
    ids = Enum.map(manifests, & &1.id) |> Enum.sort()

    assert ids == [:ext_a, :ext_b]
  end

  test "resolves duplicate extension IDs by keeping the higher version", %{tmp_dir: tmp_dir} do
    builtin = Path.join(tmp_dir, "builtin")
    uploaded = Path.join(tmp_dir, "uploaded")

    create_fake_ext(builtin, "ext_shared", "1.0.0")
    create_fake_ext(uploaded, "ext_shared", "1.2.0")

    manifests = ManifestLoader.load_extensions([builtin, uploaded])
    assert length(manifests) == 1
    ext = hd(manifests)
    assert ext.id == :ext_shared
    assert to_string(ext.version) == "1.2.0"
  end

  test "prefers later/uploaded extension when versions are identical", %{tmp_dir: tmp_dir} do
    builtin = Path.join(tmp_dir, "builtin")
    uploaded = Path.join(tmp_dir, "uploaded")

    _b_ext = create_fake_ext(builtin, "ext_shared", "1.0.0")
    u_ext = create_fake_ext(uploaded, "ext_shared", "1.0.0")

    manifests = ManifestLoader.load_extensions([builtin, uploaded])
    assert length(manifests) == 1
    ext = hd(manifests)
    assert ext.id == :ext_shared
    # The physical path should point to the uploaded extension
    assert ext.physical_path == u_ext
  end
end
