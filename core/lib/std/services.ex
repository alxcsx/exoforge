defmodule Exoforge.Std.Services do
  @moduledoc "Registry of built-in Exoforge service contracts."
  import Exoforge.Contracts.Service

  defservice database do
    @moduledoc "General database service."

    @doc "Executes a driver-agnostic query or data operation."
    action :execute do
      params(operation: :string, arguments: :map)
      returns(rows: [:map])
      errors([:syntax_error, :not_found, :unauthorized])
    end
  end

  defservice lldb do
    @moduledoc "Low-level database connection."

    @doc "Retrieves namespaced database connection details."
    action :connection_config do
      params(namespace: [type: :string, optional: true])

      returns(
        url: :string,
        pool_size: :integer,
        driver: :atom
      )
    end

    @doc "Performs a low-level ping to verify the database is reachable."
    action :health_check do
      returns(status: :string)
      errors([:unreachable, :timeout])
    end

    @doc "Fired when the underlying database pool drops connection."
    event :connection_lost do
      payload(reason: :string, timestamp: :integer)
      scope(:server_only)
    end
  end

  defservice dashboard_view do
    @moduledoc "Dashboard view and telemetry contract."

    @doc "Retrieves dashboard mount specification: {:live, Module} | {:hook, config} | {:iframe, config}"
    action :get_dashboard_mount do
      params(view_id: :atom)
      returns(mount: :term)
      scope(:server_only)
    end

    @doc "Retrieves data payload for hydrating the dashboard view."
    action :get_dashboard_data do
      params(view_id: :atom)
      returns(data: :map)
      scope(:server_only)
    end
  end

  defservice auth do
    @moduledoc "Authentication and identity service."

    @doc "Authenticates a client credential or token."
    action :authenticate do
      params(token: :string)
      returns(player_id: :string, scopes: [:string])
      errors([:invalid_token, :expired])
    end

    @doc "Verifies whether a player has the required authorization scope."
    action :verify_scope do
      params(player_id: :string, required_scope: :string)
      returns(authorized: :boolean)
      errors([:unauthorized])
    end
  end

  defservice player_data do
    @moduledoc "Canonical player profile and state storage."

    @doc "Player profiles and account state."
    resource :players do
      primary_key :player_id
      column :player_id, :string, label: "Player ID", sortable: true
      column :name, :string, label: "Display Name", filterable: true
      column :level, :integer, label: "Level", sortable: true
      column :status, :string, label: "Account Status", badge: true
      drawer [:overview, :attributes, :transactions, :inventory, :sessions, :events, :moderation]
      actions [:get_player, :update_player]
    end

    @doc "Retrieves player profile record."
    action :get_player do
      params(player_id: :string)
      returns(player: :map)
      errors([:player_not_found])
    end

    @doc "Updates player profile record."
    action :update_player do
      params(player_id: :string, data: :map)
      returns(player: :map)
      errors([:player_not_found, :invalid_attributes])
    end

    @doc "Emitted when a new player account is created."
    event :player_created do
      payload(player_id: :string, timestamp: :integer)
      scope(:server_only)
    end

    @doc "Emitted when a player account is deleted."
    event :player_deleted do
      payload(player_id: :string, timestamp: :integer)
      scope(:server_only)
    end
  end

  defservice combat do
    @moduledoc "Sandboxed combat gameplay and damage calculations."

    @doc "Ping action for health verification."
    action :ping do
      returns(pong: :integer)
    end

    @doc "Executes an attack action between two entities."
    action :attack do
      params(attacker_id: :integer, target_id: :integer, damage: :integer)
      returns(damage: :integer)
    end

    @doc "Fired when a player takes damage."
    event :player_damaged do
      payload(attacker_id: :integer, target_id: :integer, damage: :integer)
      scope(:global)
      topic("combat:events")
    end

    @doc "Combatants active in arena."
    resource :combatants do
      primary_key :entity_id
      column :entity_id, :integer, label: "Entity ID", sortable: true
      column :health, :integer, label: "Health", sortable: true
      column :status, :string, label: "Status", badge: true
      drawer [:overview, :events]
      actions [:attack, :ping]
    end
  end

  defservice ws do
    @moduledoc "Real-time WebSocket ingress and egress service."

    @doc "Broadcasts a frame to an active WebSocket topic."
    action :broadcast do
      params(topic: :string, event: :string, payload: :map)
      returns(status: :string)
    end

    @doc "Retrieves current active WebSocket connection count."
    action :connection_count do
      returns(count: :integer)
    end
  end

  defservice http do
    @moduledoc "HTTP REST ingress service."

    @doc "Returns HTTP server status and registered route summaries."
    action :status do
      returns(status: :string, port: :integer)
    end
  end
end
