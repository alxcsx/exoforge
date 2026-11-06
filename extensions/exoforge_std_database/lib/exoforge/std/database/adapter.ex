defmodule Exoforge.Std.Database.Adapter do
  @moduledoc """
  Behaviour defining operations for Exoforge database drivers.
  Every adapter must enforce strict per-plugin database isolation.
  """

  @type plugin_id :: atom() | String.t()
  @type table_name :: String.t()
  @type query :: String.t() | map()
  @type args :: list() | map()
  @type config :: map()

  @callback ensure_database(plugin_id, config) :: {:ok, map()} | {:error, term()}
  @callback execute(plugin_id, query, args, config) ::
              {:ok, %{rows: list(map()), num_rows: integer()}} | {:error, term()}
  @callback table_columns(plugin_id, table_name, config) :: {:ok, [String.t()]} | {:error, term()}
  @callback connection_config(plugin_id, config) :: {:ok, map()} | {:error, term()}
  @callback health_check(config) :: {:ok, map()} | {:error, term()}
  @callback reset(plugin_id, config) :: :ok | {:error, term()}
end
