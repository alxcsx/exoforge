defmodule Exoforge.Std.Database.Manager do
  @moduledoc """
  Core mediator and lifecycle manager for Exoforge multi-tenant database access.
  Acts as the middleground between PostgreSQL and all plugins.
  Guarantees that each plugin operates exclusively within its own isolated database/schema.
  """
  use GenServer
  require Logger

  alias Exoforge.Std.Database
  alias Exoforge.Std.Database.Adapters.Postgres

  @name __MODULE__

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @doc "Ensures a dedicated, isolated database or schema exists for the given plugin."
  def ensure_database(plugin_id) do
    GenServer.call(@name, {:ensure_database, plugin_id})
  end

  @doc "Executes a query or operation isolated to the plugin's database."
  def execute(plugin_id, query, args \\ [])

  def execute(plugin_id, %{action: action, table: _} = command, args) when action in [:put, :get, :all] do
    command = Exoforge.Std.Database.JsonColumns.encode(command)

    Exoforge.Std.Database.JsonColumns.decode(
      command,
      GenServer.call(@name, {:execute, plugin_id, command, args}, 15_000)
    )
  end

  def execute(plugin_id, query, args) do
    GenServer.call(@name, {:execute, plugin_id, query, args}, 15_000)
  end

  @doc "Returns isolated connection configuration for the plugin."
  def connection_config(plugin_id) do
    GenServer.call(@name, {:connection_config, plugin_id})
  end

  @doc "Lists the columns of a table in the plugin's isolated database."
  def table_columns(plugin_id, table) do
    GenServer.call(@name, {:table_columns, plugin_id, table}, 15_000)
  end

  @doc "Performs a health check of the underlying database system."
  def health_check do
    GenServer.call(@name, :health_check)
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

  ## Server Callbacks

  @impl true
  def init(opts) do
    config = resolve_config(opts)
    adapter = detect_adapter(config)

    state = %{
      adapter: adapter,
      config: config,
      databases: MapSet.new()
    }

    Logger.info("[Database] Manager initialized using adapter: #{inspect(adapter)}")
    {:ok, state}
  end

  @impl true
  def handle_call({:ensure_database, plugin_id}, _from, state) do
    clean = Database.clean_id(plugin_id)

    case safely(fn -> state.adapter.ensure_database(clean, state.config) end) do
      {:ok, result} ->
        new_dbs = MapSet.put(state.databases, clean)
        {:reply, {:ok, result}, %{state | databases: new_dbs}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:execute, plugin_id, query, args}, _from, state) do
    clean = Database.clean_id(plugin_id)
    # Ensure the database exists on first use, not on every query (M33 Fix 7): provisioning DDL on
    # each request was a round trip to the server per query, and the manager already remembers.
    state = ensure_once(clean, state)
    result = safely(fn -> state.adapter.execute(clean, query, args, state.config) end)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:table_columns, plugin_id, table}, _from, state) do
    clean = Database.clean_id(plugin_id)
    # Column inspection wants the table to exist; same first-use rule as execute.
    state = ensure_once(clean, state)
    result = safely(fn -> state.adapter.table_columns(clean, table, state.config) end)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:connection_config, plugin_id}, _from, state) do
    clean = Database.clean_id(plugin_id)
    result = safely(fn -> state.adapter.connection_config(clean, state.config) end)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    result = safely(fn -> state.adapter.health_check(state.config) end)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:reset, plugin_id}, _from, state) do
    clean = Database.clean_id(plugin_id)
    result = safely(fn -> state.adapter.reset(clean, state.config) end)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_databases, _from, state) do
    {:reply, MapSet.to_list(state.databases), state}
  end

  @impl true
  def handle_call({:set_adapter, adapter}, _from, state) do
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

  # Provisioning is remembered, so a second query for a known database skips the DDL round trip
  # (M33 Fix 7). A failed provision is not remembered, so the next call retries it.
  defp ensure_once(clean, state) do
    if MapSet.member?(state.databases, clean) do
      state
    else
      case safely(fn -> state.adapter.ensure_database(clean, state.config) end) do
        {:ok, _} -> %{state | databases: MapSet.put(state.databases, clean)}
        _ -> state
      end
    end
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
