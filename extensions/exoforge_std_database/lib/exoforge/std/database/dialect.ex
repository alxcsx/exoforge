defmodule Exoforge.Std.Database.Dialect do
  @moduledoc """
  How to write SQL for the active engine, as the `lldb` driver layer describes it.

  The database layer builds its statements from this and never from an engine's own habits: the
  placeholder and quoting style, the way to upsert, the native names of the logical types. It is
  asked once and remembered, since the engine does not change while the system runs.
  """
  alias Exoforge.ActionDispatcher

  @key {__MODULE__, :dialect}

  @doc "The dialect map from `lldb`, fetched on first use."
  def get do
    case :persistent_term.get(@key, nil) do
      nil -> fetch()
      dialect -> dialect
    end
  end

  @doc "Forgets the remembered dialect (tests that swap the driver layer)."
  def reset, do: :persistent_term.erase(@key)

  defp fetch do
    case ActionDispatcher.dispatch_internal(:lldb, :dialect, %{}) do
      {:ok, dialect} when is_map(dialect) ->
        :persistent_term.put(@key, dialect)
        dialect

      other ->
        raise ArgumentError, "the lldb driver layer gave no dialect: #{inspect(other)}"
    end
  end

  @doc "An identifier, validated and quoted the way the engine wants. Raises `ArgumentError` for anything else."
  def quote_ident(name) do
    str = to_string(name)

    if byte_size(str) in 1..63 and Regex.match?(~r/^[a-z0-9_]+\z/, str) do
      quote_char = get().identifier_quote
      quote_char <> str <> quote_char
    else
      raise ArgumentError, "invalid SQL identifier: #{inspect(name)}"
    end
  end

  @doc "The `n`th positional placeholder (1-based)."
  def placeholder(n) do
    case get().placeholder do
      "numbered" -> "$#{n}"
      "question" -> "?"
    end
  end

  @doc "A placeholder that carries JSON text."
  def json_placeholder(n), do: placeholder(n) <> Map.get(get(), :json_cast, "")

  @doc "The engine's name for a logical type (`text`, `json`, `timestamp`, `timestamp_naive`)."
  def type(logical), do: Map.fetch!(get().types, to_string(logical))

  @doc "How the engine upserts: `on_conflict` or `delete_insert`."
  def upsert, do: get().upsert
end
