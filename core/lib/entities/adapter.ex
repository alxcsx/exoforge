defmodule Exoforge.Entities.Adapter do
  @moduledoc """
  Behaviour for pluggable stateful entity clustering backends.
  Implementations:
  - `Exoforge.Entities.Adapters.Local`: Fast, zero-dependency local Registry & DynamicSupervisor.
  - `Exoforge.Entities.Adapters.Horde`: Distributed delta-CRDT Registry & DynamicSupervisor with libcluster.
  """

  @type plugin :: atom()
  @type type :: atom() | binary()
  @type id :: term()

  @callback registry_spec(opts :: keyword()) :: Supervisor.child_spec() | {module(), term()}
  @callback supervisor_spec(opts :: keyword()) :: Supervisor.child_spec() | {module(), term()}
  @callback via_tuple(plugin(), type(), id()) :: {:via, module(), term()}
  @callback whereis(plugin(), type(), id()) :: {:ok, pid()} | {:error, :not_found}
  @callback start_child(child_spec :: map()) :: {:ok, pid()} | {:error, term()}
  @callback terminate_child(pid :: pid()) :: :ok | {:error, term()}
  @callback count() :: non_neg_integer()
  @callback list_active() :: [map()]

  @optional_callbacks list_active: 0
end
