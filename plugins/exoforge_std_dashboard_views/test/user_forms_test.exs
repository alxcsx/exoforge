defmodule Exoforge.Std.DashboardViews.UserFormsTest do
  use ExUnit.Case, async: true

  alias Exoforge.Std.DashboardViews.UserForms

  describe "registration_payload/1" do
    test "maps a role to its scopes" do
      payload = UserForms.registration_payload(%{"role" => "studio"})

      assert payload.role == "studio"
      assert payload.scopes == Exoforge.Auth.Roles.scopes_for_role("studio")
    end

    test "defaults to the player role" do
      assert UserForms.registration_payload(%{}).role == "player"
    end

    test "blank optional fields are omitted, not sent as empty strings" do
      payload =
        UserForms.registration_payload(%{
          "user_id" => "u1",
          "name" => "  ",
          "email" => "",
          "password" => "  secret  "
        })

      assert payload.user_id == "u1"
      assert payload.player_id == "u1"
      assert payload.name == nil
      assert payload.email == nil
      assert payload.password == "secret"
    end

    test "player_id falls back to user_id when only that is supplied" do
      assert UserForms.registration_payload(%{"player_id" => "p1"}).user_id == "p1"
    end
  end

  describe "reset_password_for/2" do
    test "reports a missing selection first" do
      assert {:error, message} = UserForms.reset_password_for(nil, "new")
      assert message =~ "No user selected"
    end

    test "rejects an empty or whitespace password" do
      assert {:error, message} = UserForms.reset_password_for(%{"player_id" => "p1"}, "   ")
      assert message =~ "cannot be empty"
    end

    test "builds the payload for the selected user" do
      assert {:ok, payload} =
               UserForms.reset_password_for(%{"player_id" => "p1"}, "  new-pass  ")

      assert payload == %{player_id: "p1", password: "new-pass"}
    end

    test "a nil password is treated as empty rather than crashing" do
      assert {:error, _} = UserForms.reset_password_for(%{"player_id" => "p1"}, nil)
    end
  end

  describe "failure_message/1" do
    test "explains the protected admin case" do
      assert UserForms.failure_message(:protected_admin_account) =~ "protected environment admin"
    end

    test "everything else is echoed" do
      assert UserForms.failure_message(:invalid_attributes) == ":invalid_attributes"
    end
  end

  describe "display_name/2" do
    test "prefers a real name and falls back to the id" do
      assert UserForms.display_name("Viper", "u1") == "Viper"
      assert UserForms.display_name(nil, "u1") == "u1"
      assert UserForms.display_name("", "u1") == "u1"
    end
  end
end
