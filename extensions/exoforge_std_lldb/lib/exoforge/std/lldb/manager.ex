defmodule Exoforge.Std.Lldb.Manager do
  @moduledoc """
  Front door to the driver for every extension, and the owner of provisioning.

  Only provisioning goes through this process: making a namespace the first time it is used, and
  resetting one. Everything else (queries, transactions, introspection) runs in the CALLING process
  against the adapter and config this process published at start, so the connection pools do the
  concurrency and one slow query never queues the queries of other extensions behind it.
  """
  use GenServer
  require Logger

  alias Exoforge.Std.Lldb
  alias Exoforge.Std.Lldb.Adapters.Postgres

  @name __MODULE__
  @provisioned __MODULE__.Provisioned
  @runtime {__MODULE__, :runtime}

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @doc "Ensures a dedicated, isolated database or schema exists for the given plugin."
  def ensure_database(plugin_id) do
    with {:ok, _clean} <- ready(plugin_id), do: {:ok, %{status: :ready}}
  end

  @doc "Executes a SQL statement isolated to the plugin's namespace."
  def execute(plugin_id, query, args \\ []) do
    run(plugin_id, fn adapter, clean, config -> adapter.execute(clean, query, args, config) end)
  end

  @doc "Runs `statements` (`{sql, args}` pairs) in order in one transaction; all or nothing."
  def transaction(plugin_id, statements) when is_list(statements) do
    run(plugin_id, fn adapter, clean, config -> adapter.transaction(clean, statements, config) end)
  end

  @doc "Describes a table of the plugin's namespace in engine-neutral terms."
  def introspect(plugin_id, table) do
    run(plugin_id, fn adapter, clean, config -> adapter.introspect(clean, table, config) end)
  end

  @doc "How to write SQL for the active engine."
  def dialect do
    case runtime() do
      {adapter, config} -> {:ok, adapter.dialect(config)}
      nil -> {:error, {:database_error, :manager_not_started}}
    end
  end

  @doc "Returns isolated connection configuration for the plugin."
  def connection_config(plugin_id) do
    with {adapter, config} <- runtime() || {:error, {:database_error, :manager_not_started}} do
      safely(fn -> adapter.connection_config(Lldb.clean_id(plugin_id), config) end)
    end
  end

  @doc "Lists the columns of a table in the plugin's isolated database."
  def table_columns(plugin_id, table) do
    run(plugin_id, fn adapter, clean, config -> adapter.table_columns(clean, table, config) end)
  end

  @doc "Dry-run declarative schema plan for an extension's declared resources (applies nothing)."
  def plan_schema(plugin_id, resources \\ nil) do
    run(plugin_id, fn adapter, clean, config ->
      if function_exported?(adapter, :plan_schema, 3),
        do: adapter.plan_schema(clean, resources, config),
        else: Postgres.plan_schema(clean, resources, config)
    end)
  end

  @doc "Applies the safe changes that bring an extension's tables in line with its declared resources."
  def apply_schema(plugin_id, resources \\ nil, migrations \\ nil) do
    run(plugin_id, fn adapter, clean, config -> adapter.apply_schema(clean, resources, migrations, config) end)
  end

  @doc "Drops one table of the plugin's namespace, and its schema history."
  def reset_table(plugin_id, table) do
    run(plugin_id, fn adapter, clean, config -> adapter.reset_table(clean, table, config) end)
  end

  @doc "Performs a health check of the underlying database system."
  def health_check do
    with {adapter, config} <- runtime() || {:error, {:database_error, :manager_not_started}} do
      safely(fn -> adapter.health_check(config) end)
    end
  end

  @doc "Resets/clears the database for the given plugin."
  def reset(plugin_id) do
    GenServer.call(@name, {:reset, plugin_id})
  end

  @doc "Lists all registered plugin databases."
  def list_databases do
    GenServer.call(@name, :list_databases)
  end

  @doc "Explicitly overrides the active adapter (e.g. for testing)."
  def set_adapter(adapter) do
    GenServer.call(@name, {:set_adapter, adapter})
  end

  ## Running in the caller

  # The adapter and config are published once and read by every caller.
  defp runtime, do: :persistent_term.get(@runtime, nil)

  # Provision on first use, then run in this process. A namespace already known costs one ETS lookup.
  defp run(plugin_id, fun) do
    with {:ok, clean} <- ready(plugin_id) do
      case runtime() do
        {adapter, config} -> safely(fn -> fun.(adapter, clean, config) end)
        nil -> {:error, {:database_error, :manager_not_started}}
      end
    end
  end

  # Provisioning is remembered, so a second query for a known database skips the DDL round trip
  # (M33 Fix 7). A failed provision is not remembered, so the next call retries it.
  defp ready(plugin_id) do
    clean = Lldb.clean_id(plugin_id)

    if provisioned?(clean) do
      {:ok, clean}
    else
      case safe_call({:ensure_database, plugin_id}, 30_000) do
        {:ok, _} -> {:ok, clean}
        {:error, _} = error -> error
        other -> {:error, other}
      end
    end
  end

  defp provisioned?(clean) do
    :ets.member(@provisioned, clean)
  rescue
    ArgumentError -> false
  end

  # The Manager being down is a database error for the caller, not an exit.
  defp safe_call(message, timeout) do
    GenServer.call(@name, message, timeout)
  catch
    :exit, reason ->
      Logger.error("[Database] manager unavailable: #{inspect(reason)}")
      {:error, {:database_error, reason}}
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    config = resolve_config(opts)
    adapter = detect_adapter(config)

    :ets.new(@provisioned, [:set, :public, :named_table, read_concurrency: true])
    :persistent_term.put(@runtime, {adapter, config})

    Logger.info("[Database] Manager initialized using adapter: #{inspect(adapter)}")
    {:ok, %{adapter: adapter, config: config}}
  end

  @impl true
  def handle_call({:ensure_database, plugin_id}, _from, state) do
    clean = Lldb.clean_id(plugin_id)

    # Two callers can arrive for the same new namespace: the second finds it already made.
    if provisioned?(clean) do
      {:reply, {:ok, %{status: :ready}}, state}
    else
      case safely(fn -> state.adapter.ensure_database(clean, state.config) end) do
        {:ok, result} ->
          :ets.insert(@provisioned, {clean})
          {:reply, {:ok, result}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}

        other ->
          {:reply, {:error, other}, state}
      end
    end
  end

  def handle_call({:reset, plugin_id}, _from, state) do
    clean = Lldb.clean_id(plugin_id)
    result = safely(fn -> state.adapter.reset(clean, state.config) end)
    :ets.delete(@provisioned, clean)
    {:reply, result, state}
  end

  def handle_call(:list_databases, _from, state) do
    {:reply, :ets.select(@provisioned, [{{:"$1"}, [], [:"$1"]}]), state}
  end

  def handle_call({:set_adapter, adapter}, _from, state) do
    :persistent_term.put(@runtime, {adapter, state.config})
    {:reply, :ok, %{state | adapter: adapter}}
  end

  ## Helpers

  # The adapter is this GenServer's only contact with the outside world, and it raises when that
  # world is unavailable: Postgrex raises DBConnection.ConnectionError on a dropped connection or a
  # checkout timeout. Unhandled, one bad query took down the single Manager every extension shares,
  # and every caller - the resource store included - got {:extension_exited, ...} instead of the
  # database error that caused it, then kept getting it while the Manager restarted.
  defp safely(fun) do
    fun.()
  rescue
    e ->
      Logger.error("[Database] adapter failure: " <> Exception.format(:error, e, __STACKTRACE__))
      {:error, {:database_error, Exception.message(e)}}
  catch
    :exit, reason ->
      Logger.error("[Database] adapter exit: #{inspect(reason)}")
      {:error, {:database_error, reason}}
  end

  defp resolve_config(opts) do
    app_config = Application.get_env(:exoforge, :database, []) |> Enum.into(%{})

    env_url =
      case System.get_env("DATABASE_URL") do
        val when is_binary(val) and val != "" -> val
        _ -> nil
      end

    url = env_url || Map.get(app_config, :url)
    parsed_url = if is_binary(url) and url != "", do: parse_database_url(url), else: %{}

    %{}
    |> Map.merge(app_config)
    |> Map.merge(parsed_url)
    |> Map.merge(pg_env_config())
    |> Map.merge(test_pg_config())
    |> Map.merge(Enum.into(opts, %{}))
  end

  defp pg_env_config do
    %{}
    |> maybe_put_env(:host, "PGHOST")
    |> maybe_put_port_env(:port, "PGPORT")
    |> maybe_put_env(:username, "PGUSER")
    |> maybe_put_env(:password, "PGPASSWORD")
    |> maybe_put_env(:database, "PGDATABASE")
    |> maybe_put_env(:role_secret, "EXOFORGE_DB_ROLE_SECRET")
  end

  defp maybe_put_env(acc, key, env_name) do
    case System.get_env(env_name) do
      val when is_binary(val) and val != "" -> Map.put(acc, key, val)
      _ -> acc
    end
  end

  defp maybe_put_port_env(acc, key, env_name) do
    case System.get_env(env_name) do
      val when is_binary(val) and val != "" ->
        case Integer.parse(val) do
          {port, ""} -> Map.put(acc, key, port)
          _ -> acc
        end

      _ ->
        acc
    end
  end

  defp test_pg_config do
    case Application.get_env(:exoforge, :test_pg_config) do
      nil -> %{}
      cfg -> Enum.into(cfg, %{})
    end
  end

  defp detect_adapter(config), do: Map.get(config, :adapter, Postgres)

  defp parse_database_url(url) when is_binary(url) do
    uri = URI.parse(url)

    userinfo = if uri.userinfo, do: String.split(uri.userinfo, ":"), else: []
    user = Enum.at(userinfo, 0, "postgres")
    pass = Enum.at(userinfo, 1, "")
    db = if uri.path, do: String.trim_leading(uri.path, "/"), else: "postgres"

    %{
      driver: :postgres,
      host: uri.host || "localhost",
      port: uri.port || 5432,
      username: user,
      password: pass,
      database: db
    }
  end
end
