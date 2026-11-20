defmodule Exoforge.Std.Services do
  @moduledoc "Registry of built-in Exoforge service contracts."
  import Exoforge.Contracts.Service

  defservice database do
    @moduledoc "General database service."

    @doc "Executes a driver-agnostic query or data operation."
    action :execute do
      scope(:server)

      params(
        operation: [type: :term],
        arguments: [type: :term, optional: true],
        plugin: [type: :term, optional: true]
      )

      returns(rows: [:map])
      errors([:syntax_error, :not_found, :unauthorized])
    end

    @doc "Lists the columns of a table in an extension's isolated database."
    action :table_columns do
      scope(:server)

      params(
        table: :string,
        plugin: [type: :term, optional: true]
      )

      returns(columns: [:string])
      errors([:not_found])
    end
  end

  defservice lldb do
    @moduledoc "Low-level database driver: one engine's connections, isolated namespaces and health. The engine is not named here (ADR 005)."

    @doc "Runs an operation inside a namespace: a SQL statement with arguments, or a key-value command."
    action :exec do
      scope(:server)

      params(
        operation: [type: :term],
        arguments: [type: :term, optional: true],
        namespace: [type: :term, optional: true]
      )

      returns(result: :term)
      errors([:syntax_error, :not_found, :unauthorized])
    end

    @doc "Creates, or refreshes, the isolated namespace (and its access rules) for an extension."
    action :provision_namespace do
      scope(:server)
      params(namespace: [type: :term, optional: true])
      returns(result: :term)
    end

    @doc "Removes an extension's namespace and everything in it."
    action :drop_namespace do
      scope(:server)
      params(namespace: [type: :term, optional: true])
      returns(result: :term)
    end

    @doc "Runs statements (SQL with positional arguments) in order in one transaction, all or nothing; a failure names the statement index."
    action :transaction do
      scope(:server)

      params(
        statements: [type: :term],
        namespace: [type: :term, optional: true]
      )

      returns(result: :term)
      errors([:syntax_error, :unauthorized])
    end

    @doc "Describes a table in engine-neutral terms: columns with logical types, nullability and the primary key."
    action :introspect do
      scope(:server)

      params(
        table: :string,
        namespace: [type: :term, optional: true]
      )

      returns(result: :term)
    end

    @doc "How to write SQL for this engine: placeholder and quoting style, upsert strategy and type names."
    action :dialect do
      scope(:server)
      returns(result: :term)
    end

    @doc "Applies the safe changes that bring a namespace's tables in line with declared resources (logical `storage` types); an unsafe change applies nothing and is reported."
    action :apply_schema do
      scope(:server)

      params(
        resources: [type: :term, optional: true],
        migrations: [type: :term, optional: true],
        version: [type: :integer, optional: true],
        namespace: [type: :term, optional: true]
      )

      returns(result: :term)
    end

    @doc "Applies an extension's hand-written SQL migrations in version order."
    action :run_migrations do
      scope(:server)

      params(
        namespace: [type: :term, optional: true],
        migrations: [type: :term, optional: true]
      )

      returns(result: :term)
    end

    @doc "Drops a table of a namespace, and its schema history."
    action :reset_table do
      scope(:server)

      params(
        table: :string,
        namespace: [type: :term, optional: true]
      )

      returns(result: :term)
    end

    @doc "Lists the columns of a table in a namespace."
    action :table_columns do
      scope(:server)

      params(
        table: :string,
        namespace: [type: :term, optional: true]
      )

      returns(columns: [:string])
      errors([:not_found])
    end

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

  defservice observability do
    @moduledoc "Cluster event history, failure groups and request timelines."

    @doc "The most recent cluster events, newest first."
    action :recent_events do
      params(limit: [type: :integer, optional: true])
      returns(events: [:map])
      scope("studio")
    end

    @doc "Failures grouped by fingerprint: counts, first/last seen, callers, and a sample request."
    action :error_groups do
      params(
        service: [type: :string, optional: true],
        action: [type: :string, optional: true],
        caller: [type: :string, optional: true],
        rid: [type: :string, optional: true],
        limit: [type: :integer, optional: true]
      )

      returns(groups: [:map], count: :integer)
      scope("studio")
    end

    @doc "Starts a deep capture for one player, one action, or the whole cluster, for a few minutes."
    action :capture do
      params(
        kind: [type: :string, optional: true],
        value: [type: :string, optional: true],
        seconds: [type: :integer, optional: true]
      )

      returns(capture: :map)
      scope("studio")
    end

    @doc "The active deep captures, with their remaining seconds."
    action :captures do
      returns(captures: [:map])
      scope("studio")
    end

    @doc "Stops one capture (or every capture when kind is global and the value is blank)."
    action :stop_capture do
      params(
        kind: [type: :string, optional: true],
        value: [type: :string, optional: true]
      )

      returns(status: :string)
      scope("studio")
    end

    @doc "Replays a captured invocation's full request as the caller who made it."
    action :replay do
      params(id: :term)
      returns(source_rid: :string, rid: :string, status: :map, data: :term)
      scope("studio")
    end

    @doc "Per-action health: 30-minute rates, lifetime p50/p95, and what needs attention."
    action :health do
      params(limit: [type: :integer, optional: true])
      returns(rows: [:map], attention: [:map])
      scope("studio")
    end

    @doc "One page of stored events, filtered; ranges older than the hot window come from the archive."
    action :events do
      params(
        rid: [type: :string, optional: true],
        player: [type: :string, optional: true],
        event: [type: :string, optional: true],
        status: [type: :string, optional: true],
        since_ms: [type: :integer, optional: true],
        until_ms: [type: :integer, optional: true],
        limit: [type: :integer, optional: true],
        offset: [type: :integer, optional: true]
      )

      returns(events: [:map], total: :integer, capped: :boolean)
      scope("studio")
    end

    @doc "One request's timeline (or one caller's recent activity): calls, events, logs and failures."
    action :timeline do
      params(
        rid: [type: :string, optional: true],
        player: [type: :string, optional: true],
        since_ms: [type: :integer, optional: true],
        limit: [type: :integer, optional: true]
      )

      returns(nodes: [:map], count: :integer)
      scope("studio")
    end

    @doc "Drops the in-memory ring and the persisted event history."
    action :clear_events do
      returns(status: :string)
      scope("admin")
    end

    @doc "Drops one caller's hot events (account deletion); archived files are left untouched."
    action :purge_events do
      params(origin: :string)
      returns(status: :string)
      scope("admin")
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

    @doc "Retrieves global project metadata."
    action :get_project_metadata do
      returns(
        project_name: :string,
        studio_name: :string,
        description: :string,
        website_url: :string,
        custom: :map,
        updated_at: :integer
      )

      scope(:studio)
    end

    @doc "Updates global project metadata."
    action :update_project_metadata do
      params(
        project_name: [type: :string, optional: true],
        studio_name: [type: :string, optional: true],
        description: [type: :string, optional: true],
        website_url: [type: :string, optional: true],
        custom: [type: :map, optional: true]
      )

      returns(metadata: :map)
      scope(:admin)
    end

    @doc "Broadcast when project metadata is updated."
    event :project_metadata_updated do
      payload(metadata: :map)
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
      errors([:invalid_token, :token_expired])
    end

    @doc "Exchanges a refresh token for a fresh access/refresh pair."
    action :refresh do
      params(token: :string)
      returns(player_id: :string, token: :string, refresh_token: :string, expires_in: :integer)
      errors([:invalid_token, :token_expired])
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
        required_scope: :string,
        user_id: [type: :string, optional: true],
        player_id: [type: :string, optional: true]
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
      errors([:invalid_attributes, :registration_failed, :unauthorized])
    end

    @doc "Sets the signed-in player's display name."
    action :set_display_name do
      params(name: :string, player_id: [type: :string, optional: true])
      returns(player_id: :string, name: :string)
      errors([:unauthorized, :invalid_attributes, :player_not_found])
    end

    @doc """
    Issues a service token for an existing user or player account.

    The token carries the account's scopes as they are when it authenticates; the `scopes`
    parameter is accepted for older callers and ignored.
    """
    action :issue_token do
      # Mints tokens - admin only (M33 Fix 3).
      scope("admin")

      params(
        player_id: :string,
        user_id: [type: :string, optional: true],
        scopes: [type: :term, optional: true],
        expires_in: [type: :integer, optional: true]
      )

      returns(
        token: :string,
        user_id: :string,
        player_id: :string,
        token_id: :string,
        expires_at: :string,
        expires_in: :integer
      )

      errors([:invalid_player, :unknown_user])
    end

    @doc "Lists the tokens issued for an account: id, kind, creation, last use and expiry."
    action :list_tokens do
      scope("admin")

      params(
        user_id: [type: :string, optional: true],
        player_id: [type: :string, optional: true]
      )

      returns(tokens: [:map], count: :integer)
    end

    @doc "Revokes a token (and the session it belongs to)."
    action :revoke_token do
      scope("admin")
      params(token_id: :string)
      returns(token_id: :string, status: :string)
      errors([:token_not_found])
    end

    @doc "Deletes expired and revoked token rows. Cron calls this."
    action :purge_tokens do
      scope(:server)
      returns(purged: :integer)
    end

    @doc """
    Removes every token that has expired or been revoked.

    Credentials are rows with a lifetime: an access token after an hour, a refresh token after a
    month, a service token after its term. Deleting the dead ones is what keeps the table, and the
    account listing built from it, a picture of live sessions rather than a history of them.
    """
    cron :purge_tokens do
      schedule("17 * * * *")
      description("Deletes expired and revoked token rows.")
    end

    @doc "Lists all registered user accounts and their assigned authorization scopes."
    action :list_users do
      scope("studio")

      params(
        query: [type: :string, optional: true],
        limit: [type: :integer, optional: true]
      )

      returns(users: [:map], count: :integer)
    end

    @doc "Resets the password for an existing account."
    action :reset_password do
      scope("admin")

      params(
        password: :string,
        user_id: [type: :string, optional: true],
        player_id: [type: :string, optional: true]
      )

      returns(user_id: :string, player_id: :string, status: :string)
      errors([:user_not_found, :protected_admin_account, :invalid_password])
    end

    @doc "Updates authorization scopes/roles for a user account."
    action :update_user_roles do
      scope("admin")

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
      scope("admin")

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
      scope("admin")

      params(player_id: :string)
      returns(status: :string, player_id: :string)
      errors([:player_not_found])
    end

    @doc "Unlinks user and marks player record as retained/orphaned for data retention policies."
    action :retain_player do
      scope("admin")

      params(player_id: :string)
      returns(status: :string, player_id: :string)
      errors([:player_not_found])
    end

    @doc "Lists all registered player profiles with optional filtering (all, valid, orphaned)."
    action :list_players do
      scope("studio")

      params(
        filter: [type: :string, optional: true],
        user_id: [type: :string, optional: true],
        limit: [type: :integer, optional: true]
      )

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
      scope(:studio)
      params(topic: :string, event: :string, payload: :map)
      returns(status: :string)
    end

    @doc "Retrieves current active WebSocket connection count."
    action :connection_count do
      scope(:studio)
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

  defservice transport do
    @moduledoc "Transport abstraction layer for ingress network gateways."

    @doc "Returns transport layer status."
    action :status do
      returns(status: :string, layer: :string)
    end
  end

  defservice cron do
    @moduledoc "Scheduled job execution and recurring cron runner."

    @doc "Returns status and count of active cron jobs."
    action :status do
      scope(:studio)
      returns(status: :string, active_jobs: :integer)
    end

    @doc "Lists all scheduled cron jobs."
    action :list_jobs do
      scope("studio")
      returns(jobs: [:map], count: :integer)
    end

    @doc "Manually triggers a scheduled job by its name or id."
    action :trigger_job do
      scope("studio")
      params(job_id: :string)
      returns(status: :string)
    end
  end

  defservice extension_manager do
    @moduledoc "Lifecycle, deployment, and inspection of Exoforge extensions."

    @doc "Lists all registered extensions with their metadata and contracts."
    action :list_extensions do
      scope("studio")
      returns(extensions: [:map], count: :integer)
    end

    @doc "Retrieves details and contract metadata for a single extension."
    action :get_extension do
      scope("studio")
      params(id: :string)
      returns(extension: :map)
      errors([:not_found])
    end

    @doc "Retrieves runtime node health, memory, and cluster stats."
    action :get_system_info do
      scope("studio")
      returns(system: :map)
    end

    @doc "Uploads and installs a new extension binary."
    action :upload_extension do
      scope("admin")

      params(
        name: :string,
        binary: :term,
        manifest: [type: :term, optional: true]
      )

      returns(extension_id: :string, status: :string)
      errors([:invalid_package, :write_failed])
    end

    @doc "Removes an installed extension."
    action :remove_extension do
      scope("admin")
      params(id: :string)
      returns(status: :string)
      errors([:not_found])
    end

    @doc "Triggers a system re-index and reload of all extensions."
    action :restart_system do
      scope("admin")
      returns(status: :string, extensions_count: :integer)
    end

    @doc "Returns the most recent log lines an extension emitted."
    action :logs do
      scope("studio")
      params(id: :string, limit: [type: :integer, optional: true])
      returns(extension_id: :string, lines: [:map], count: :integer)
      errors([:not_found])
    end

    @doc "Re-boots an installed extension from its staged files, without re-uploading it."
    action :reload_extension do
      scope("admin")
      params(id: :string)
      returns(extension_id: :string, status: :string)
      errors([:not_found])
    end

    @doc "Exports the complete catalog of extensions and contracts for external tools (CLI/Unity)."
    action :export_extension_info do
      scope("studio")
      returns(export: :map)
    end

    @doc "Exports C# companion attributes and types provided by loaded extensions."
    action :csharp_attributes do
      scope(:studio)
      returns(files: [:map], count: :integer)
    end
  end

  defservice resource_store do
    @moduledoc "Schema-driven persistence for declared resources."

    @doc "Creates/updates the tables backing all declared resources (additive migrations)."
    action :migrate do
      scope(:studio)
      params(resource: [type: :string, optional: true], extension: [type: :string, optional: true])
      returns(migrated: :integer)
    end

    @doc "Provisioning step before an extension starts: makes the tables of its typed resources (those that declare column storage types)."
    action :provision do
      scope(:studio)
      params(extension: [type: :string, optional: true])
      returns(provisioned: :integer)
    end

    @doc "Lists rows for a resource with filtering, sorting, and pagination."
    action :list do
      scope(:player)

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
      scope(:player)
      # `optional: true` turns a missing row into `{:ok, %{row: nil}}` instead of an error: a
      # lookup that is allowed to miss must not land in the error groups.
      params(resource: :string, id: :term, optional: [type: :boolean, optional: true])
      returns(row: :map)
      errors([:not_found])
    end

    @doc "Creates a row."
    action :create do
      scope(:studio)
      params(resource: :string, attributes: :map)
      returns(row: :map)
      errors([:invalid_attributes])
    end

    @doc "Updates a row by primary key."
    action :update do
      scope(:studio)
      params(resource: :string, id: :term, attributes: :map)
      returns(row: :map)
      errors([:not_found])
    end

    @doc "Deletes a row by primary key."
    action :delete do
      scope(:studio)
      params(resource: :string, id: :term)
      returns(deleted: :boolean)
    end

    @doc "Inserts or updates a row on conflict."
    action :upsert do
      scope(:studio)
      params(resource: :string, attributes: :map)
      returns(row: :map)
    end

    @doc "Removes every row of a resource, table-backed or KV-backed, without dropping the table."
    action :clear do
      scope(:studio)
      params(resource: [type: :string, optional: true])
      returns(cleared: :integer)
    end

    @doc "Deletes a user account and associated auth credentials."
  end

  defservice metering do
    @moduledoc "Local usage metering: what each extension was called with, and what it cost."

    @doc "Rolls up persisted usage per extension and action for this title."
    action :usage do
      scope(:studio)

      params(
        plugin_id: [type: :string, optional: true],
        since: [type: :integer, optional: true]
      )

      returns(title_id: :string, studio_id: :string, plugins: [:map], totals: :map)
    end
  end

  defservice versioning do
    @moduledoc """
    Game versions: which release is live, which is still served, and which extension version each one locks.

    A game version moves `dev` -> `live` -> `outdated` -> `blocked`. At most `max_active_versions`
    (default 3) are not blocked; registering or promoting past that blocks the oldest `outdated` one.
    """

    @doc "Registers a game version in `dev`, with the extension versions it locks."
    action :register do
      scope(:studio)
      params(version: :string, locks: [type: :map, optional: true])
      returns(version: :string, status: :string, blocked: [:string])
      errors([:already_exists, :invalid_version, :too_many_active])
    end

    @doc "Changes the locks of a `dev` game version. Live, outdated and blocked versions are immutable."
    action :set_locks do
      scope(:studio)
      params(version: :string, locks: :map)
      returns(version: :string, status: :string)
      errors([:not_found, :invalid_locks, :locks_immutable])
    end

    @doc "Makes a `dev` game version live. The previous live one becomes `outdated`."
    action :promote do
      scope(:studio)
      params(version: :string)
      returns(version: :string, status: :string, blocked: [:string])
      errors([:not_found, :invalid_transition])
    end

    @doc "Blocks a game version: its clients are told to upgrade."
    action :block do
      scope(:studio)
      params(version: :string)
      returns(version: :string, status: :string)
      errors([:not_found])
    end

    @doc "Lists game versions, newest first."
    action :list do
      scope(:studio)
      returns(versions: [:map])
    end

    @doc "Status and extension locks of one game version, as a client reports it."
    action :resolve do
      scope(:player)
      params(version: :string)
      returns(version: :string, status: :string, locks: :map)
      errors([:not_found])
    end
  end

  defservice file_bucket do
    @moduledoc """
    Cluster file storage and retrieval engine for binary assets, uploads, and blobs.

    Raw file actions are staff-only. Players reach files only through an extension that applies
    its own rules, which stores files internally and hands out `signed_url/1` links.
    """

    @doc "Stores a file in a specified bucket from raw binary or base64 content."
    action :upload_file do
      scope(:studio)

      params(
        filename: :string,
        bucket: [type: :string, optional: true],
        content: :term,
        content_type: [type: :string, optional: true],
        metadata: [type: :map, optional: true]
      )

      returns(file: :map)
      errors([:invalid_payload, :write_failed])
    end

    @doc "Retrieves metadata and local storage path for a file."
    action :get_file_info do
      scope(:studio)

      params(
        id: :string,
        bucket: [type: :string, optional: true]
      )

      returns(file: :map)
      errors([:not_found])
    end

    @doc "Reads raw binary content of a file."
    action :read_file do
      scope(:studio)

      params(
        id: :string,
        bucket: [type: :string, optional: true]
      )

      returns(content: :term, file: :map)
      errors([:not_found, :read_failed])
    end

    @doc "Lists stored files within a bucket or across all buckets."
    action :list_files do
      scope(:studio)

      params(
        bucket: [type: :string, optional: true],
        limit: [type: :integer, optional: true],
        offset: [type: :integer, optional: true]
      )

      returns(files: [:map], count: :integer)
    end

    @doc "Lists all storage buckets with their visibility (`public` or `private`)."
    action :list_buckets do
      scope(:studio)
      params()
      returns(buckets: [:map])
    end

    @doc """
    Sets a bucket's visibility. `public` lets anyone download its files by URL; `private` (the
    default) serves them only to staff or through a `signed_url`. Staff-only; an extension that owns
    a bucket resolves its own files and marks the bucket public at start.
    """
    action :set_bucket_visibility do
      scope(:studio)
      params(bucket: :string, visibility: :string)
      returns(bucket: :string, visibility: :string)
      errors([:invalid_payload])
    end

    @doc "Modifies an existing file's name, metadata, or content."
    action :update_file do
      scope(:studio)

      params(
        id: :string,
        bucket: [type: :string, optional: true],
        filename: [type: :string, optional: true],
        content: [type: :term, optional: true],
        content_type: [type: :string, optional: true],
        metadata: [type: :map, optional: true]
      )

      returns(file: :map)
      errors([:not_found, :write_failed])
    end

    @doc """
    Returns a time-limited download URL for one file. Server-only: an extension decides who may
    read a file and mints the link; the HTTP file route accepts it without a token until it expires.
    """
    action :signed_url do
      scope(:server)

      params(
        id: :string,
        bucket: [type: :string, optional: true],
        ttl_seconds: [type: :integer, optional: true]
      )

      returns(url: :string, expires_at: :integer)
      errors([:not_found])
    end

    @doc "Whether an unauthenticated download may be served: a public bucket, or a valid signed URL."
    action :authorize_download do
      scope(:server)

      params(
        bucket: :string,
        id: :string,
        exp: [type: :string, optional: true],
        sig: [type: :string, optional: true]
      )

      returns(allowed: :boolean)
    end

    @doc "Deletes a stored file."
    action :delete_file do
      scope(:studio)

      params(
        id: :string,
        bucket: [type: :string, optional: true]
      )

      returns(deleted: :boolean)
      errors([:not_found])
    end
  end

  defservice docs do
    @moduledoc "Developer Guide, documentation chapters, and dynamic API reference."

    @doc "Lists all available documentation chapters."
    action :list_chapters do
      scope(:studio)
      returns(chapters: [:map])
    end

    @doc "Retrieves the content of a specific documentation chapter."
    action :get_chapter do
      scope(:studio)
      params(id: :string)
      returns(chapter: :map)
      errors([:not_found])
    end

    @doc "Exports the consolidated documentation and dynamic API reference as Markdown or HTML."
    action :export_docs do
      scope(:studio)
      params(format: [type: :string, optional: true])
      returns(title: :string, content: :string, format: :string)
    end
  end
end
