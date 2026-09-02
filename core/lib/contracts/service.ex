defmodule Exoforge.Contracts.Service do
  defmacro defservice(name, do: block) do
    service_alias = Macro.camelize(to_string(name))

    quote do
      contract_module = Module.concat([__MODULE__, unquote(service_alias)])

      defmodule contract_module do
        @moduledoc "Contract definition for the #{unquote(name)} service."
        unquote(block)
        def __service_name__, do: unquote(name)
      end
    end
  end
end
