defmodule Exoforge.Plugin do
  @moduledoc "Public DSL for creating Exoforge plugins."

  defmacro __using__(_opts) do
    quote do
      @behaviour Exoforge.Contracts.Plugin
      import Exoforge.Plugin, only: [defaction: 2, defevent: 2]
      Module.register_attribute(__MODULE__, :exo_actions, accumulate: true)
      Module.register_attribute(__MODULE__, :exo_events, accumulate: true)
      Module.register_attribute(__MODULE__, :has_custom_init, accumulate: false)

      @before_compile Exoforge.Plugin
    end
  end

  defmacro defaction({name, _meta, args}, do: block) do
    quote do
      @exo_actions unquote(name)
      def unquote(name)(unquote_splicing(args)), do: unquote(block)
    end
  end

  defmacro defevent({name, _meta, args}, do: block) do
    quote do
      @exo_events unquote(name)
      def unquote(name)(unquote_splicing(args)), do: unquote(block)
    end
  end

  defmacro on_init({_name, _meta, [manifest_arg]}, do: block) do
    quote do
      @has_custom_init true
      def __custom_init(unquote(manifest_arg)) do
        unquote(block)
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def __custom_init(_manifest), do: :ok

      @impl Exoforge.Contracts.Plugin
      def init(manifest) do
        __custom_init(manifest)

        {:ok,
         %{
           plugin: __MODULE__,
           actions: @exo_actions,
           events: @exo_events
         }}
      end

      def manifest do
        Exoforge.PluginRegistry.fetch_manifest(__MODULE__)
      end
    end
  end
end
