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
end
