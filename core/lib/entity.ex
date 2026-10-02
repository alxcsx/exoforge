defmodule Exoforge.Entity do
  @moduledoc """
  Behaviour and macro for stateful game entity actors.
  Features:
  - Automatic state hydration from configured Store on activation
  - `on_create/2` hook for newly initialized entities
  - Idle passivation timeout (auto-persists and stops actor when inactive)
  - Memory bounds protection via `Process.flag(:max_heap_size, ...)`
  - Automatic state snapshot on termination and passivation
  - Clean GenServer semantics with zero boilerplate
  """

  @callback on_create(id :: term(), opts :: keyword()) :: {:ok, term()} | term()
  @optional_callbacks [on_create: 2]

  @doc """
  Synchronously flushes the current entity state to the configured store.
  """
  def save_now(state) do
    meta = Process.get(:__exo_entity_meta__)

    if meta do
      meta.store.save({meta.plugin, meta.type, meta.id}, state)
    else
      :ok
    end
  end

  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Exoforge.Entity
      use GenServer

      @entity_opts unquote(opts)
      @entity_persist Keyword.get(@entity_opts, :persist, :memory)
      @entity_timeout Keyword.get(@entity_opts, :timeout, 300_000)
      @entity_max_heap Keyword.get(@entity_opts, :max_heap_size, 50 * 1024 * 1024)

      def start_link({plugin, type, id, init_opts}) do
        GenServer.start_link(
          __MODULE__,
          {plugin, type, id, init_opts},
          name: Exoforge.Entities.via_tuple(plugin, type, id)
        )
      end

      @impl true
      def init({plugin, type, id, init_opts}) do
        Process.flag(:trap_exit, true)

        if @entity_max_heap && @entity_max_heap > 0 do
          words = div(@entity_max_heap, :erlang.system_info(:wordsize))
          Process.flag(:max_heap_size, %{size: words, kill: true})
        end

        store =
          case @entity_persist do
            :memory -> Exoforge.Entity.MemoryStore
            :snapshot -> Exoforge.Entity.SnapshotStore
            mod when is_atom(mod) -> mod
          end

        meta = %{plugin: plugin, type: type, id: id, store: store, timeout: @entity_timeout}
        Process.put(:__exo_entity_meta__, meta)

        key = {plugin, type, id}

        case store.load(key) do
          {:ok, state} ->
            {:ok, state, @entity_timeout}

          {:error, :not_found} ->
            initial_state =
              if function_exported?(__MODULE__, :on_create, 2) do
                case apply(__MODULE__, :on_create, [id, init_opts]) do
                  {:ok, s} -> s
                  s -> s
                end
              else
                %{}
              end

            store.save(key, initial_state)
            {:ok, initial_state, @entity_timeout}
        end
      end

      @impl true
      def handle_call({:__exo_call__, user_msg}, from, state) do
        case handle_call(user_msg, from, state) do
          {:reply, reply, new_state} ->
            {:reply, reply, new_state, @entity_timeout}

          {:reply, reply, new_state, extra} ->
            {:reply, reply, new_state, extra}

          {:noreply, new_state} ->
            {:noreply, new_state, @entity_timeout}

          {:noreply, new_state, extra} ->
            {:noreply, new_state, extra}

          {:stop, reason, reply, new_state} ->
            {:stop, reason, reply, new_state}

          {:stop, reason, new_state} ->
            {:stop, reason, new_state}
        end
      end

      @impl true
      def handle_cast({:__exo_cast__, user_msg}, state) do
        case handle_cast(user_msg, state) do
          {:noreply, new_state} ->
            {:noreply, new_state, @entity_timeout}

          {:noreply, new_state, extra} ->
            {:noreply, new_state, extra}

          {:stop, reason, new_state} ->
            {:stop, reason, new_state}
        end
      end

      # Intercept idle timeout for automatic passivation
      @impl true
      def handle_info(:timeout, state) do
        meta = Process.get(:__exo_entity_meta__)

        if meta do
          meta.store.save({meta.plugin, meta.type, meta.id}, state)
        end

        {:stop, :normal, state}
      end

      @impl true
      def handle_info(_msg, state) do
        {:noreply, state, @entity_timeout}
      end

      @impl true
      def terminate(_reason, state) do
        meta = Process.get(:__exo_entity_meta__)

        if meta do
          meta.store.save({meta.plugin, meta.type, meta.id}, state)
        end

        :ok
      end

      defoverridable handle_info: 2, terminate: 2
    end
  end
end
