defmodule Exoforge.Contracts.Services do
  @moduledoc "Registry of built-in Exoforge service contracts."
  import Exoforge.Contracts.Service

  defservice database do
    @moduledoc "General database service."

    @doc "Executes a driver-agnostic query or data operation."
    action :execute do
      params(operation: :string, arguments: :map)
      returns(rows: [:map])
      errors([:syntax_error, :not_found, :unauthorized])
    end
  end

  defservice lldb do
    @moduledoc "Low-level database connection."

    @doc "Retrieves namespaced database connection details."
    action :connection_config do
      params(namespace: [type: :string, optional: true])

      returns(
        url: :string,
        pool_size: :integer,
        driver: :atom
      )
    end

    @doc "Performs a low-level ping to verify the database is reachable."
    action :health_check do
      returns(status: :string)
      errors([:unreachable, :timeout])
    end

    @doc "Fired when the underlying database pool drops connection."
    event :connection_lost do
      payload(reason: :string, timestamp: :integer)
      scope(:server)
    end
  end
end
