defmodule Exoforge.Std.DashboardViews.PluginUploadTest do
  use ExUnit.Case, async: true

  alias Exoforge.Std.DashboardViews.PluginUpload

  @empty_form %{
    "name" => "",
    "type" => "wasm",
    "binary" => "",
    "elixir_code" => "",
    "manifest_json" => ""
  }

  describe "plugin_name_from/1" do
    test "derives the id the CLI and scaffolder would use" do
      assert PluginUpload.plugin_name_from("guild_system.wasm") == "guild_system"
      assert PluginUpload.plugin_name_from("GuildSystem.exs") == "guild_system"
      assert PluginUpload.plugin_name_from("My Cool Plugin!.wasm") == "my_cool_plugin"
    end
  end

  describe "form_with_file/3" do
    test "a .wasm file becomes a binary upload" do
      form = PluginUpload.form_with_file(@empty_form, "guild.wasm", "QUJD")

      assert form["type"] == "wasm"
      assert form["binary"] == "QUJD"
      assert form["name"] == "guild"
    end

    test "Elixir source is decoded, not kept as base64" do
      form = PluginUpload.form_with_file(@empty_form, "GuildSystem.exs", Base.encode64("defmodule Guild do end"))

      assert form["type"] == "elixir"
      assert form["elixir_code"] == "defmodule Guild do end"
      assert form["name"] == "guild_system"
    end

    test "a name the user already typed is kept" do
      form = PluginUpload.form_with_file(%{@empty_form | "name" => "chosen"}, "other.wasm", "QUJD")

      assert form["name"] == "chosen"
    end

    test "undecodable base64 yields empty source rather than raising" do
      form = PluginUpload.form_with_file(@empty_form, "x.ex", "!!!not base64!!!")

      assert form["elixir_code"] == ""
    end
  end

  describe "payload/2" do
    test "builds a binary upload from submitted params" do
      assert {:ok, payload} =
               PluginUpload.payload(
                 %{"name" => "guild", "type" => "wasm", "binary" => "QUJD"},
                 @empty_form
               )

      assert payload == %{name: "guild", type: "wasm", binary: "QUJD", manifest: nil}
    end

    test "builds an Elixir upload" do
      assert {:ok, payload} =
               PluginUpload.payload(
                 %{"name" => "guild", "type" => "elixir", "elixir_code" => "defmodule G do end"},
                 @empty_form
               )

      assert payload[:elixir_code] == "defmodule G do end"
      refute Map.has_key?(payload, :binary)
    end

    test "falls back to the form when a dropped file populated state, not an input" do
      form = %{@empty_form | "name" => "dropped", "binary" => "QUJD"}

      assert {:ok, payload} = PluginUpload.payload(%{"type" => "wasm"}, form)
      assert payload.name == "dropped"
      assert payload.binary == "QUJD"
    end

    test "decodes a manifest when one was supplied" do
      assert {:ok, payload} =
               PluginUpload.payload(
                 %{"name" => "g", "binary" => "x", "manifest_json" => ~s({"id": "g"})},
                 @empty_form
               )

      assert payload.manifest == %{"id" => "g"}
    end

    test "an unparseable manifest is dropped rather than failing the upload" do
      assert {:ok, payload} =
               PluginUpload.payload(
                 %{"name" => "g", "binary" => "x", "manifest_json" => "not json"},
                 @empty_form
               )

      assert payload.manifest == nil
    end

    test "reports what is missing" do
      assert {:error, message} = PluginUpload.payload(%{}, @empty_form)
      assert message =~ "name"

      assert {:error, message} =
               PluginUpload.payload(%{"name" => "g", "type" => "wasm"}, @empty_form)

      assert message =~ "binary"

      assert {:error, message} =
               PluginUpload.payload(%{"name" => "g", "type" => "elixir"}, @empty_form)

      assert message =~ "Elixir"
    end

    test "a name of only whitespace counts as missing" do
      assert {:error, _} = PluginUpload.payload(%{"name" => "   ", "binary" => "x"}, @empty_form)
    end
  end
end
