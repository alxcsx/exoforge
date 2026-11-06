defmodule Exoforge.Std.DashboardViews.UserForms do
  @moduledoc """
  Turns the Studio's user forms into `:auth` payloads.

  Blank optional fields, the role → scope mapping, and the password rules are pure decisions that
  used to sit inside LiveView handlers, reachable only by driving the UI. They live here so they
  can be tested directly.
  """

  alias Exoforge.Auth.Roles

  @doc """
  Payload for `auth.register`.

  Blank fields are omitted rather than sent as empty strings: the auth service would otherwise
  create an account with an empty name or email.
  """
  def registration_payload(params) do
    user_id = value(params, "user_id", value(params, "player_id"))
    name = value(params, "name")
    email = value(params, "email")
    password = value(params, "password")
    role = value(params, "role", "player")

    %{
      user_id: presence(user_id),
      player_id: presence(user_id),
      name: presence(name),
      email: presence(email),
      password: presence(password),
      role: role,
      scopes: Roles.scopes_for_role(role)
    }
  end

  @doc """
  Validates a password reset, returning the payload for `auth.reset_password`.

  A missing selection is reported before the empty-password case, so the message matches what the
  user can actually fix.
  """
  def reset_password(nil, _new_password), do: {:error, "No user selected."}

  def reset_password(_user, new_password) do
    case String.trim(new_password || "") do
      "" -> {:error, "Password cannot be empty."}
      trimmed -> {:ok, %{player_id: nil, password: trimmed}}
    end
  end

  @doc "The reset payload for a selected user, or an explanation of what is wrong."
  def reset_password_for(user, new_password) do
    case reset_password(user, new_password) do
      {:ok, payload} -> {:ok, %{payload | player_id: user["player_id"]}}
      error -> error
    end
  end

  @doc """
  Human-readable reason for a failed auth action.

  A couple of failures are worth explaining rather than echoing an atom at the user.
  """
  def failure_message(:protected_admin_account),
    do: "Cannot reset password of the protected environment admin."

  def failure_message(reason), do: inspect(reason)

  @doc "A user's display name, falling back to their id when they never set one."
  def display_name(name, fallback) do
    case presence(name) do
      nil -> fallback
      name -> name
    end
  end

  defp value(params, key, default \\ ""), do: String.trim(Map.get(params, key, default) || "")

  defp presence(""), do: nil
  defp presence(value), do: value
end
