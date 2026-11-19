defmodule Exoforge.Std.Lldb.Adapter do
  @moduledoc """
  Behaviour defining operations for Exoforge database drivers.
  Every adapter must enforce strict per-plugin database isolation.
  """

  @type plugin_id :: atom() | String.t()
  @type table_name :: String.t()
  @type query :: String.t()
  @type args :: list() | map()
  @type config :: map()

  @callback ensure_database(plugin_id, config) :: {:ok, map()} | {:error, term()}
  @callback execute(plugin_id, query, args, config) ::
              {:ok, %{rows: list(map()), num_rows: integer()}} | {:error, term()}
  @callback table_columns(plugin_id, table_name, config) :: {:ok, [String.t()]} | {:error, term()}

  @typedoc "One statement of a transaction: SQL text and its positional arguments."
  @type statement :: {String.t(), list()}

  @doc """
  Runs the statements in order inside one transaction in the plugin's namespace, all or nothing.
  Fails with `%{index: i, reason: term, message: String.t()}` naming the statement that failed.
  """
  @callback transaction(plugin_id, [statement], config) ::
              {:ok, %{results: [map()], num_rows: integer()}} | {:error, term()}

  @doc """
  Describes a table of the namespace in engine-neutral terms: `columns` with a logical `type`
  (`text`, `int16`, `int32`, `int64`, `float32`, `float64`, `decimal`, `bool`, `uuid`, `timestamp`,
  `bytes`, `json` or `other`), whether it carries a time zone (`tz`) and whether it is `nullable`, and
  the `primary_key` column names in order.
  """
  @callback introspect(plugin_id, table_name, config) :: {:ok, map()} | {:error, term()}

  @doc "How to write SQL for this engine: placeholder and quoting style, upsert strategy, native type names."
  @callback dialect(config) :: map()
  @callback connection_config(plugin_id, config) :: {:ok, map()} | {:error, term()}
  @callback health_check(config) :: {:ok, map()} | {:error, term()}
  @callback reset(plugin_id, config) :: :ok | {:error, term()}
end
