defmodule Exoforge.Auth.Roles do
  @moduledoc """
  Shared role hierarchy for authorization across the kernel and transports.

  Roles are expressed as scopes carried by a caller's auth context:

      admin > studio > player > guest

  A caller may run an action whose declared scope is at or below their own rank.
  `admin` is the only role that can run `admin`-scoped actions; `studio` can run
  `studio`/`player`/`global`; `player` can run `player`/`global`.
  """

  @admin "admin"
  @studio "studio"
  @player "player"
  @guest "guest"

  @rank %{@admin => 3, @studio => 2, @player => 1, @guest => 0}

  @doc "Canonical role names."
  def admin, do: @admin
  def studio, do: @studio
  def player, do: @player
  def guest, do: @guest

  @doc "Numeric rank for a single scope name."
  def rank(scope), do: Map.get(@rank, to_string(scope), 0)

  @doc "Highest rank held by a caller's scope list."
  def rank_of(scopes) do
    scopes
    |> List.wrap()
    |> Enum.map(&rank/1)
    |> Enum.max(fn -> 0 end)
  end

  @doc "Single role label for a caller's scope list."
  def role(scopes) do
    scopes = Enum.map(List.wrap(scopes), &to_string/1)

    cond do
      @admin in scopes -> :admin
      @studio in scopes -> :studio
      @player in scopes -> :player
      true -> :guest
    end
  end

  @doc "True when the caller's scopes satisfy the required scope."
  def satisfies?(scopes, required), do: rank_of(scopes) >= rank(required)

  @doc "True when the caller's scope list contains the given role."
  def has?(scopes, role), do: to_string(role) in Enum.map(List.wrap(scopes), &to_string/1)

  @service "service"
  def service, do: @service

  @doc """
  Every scope an action may declare.

  `:server` means "never reachable from a transport" — the dispatcher rejects it for any external
  caller and only kernel-internal calls (which pass `caller_scopes: :internal`) get through.
  """
  @action_scopes [@admin, @studio, @player, @guest, @service, "server", "global"]

  def action_scopes, do: @action_scopes

  @doc "True when `scope` is a scope an action may declare."
  def action_scope?(scope), do: to_string(scope) in @action_scopes

  @doc """
  Compile-time guard for the action DSLs.

  A mistyped scope is otherwise silent: the dispatcher ranks unknown scopes at 0, so
  `scope: "stduio"` would quietly mean "guest" instead of "studio". Expressions (the
  `Exoforge.Auth.Roles.studio()` form) are left to the compiler to resolve.
  """
  def validate_action_scope!(scope, context) do
    if (is_binary(scope) or is_atom(scope)) and not action_scope?(scope) do
      raise CompileError,
        description:
          "Unknown scope #{inspect(scope)} for #{context}. " <>
            "Known scopes: #{inspect(@action_scopes)}"
    end

    scope
  end

  @role_scopes %{
    "admin" => ["admin", "service", "studio", "player", "write", "read"],
    "studio" => ["studio", "write", "read"],
    "service" => ["service", "write", "read"],
    "player" => ["player", "read", "write"],
    "guest" => ["read"]
  }

  @doc "Fixed authorization roles with multi-scope mappings. Admin grants all scopes."
  def scopes_for_role(role) do
    Map.get(@role_scopes, to_string(role), ["read"])
  end

  @doc "Identifies the highest role matching the given scopes."
  def role_from_scopes(scopes) do
    list = Enum.map(List.wrap(scopes), &to_string/1)

    cond do
      "admin" in list -> "admin"
      "studio" in list -> "studio"
      "service" in list -> "service"
      "player" in list -> "player"
      true -> "guest"
    end
  end

  @doc "Predefined role options for dropdown selection."
  def available_roles do
    [
      %{id: "admin", label: "Admin (Full Access - All Scopes)", scopes: scopes_for_role("admin")},
      %{id: "studio", label: "Studio / Developer (Studio, Write, Read)", scopes: scopes_for_role("studio")},
      %{id: "service", label: "Service / Worker (Service, Write, Read)", scopes: scopes_for_role("service")},
      %{id: "player", label: "Player / User (Player, Read, Write)", scopes: scopes_for_role("player")},
      %{id: "guest", label: "Guest (Read Only)", scopes: scopes_for_role("guest")}
    ]
  end
end
