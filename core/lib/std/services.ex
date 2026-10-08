defmodule Exoforge.Std.Services do
  @moduledoc "Registry of built-in Exoforge service contracts."
  import Exoforge.Contracts.Service

  defservice database do
    @moduledoc "General database service."

    @doc "Executes a driver-agnostic query or data operation."
    action :execute do
      scope(:server)

      params(
        operation: :string,
        arguments: [type: :term, optional: true],
        plugin: [type: :term, optional: true]
      )

      returns(rows: [:map])
      errors([:syntax_error, :not_found, :unauthorized])
    end
  end

  defservice lldb do
    @moduledoc "Low-level database connection."

    @doc "Retrieves namespaced database connection details."
    action :connection_config do
      scope(:server)
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
      scope(:server)
    end
  end

  defservice dashboard do
    @moduledoc "Dashboard host and studio server contract."

    @doc "Per-account Studio preferences (pinned extensions, etc.)."
    defresource StudioPreference,
      name: :studio_preference,
      primary_key: :player_id,
      source: {:table, "studio_preferences"} do
      column(:player_id, :string, sortable: true)
      column(:data, :string)
    end

    @doc "Retrieves dashboard mount specification: {:live, Module} | {:hook, config} | {:iframe, config}"
    action :get_dashboard_mount do
      params(view_id: [type: :atom, optional: true])
      returns(mount: :term)
      scope(:server)
    end

    @doc "Retrieves data payload for hydrating the dashboard view."
    action :get_dashboard_data do
      params(view_id: [type: :atom, optional: true])
      returns(data: :map)
      scope(:server)
    end
  end

  defservice dashboard_view do
    @moduledoc "Dashboard view and telemetry contract."

    @doc "Resolves the LiveView component module for a given service or extension id."
    action :resolve_view do
      params(id: :term)
      returns(module: :term)
      scope(:server)
    end

    @doc "Lists all registered custom dashboard view modules."
    action :list_views do
      returns(views: [:map])
      scope(:server)
    end

    @doc "Retrieves dashboard mount specification: {:live, Module} | {:hook, config} | {:iframe, config}"
    action :get_dashboard_mount do
      params(view_id: [type: :atom, optional: true])
      returns(mount: :term)
      scope(:server)
    end

    @doc "Retrieves data payload for hydrating the dashboard view."
    action :get_dashboard_data do
      params(view_id: [type: :atom, optional: true])
      returns(data: :map)
      scope(:server)
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

    @doc "Authenticates an account with email and password."
    action :login do
      params(email: :string, password: :string)
      returns(player_id: :string, token: :string, scopes: [:string])
      errors([:invalid_credentials])
    end

    @doc "Verifies whether a player or user has the required authorization scope."
    action :verify_scope do
      params(
        user_id: [type: :string, optional: true],
        player_id: [type: :string, optional: true],
        required_scope: :string
      )

      returns(authorized: :boolean)
      errors([:unauthorized])
    end

    @doc "Registers a new user account and profile in both auth and player_data."
    action :register do
      params(
        user_id: [type: :string, optional: true],
        player_id: [type: :string, optional: true],
        name: [type: :string, optional: true],
        email: [type: :string, optional: true],
        password: [type: :string, optional: true],
        scopes: [type: :term, optional: true]
      )

      returns(user_id: :string, player_id: :string, token: :string, scopes: [:string], player: :map)
      errors([:invalid_attributes, :registration_failed])
    end

    @doc "Creates a new player or user account with authentication credentials."
    action :create_player do
      params(
        user_id: [type: :string, optional: true],
        player_id: [type: :string, optional: true],
        name: [type: :string, optional: true],
        email: [type: :string, optional: true],
        password: [type: :string, optional: true],
        scopes: [type: :term, optional: true]
      )

      returns(user_id: :string, player_id: :string, token: :string, scopes: [:string], player: :map)
      errors([:invalid_attributes, :registration_failed])
    end

    @doc "Creates or resumes an anonymous player session."
    action :anonymous do
      params(
        player_id: [type: :string, optional: true],
        name: [type: :string, optional: true]
      )

      returns(player_id: :string, token: :string, scopes: [:string])
      errors([:invalid_attributes, :registration_failed])
    end

    @doc "Sets the signed-in player's display name."
    action :set_display_name do
      params(player_id: [type: :string, optional: true], name: :string)
      returns(player_id: :string, name: :string)
      errors([:unauthorized, :invalid_attributes, :player_not_found])
    end

    @doc "Issues an authentication token for a user or player."
    action :issue_token do
      params(
        player_id: :string,
        user_id: [type: :string, optional: true],
        scopes: [type: :term, optional: true]
      )

      returns(token: :string, user_id: :string, player_id: :string)
      errors([:invalid_player])
    end

    @doc "Lists all registered user accounts and their assigned authorization scopes."
    action :list_users do
      params(query: [type: :string, optional: true])
      returns(users: [:map], count: :integer)
    end

    @doc "Resets the password for an existing account."
    action :reset_password do
      params(
        user_id: [type: :string, optional: true],
        player_id: [type: :string, optional: true],
        password: :string
      )

      returns(user_id: :string, player_id: :string, status: :string)
      errors([:user_not_found, :protected_admin_account, :invalid_password])
    end

    @doc "Updates authorization scopes/roles for a user account."
    action :update_user_roles do
      params(
        user_id: [type: :string, optional: true],
        player_id: [type: :string, optional: true],
        scopes: [type: :term, optional: true],
        role: [type: :string, optional: true]
      )

      returns(user_id: :string, player_id: :string, scopes: [:string])
      errors([:user_not_found, :protected_admin_account, :invalid_scopes])
    end

    @doc "Deletes a user account and associated auth credentials."
    action :delete_user do
      params(
        user_id: [type: :string, optional: true],
        player_id: [type: :string, optional: true]
      )

      returns(user_id: :string, player_id: :string, status: :string)
      errors([:user_not_found, :protected_admin_account])
    end

    @doc """
    Removes every account that was created disposable, and nothing else.

    A player is disposable because the caller said so when it registered — a test, a demo, a load
    run. Nothing is inferred, so this is safe to call on a live cluster: it removes the guests and
    leaves the players who signed up.
    """
    action :purge_disposable do
      params(dry_run: [type: :boolean, optional: true])
      returns(purged: :integer, dry_run: :boolean)
    end
  end

  defservice player_data do
    @moduledoc "Canonical player profile and state storage."

    @doc "Player profiles and account state."
    defresource Player, name: :players, primary_key: :player_id do
      column(:player_id, :string, label: "Player ID", sortable: true)
      column(:user_id, :string, label: "User ID", filterable: true)
      column(:name, :string, label: "Display Name", filterable: true)
      column(:level, :integer, label: "Level", sortable: true, default: 1)
      column(:status, :string, label: "Account Status", badge: true, default: "active")
      drawer([:overview, :attributes, :transactions, :inventory, :sessions, :events, :moderation])
      actions([:get_player, :create_player, :update_player, :delete_player, :list_players])
    end

    @doc "Retrieves player profile record."
    action :get_player do
      params(player_id: :string)
      returns(player: :map)
      errors([:player_not_found, :player_not_accessible])
    end

    @doc "Creates a player profile record, optionally linked to a user account."
    action :create_player do
      params(
        player_id: [type: :string, optional: true],
        user_id: [type: :string, optional: true],
        profile: [type: :map, optional: true]
      )

      returns(player: :map)
      errors([:invalid_attributes])
    end

    @doc "Deletes a player profile record."
    action :delete_player do
      params(player_id: :string)
      returns(status: :string, player_id: :string)
      errors([:player_not_found])
    end

    @doc "Unlinks user and marks player record as retained/orphaned for data retention policies."
    action :retain_player do
      params(player_id: :string)
      returns(status: :string, player_id: :string)
      errors([:player_not_found])
    end

    @doc "Lists all registered player profiles with optional filtering (all, valid, orphaned)."
    action :list_players do
      params(filter: [type: :string, optional: true])
      returns(players: [:map])
    end

    @doc "Updates player profile record."
    action :update_player do
      params(player_id: :string, data: :map)
      returns(player: :map)
      errors([:player_not_found, :invalid_attributes])
    end

    @doc "Retrieves a fine-grained key-value JSON state entry for a player."
    action :get_data do
      params(player_id: :string, key: :string)
      returns(key: :string, value: :term)
      errors([:player_not_found, :key_not_found])
    end

    @doc "Sets a fine-grained key-value JSON state entry for a player."
    action :set_data do
      params(player_id: :string, key: :string, value: :term)
      returns(key: :string, value: :term)
      errors([:player_not_found])
    end

    @doc "Deletes a fine-grained key-value JSON state entry for a player."
    action :delete_data do
      params(player_id: :string, key: :string)
      returns(key: :string, status: :string)
      errors([:player_not_found])
    end

    @doc "Retrieves all key-value state entries for a player as a map."
    action :get_all_data do
      params(player_id: :string)
      returns(data: :map)
      errors([:player_not_found])
    end

    @doc "Emitted when a new player account is created."
    event :player_created do
      payload(player_id: :string, timestamp: :integer)
      scope(:server)
    end

    @doc "Emitted when a player account is deleted."
    event :player_deleted do
      payload(player_id: :string, timestamp: :integer)
      scope(:server)
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

  defservice plugin_manager do
    @moduledoc "Lifecycle, deployment, and inspection of Exoforge plugins."

    @doc "Lists all registered plugins with their metadata and contracts."
    action :list_plugins do
      scope("studio")
      returns(plugins: [:map], count: :integer)
    end

    @doc "Retrieves details and contract metadata for a single plugin."
    action :get_plugin do
      scope("studio")
      params(id: :string)
      returns(plugin: :map)
      errors([:not_found])
    end

    @doc "Retrieves runtime node health, memory, and cluster stats."
    action :get_system_info do
      scope("studio")
      returns(system: :map)
    end

    @doc "Uploads and installs a new plugin (e.g. C# WASM package)."
    action :upload_plugin do
      scope("admin")

      params(
        name: :string,
        binary: :term,
        manifest: [type: :term, optional: true]
      )

      returns(plugin_id: :string, status: :string)
      errors([:invalid_package, :write_failed])
    end

    @doc "Removes an installed plugin."
    action :remove_plugin do
      scope("admin")
      params(id: :string)
      returns(status: :string)
      errors([:not_found])
    end

    @doc "Triggers a system re-index and reload of all plugins."
    action :restart_system do
      scope("admin")
      returns(status: :string, plugins_count: :integer)
    end

    @doc """
    Returns the most recent log lines a plugin emitted.

    Plugin output otherwise only reaches the server's Logger, which a developer working in Unity
    cannot see. Lines are held in memory and capped, so this is "what did my plugin just do?".
    """
    action :logs do
      scope("studio")
      params(id: :string, limit: [type: :integer, optional: true])
      returns(plugin_id: :string, lines: [:map], count: :integer)
      errors([:not_found])
    end

    @doc "Re-boots an installed plugin from its staged files, without re-uploading it."
    action :reload_plugin do
      scope("admin")
      params(id: :string)
      returns(plugin_id: :string, status: :string)
      errors([:not_found])
    end

    @doc "Exports the complete catalog of plugins and contracts for external tools (CLI/Unity)."
    action :export_plugin_info do
      scope("studio")
      returns(export: :map)
    end
  end

  defservice resource_store do
    @moduledoc "Schema-driven persistence for declared resources."

    @doc "Creates/updates the tables backing all declared resources (additive migrations)."
    action :migrate do
      params(resource: [type: :string, optional: true])
      returns(migrated: :integer)
    end

    @doc "Lists rows for a resource with filtering, sorting, and pagination."
    action :list do
      params(
        resource: :string,
        filter: [type: :map, optional: true],
        search: [type: :string, optional: true],
        sort: [type: :string, optional: true],
        limit: [type: :integer, optional: true],
        offset: [type: :integer, optional: true]
      )

      returns(rows: [:map], total: :integer)
    end

    @doc "Fetches one row by primary key."
    action :get do
      params(resource: :string, id: :term)
      returns(row: :map)
      errors([:not_found])
    end

    @doc "Creates a row."
    action :create do
      params(resource: :string, attributes: :map)
      returns(row: :map)
      errors([:invalid_attributes])
    end

    @doc "Updates a row by primary key."
    action :update do
      params(resource: :string, id: :term, attributes: :map)
      returns(row: :map)
      errors([:not_found])
    end

    @doc "Deletes a row by primary key."
    action :delete do
      params(resource: :string, id: :term)
      returns(deleted: :boolean)
    end

    @doc "Inserts or updates a row on conflict."
    action :upsert do
      params(resource: :string, attributes: :map)
      returns(row: :map)
    end

@doc "Removes every row of a resource, table-backed or KV-backed, without dropping the table."
    action :clear do
      params(resource: [type: :string, optional: true])
      returns(cleared: :integer)
    end

    @doc "Deletes a user account and associated auth credentials."
  end
end
