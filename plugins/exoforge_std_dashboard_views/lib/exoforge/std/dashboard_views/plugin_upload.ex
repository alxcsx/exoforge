defmodule Exoforge.Std.DashboardViews.PluginUpload do
  @moduledoc """
  Turns the Studio's plugin upload form into an upload payload.

  The form accepts a dropped file, pasted binary content, or Elixir source. Working out which one
  it is, deriving a plugin id from the filename, and deciding whether the form is complete is pure
  logic — so it lives here instead of inside a LiveView handler, where the only way to exercise it
  was to drive the UI.
  """

  @elixir_extensions [".ex", ".exs"]

  @doc """
  The upload form after a file was dropped on it.

  A `.ex`/`.exs` file becomes Elixir source; anything else is treated as a binary. An id already
  typed by the user is kept — dropping a file should not rename what they just wrote.
  """
  def form_with_file(form, filename, base64) do
    type = if elixir_source?(filename), do: "elixir", else: "wasm"

    content_key = if type == "elixir", do: "elixir_code", else: "binary"
    content = if type == "elixir", do: decode_base64(base64), else: base64

    name = if blank?(form["name"]), do: plugin_name_from(filename), else: form["name"]

    form
    |> Map.put("type", type)
    |> Map.put(content_key, content)
    |> Map.put("name", name)
  end

  @doc """
  Derives a plugin id from an uploaded filename: `GuildSystem.exs` → `guildsystem`.

  Matches the naming the CLI and scaffolder use, so an uploaded plugin is addressable by the id a
  developer expects.
  """
  def plugin_name_from(filename) do
    filename
    |> Path.rootname(Path.extname(filename))
    |> Macro.underscore()
    |> String.replace(~r/[^a-z0-9_]/, "")
  end

  @doc "True when the filename is Elixir source rather than a compiled plugin."
  def elixir_source?(filename), do: Path.extname(filename) in @elixir_extensions

  @doc """
  Builds the payload for `plugin_manager.upload_plugin`, or explains what the form is missing.

  `params` are the submitted form fields; `form` is the current state, used as a fallback for
  fields the browser did not send (a dropped file populates state without a matching input).
  """
  def payload(params, form) do
    name = fetch(params, form, "name")
    type = fetch(params, form, "type", "wasm")

    case validate(name, type, fetch(params, form, "binary"), fetch(params, form, "elixir_code")) do
      {:error, message} ->
        {:error, message}

      :ok ->
        {:ok,
         %{
           name: name,
           type: type,
           manifest: decode_manifest(fetch(params, form, "manifest_json"))
         }
         |> put_content(type, fetch(params, form, "binary"), fetch(params, form, "elixir_code"))}
    end
  end

  # ---- internals ---------------------------------------------------------------------

  defp validate("", _type, _binary, _code), do: {:error, "Plugin name is required."}

  defp validate(_name, "elixir", _binary, ""),
    do: {:error, "Elixir module code is required."}

  defp validate(_name, "wasm", "", _code),
    do: {:error, "WASM binary content or file is required."}

  defp validate(_name, _type, _binary, _code), do: :ok

  defp put_content(payload, "elixir", _binary, code), do: Map.put(payload, :elixir_code, code)
  defp put_content(payload, _type, binary, _code), do: Map.put(payload, :binary, binary)

  defp decode_manifest(""), do: nil

  defp decode_manifest(raw) do
    case Jason.decode(raw) do
      {:ok, parsed} -> parsed
      _ -> nil
    end
  end

  defp fetch(params, form, key, default \\ "") do
    params
    |> Map.get(key, form[key] || default)
    |> to_string()
    |> String.trim()
  end

  defp decode_base64(base64) do
    case Base.decode64(base64) do
      {:ok, text} -> text
      _ -> ""
    end
  end

  defp blank?(value), do: value in [nil, ""]
end
