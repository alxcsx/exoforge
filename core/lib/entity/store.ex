defmodule Exoforge.Entity.Store do
  @moduledoc """
  Persistence store behaviour for stateful entities.
  Provides a clean contract for persisting and loading entity actor state snapshots.
  """

  @type key :: {plugin :: atom(), type :: atom(), id :: String.t() | integer() | atom()}

  @callback load(key :: key()) :: {:ok, term()} | {:error, :not_found | term()}
  @callback save(key :: key(), state :: term()) :: :ok | {:error, term()}
  @callback delete(key :: key()) :: :ok | {:error, term()}
end
