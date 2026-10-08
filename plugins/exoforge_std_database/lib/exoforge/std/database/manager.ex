defmodule Exoforge.Std.Database.Manager do
  @moduledoc """
  Core mediator and lifecycle manager for Exoforge multi-tenant database access.
  Acts as the middleground between database backends (PostgreSQL, SQLite) and all plugins.
  Guarantees that each plugin operates exclusively within its own isolated database/schema.
  """
  use GenServer
  require Logger

  alias Exoforge.Std.Database
  alias Exoforge.Std.Database.Adapters.Postgres
  alias Exoforge.Std.Database.Adapters.Sqlite

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
  def execute(plugin_id, query, args \\ []) do
    GenServer.call(@name, {:execute, plugin_id, query, args}, 15_000)
  end

  @doc "Returns isolated connection configuration for the plugin."
  def connection_config(plugin_id) do
    GenServer.call(@name, {:connection_config, plugin_id})
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

    case state.adapter.ensure_database(clean, state.config) do
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
    # Automatically ensure database exists on first query
    _ = state.adapter.ensure_database(clean, state.config)
    result = state.adapter.execute(clean, query, args, state.config)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:connection_config, plugin_id}, _from, state) do
    clean = Database.clean_id(plugin_id)
    result = state.adapter.connection_config(clean, state.config)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    result = state.adapter.health_check(state.config)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:reset, plugin_id}, _from, state) do
    clean = Database.clean_id(plugin_id)
    result = state.adapter.reset(clean, state.config)
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

  defp resolve_config(opts) do
    app_config = Application.get_env(:exoforge, :database, [])
    url = System.get_env("DATABASE_URL") || Keyword.get(app_config, :url)

    parsed_url = if url, do: parse_database_url(url), else: %{}

    Enum.into(opts, %{})
    |> Map.merge(Enum.into(app_config, %{}))
    |> Map.merge(parsed_url)
    |> Map.put_new_lazy(:data_dir, &default_data_dir/0)
  end

  # Tests get a fresh SQLite database per Manager instance so cases stay isolated; everything else
  # persists under priv/data/sqlite, unless EXOFORGE_DATA_DIR says otherwise.
  #
  # That override is what lets a server run against a throwaway database: the integration tests start
  # one, and without it they wrote every account, token and score they made into the developer's own
  # database - 83 players and 186 tokens after a few runs, indistinguishable from real ones.
  defp default_data_dir do
    cond do
      dir = System.get_env("EXOFORGE_DATA_DIR") ->
        dir

      function_exported?(Mix, :env, 0) and Mix.env() == :test ->
        Path.join(System.tmp_dir!(), "exoforge_test_#{System.unique_integer([:positive])}")

      true ->
        Path.join([File.cwd!(), "priv", "data", "sqlite"])
    end
  end

  defp detect_adapter(config) do
    force_driver = Map.get(config, :driver)

    cond do
      force_driver == :postgres ->
        Postgres

      force_driver == :sqlite ->
        Sqlite

      function_exported?(Mix, :env, 0) and Mix.env() == :test ->
        Sqlite

      Map.has_key?(config, :host) or System.get_env("DATABASE_URL") != nil ->
        # Verify if Postgres is reachable
        case Postgres.health_check(config) do
          {:ok, _} ->
            Postgres

          {:error, _reason} ->
            Logger.warning(
              "[Database] PostgreSQL not reachable at configured host. Using the local SQLite adapter."
            )

            Sqlite
        end

      true ->
        if sqlite_fallback_allowed?(config) do
          Logger.warning(
            "[Database] No DATABASE_URL configured. Using the local SQLite adapter " <>
              "(data persists under priv/data/sqlite). Set DATABASE_URL for a production database."
          )

          Sqlite
        else
          raise """
          No DATABASE_URL configured and the SQLite fallback is not permitted in production.

          Set DATABASE_URL (or :database, :driver) to point at a real database, or set
          EXOFORGE_ALLOW_SQLITE_FALLBACK=true to explicitly opt in to a local SQLite file.
          """
        end
    end
  end

  # SQLite is the dev/test default. In production — including any release build,
  # where Mix is unavailable — it must be an explicit choice, never a silent fallback.
  defp sqlite_fallback_allowed?(config) do
    case Map.get(config, :fallback_to_sqlite) do
      true -> true
      false -> false
      nil -> not prod_build?() or System.get_env("EXOFORGE_ALLOW_SQLITE_FALLBACK") in ["1", "true", "yes"]
    end
  end

  defp prod_build? do
    if function_exported?(Mix, :env, 0), do: Mix.env() == :prod, else: true
  end

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

  defp parse_database_url(_), do: %{}

end
