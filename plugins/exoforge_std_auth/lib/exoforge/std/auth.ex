defmodule Exoforge.Std.Auth do
  @moduledoc """
  Standard authentication and authorization plugin for Exoforge.
  Provides the :auth service contract.
  Relies on the :database service for isolated persistence of tokens and scopes.
  """
  use Exoforge.Plugin, provides: [:auth]

  @manifest %{
    dependencies: [Exoforge.Std.Services.Database]
  }

  alias Exoforge.ActionDispatcher

  def on_init(_manifest) do
    init_schema()
    :ok
  end

  @doc "Initializes the required tables in the isolated auth database."
  def init_schema do
    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :auth,
        operation: "CREATE TABLE IF NOT EXISTS tokens (id text, token text, player_id text, scopes text)"
      })

    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :auth,
        operation: "CREATE TABLE IF NOT EXISTS players (id text, player_id text, scopes text)"
      })

    :ok
  end

  ## ---- SERVICE ACTIONS ----

  @impl true
  defaction authenticate(payload) do
    token = extract_token(payload)

    cond do
      is_nil(token) or token == "" ->
        {:error, :invalid_token}

      # Fast path for dev convenience tokens: "dev:<id>" or "guest"
      String.starts_with?(token, "dev:") ->
        player_id = String.replace_prefix(token, "dev:", "")
        {:ok, %{player_id: player_id, scopes: ["player", "admin"]}}

      token == "guest" ->
        {:ok, %{player_id: "guest_anon", scopes: ["guest"]}}

      true ->
        query = "SELECT * FROM tokens WHERE token = $1"

        case ActionDispatcher.dispatch(:database, :execute, %{plugin: :auth, operation: query, arguments: [token]}) do
          {:ok, %{rows: [row | _]}} ->
            player_id = Map.get(row, "player_id") || Map.get(row, :player_id)
            raw_scopes = Map.get(row, "scopes") || Map.get(row, :scopes) || "player"
            scopes = parse_scopes(raw_scopes)
            {:ok, %{player_id: player_id, scopes: scopes}}

          {:ok, %{rows: []}} ->
            {:error, :invalid_token}

          {:error, _reason} ->
            {:error, :invalid_token}
        end
    end
  end

  @impl true
  defaction verify_scope(payload) do
    player_id = Map.get(payload, :player_id) || Map.get(payload, "player_id")
    required = Map.get(payload, :required_scope) || Map.get(payload, "required_scope")

    if is_nil(player_id) or is_nil(required) do
      {:error, :unauthorized}
    else
      # Special admin override
      if player_id == "admin" or String.starts_with?(player_id, "dev_admin") do
        {:ok, %{authorized: true}}
      else
        query = "SELECT * FROM players WHERE player_id = $1"

        case ActionDispatcher.dispatch(:database, :execute, %{plugin: :auth, operation: query, arguments: [player_id]}) do
          {:ok, %{rows: [row | _]}} ->
            raw_scopes = Map.get(row, "scopes") || Map.get(row, :scopes) || ""
            scopes = parse_scopes(raw_scopes)
            authorized = required in scopes or "admin" in scopes
            {:ok, %{authorized: authorized}}

          {:ok, %{rows: []}} ->
            # Default scope: "player"
            {:ok, %{authorized: required == "player" or required == "guest"}}

          _ ->
            {:ok, %{authorized: false}}
        end
      end
    end
  end

  ## ---- DIRECT ELIXIR FACADE ----

  @doc "Issues and stores a new authentication token for a player."
  def issue_token(player_id, scopes \\ ["player"]) do
    init_schema()
    token = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
    scopes_str = Enum.join(scopes, ",")

    insert_query = "INSERT INTO tokens (id, token, player_id, scopes) VALUES ($1, $2, $3, $4)"

    case ActionDispatcher.dispatch(:database, :execute, %{
           plugin: :auth,
           operation: insert_query,
           arguments: [token, token, player_id, scopes_str]
         }) do
      {:ok, _} ->
        # Also record/update the player's primary scopes
        _ = set_player_scopes(player_id, scopes)
        {:ok, token}

      error ->
        error
    end
  end

  @doc "Registers or updates scopes for a player."
  def set_player_scopes(player_id, scopes) do
    init_schema()
    scopes_str = Enum.join(scopes, ",")

    # Delete previous entry if exists
    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :auth,
        operation: "DELETE FROM players WHERE player_id = $1",
        arguments: [player_id]
      })

    insert_query = "INSERT INTO players (id, player_id, scopes) VALUES ($1, $2, $3)"

    ActionDispatcher.dispatch(:database, :execute, %{
      plugin: :auth,
      operation: insert_query,
      arguments: [player_id, player_id, scopes_str]
    })
  end

  ## ---- PRIVATE HELPERS ----

  defp extract_token(payload) when is_binary(payload), do: payload

  defp extract_token(payload) when is_map(payload) do
    Map.get(payload, :token) || Map.get(payload, "token")
  end

  defp extract_token(_), do: nil

  defp parse_scopes(scopes) when is_list(scopes), do: Enum.map(scopes, &to_string/1)

  defp parse_scopes(scopes) when is_binary(scopes) do
    scopes
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_scopes(_), do: ["player"]
end
