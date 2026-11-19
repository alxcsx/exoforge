defmodule Exoforge.Std.Database.TestDB do
  @moduledoc """
  Provisions a throwaway PostgreSQL database for a test run and drops it on VM exit.

  Tests stay isolated from `exoforge_prod` and from earlier runs while exercising the
  real PostgreSQL adapter.
  """

  @env_key :test_pg_config

  @doc """
  Creates a throwaway `exoforge_test_<hex>` database, stores its connection map in
  `:exoforge`/`:test_pg_config`, and registers a `System.at_exit/1` hook to drop it
  with `WITH (FORCE)`.
  """
  def setup_throwaway!(opts \\ []) do
    {:ok, _} = Application.ensure_all_started(:postgrex)

    base = resolve_base_config(opts)
    db_name = "exoforge_test_" <> (:crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower))

    ensure_tcp_reachable!(base)
    exec_maintenance_sql!(base, ~s[CREATE DATABASE "#{db_name}"])

    System.at_exit(fn _status ->
      drop_database(base, db_name)
    end)

    config = Map.put(base, :database, db_name)
    Application.put_env(:exoforge, @env_key, config)
    config
  end

  @doc "Returns the throwaway PostgreSQL config provisioned by `setup_throwaway!/1`."
  def config do
    Application.fetch_env!(:exoforge, @env_key)
  end

  defp drop_database(base, db_name) do
    _ = Application.ensure_all_started(:postgrex)
    exec_maintenance_sql(base, ~s[DROP DATABASE IF EXISTS "#{db_name}" WITH (FORCE)])
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp ensure_tcp_reachable!(base) do
    case :gen_tcp.connect(String.to_charlist(base.host), base.port, [], 1_500) do
      {:ok, sock} ->
        :gen_tcp.close(sock)
        :ok

      {:error, reason} ->
        raise connection_error_message(base, reason)
    end
  end

  defp exec_maintenance_sql!(base, sql) do
    case exec_maintenance_sql(base, sql) do
      {:ok, _} -> :ok
      {:error, reason} -> raise connection_error_message(base, reason)
    end
  end

  defp exec_maintenance_sql(base, sql) do
    conn_opts = [
      hostname: base.host,
      port: base.port,
      username: base.username,
      password: base.password,
      database: "postgres",
      timeout: 3_000
    ]

    case Postgrex.start_link(conn_opts) do
      {:ok, conn} ->
        try do
          Postgrex.query(conn, sql, [])
        after
          if Process.alive?(conn), do: GenServer.stop(conn)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp connection_error_message(base, reason) do
    """
    Could not connect to PostgreSQL at #{base.host}:#{base.port} (#{inspect(reason)}).

    Start local PostgreSQL via Docker or Podman before running tests:
      just db-up
    """
  end

  defp resolve_base_config(opts) do
    defaults = %{
      host: "127.0.0.1",
      port: 5432,
      username: "postgres",
      password: "postgres"
    }

    pg_env =
      %{}
      |> maybe_put_env(:host, "PGHOST")
      |> maybe_put_port_env(:port, "PGPORT")
      |> maybe_put_env(:username, "PGUSER")
      |> maybe_put_env(:password, "PGPASSWORD")

    url_cfg = parse_url(System.get_env("DATABASE_URL"))

    defaults
    |> Map.merge(pg_env)
    |> Map.merge(url_cfg)
    |> Map.merge(Enum.into(opts, %{}))
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

  defp parse_url(url) when is_binary(url) and url != "" do
    uri = URI.parse(url)

    creds =
      case uri.userinfo do
        info when is_binary(info) and info != "" ->
          case String.split(info, ":", parts: 2) do
            [user, pass] -> %{username: user, password: pass}
            [user] -> %{username: user, password: ""}
          end

        _ ->
          %{}
      end

    %{}
    |> then(fn m ->
      if is_binary(uri.host) and uri.host != "", do: Map.put(m, :host, uri.host), else: m
    end)
    |> then(fn m -> if is_integer(uri.port), do: Map.put(m, :port, uri.port), else: m end)
    |> Map.merge(creds)
  end

  defp parse_url(_), do: %{}
end
