defmodule Exoforge.Std.Database.Manager do
  @moduledoc """
  Core mediator and lifecycle manager for Exoforge multi-tenant database access.
  Acts as the middleground between database backends (PostgreSQL, Sandbox) and all plugins.
  Guarantees that each plugin operates exclusively within its own isolated database/schema.
  """
  use GenServer
  require Logger

  alias Exoforge.Std.Database.Adapters.Postgres
  alias Exoforge.Std.Database.Adapters.Sandbox

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
    clean = clean_id(plugin_id)

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
    clean = clean_id(plugin_id)
    # Automatically ensure database exists on first query
    _ = state.adapter.ensure_database(clean, state.config)
    result = state.adapter.execute(clean, query, args, state.config)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:connection_config, plugin_id}, _from, state) do
    clean = clean_id(plugin_id)
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
    clean = clean_id(plugin_id)
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
  end

  defp detect_adapter(config) do
    force_driver = Map.get(config, :driver)

    cond do
      force_driver == :postgres ->
        Postgres

      force_driver == :sandbox ->
        Sandbox

      function_exported?(Mix, :env, 0) and Mix.env() == :test ->
        Sandbox

      Map.has_key?(config, :host) or System.get_env("DATABASE_URL") != nil ->
        # Verify if Postgres is reachable
        case Postgres.health_check(config) do
          {:ok, _} ->
            Postgres

          {:error, _reason} ->
            Logger.warning("[Database] PostgreSQL not reachable at configured host. Falling back to Sandbox adapter.")
            Sandbox
        end

      true ->
        Sandbox
    end
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

  defp clean_id(plugin_id) do
    plugin_id
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
    |> String.downcase()
    |> String.to_atom()
  end
end
