defmodule Exoforge.Std.Dashboard.ActionFormsTest do
  use ExUnit.Case, async: true

  alias Exoforge.Std.Dashboard.ActionForms

  # Shape matches what Extensions.normalize_action_params/1 produces.
  defp action(params) do
    %{name: "submit_score", doc: "d", mode: "sync", params: params}
  end

  describe "cast/2" do
    test "coerces the declared type, not the string" do
      assert ActionForms.cast("42", :integer) == 42
      assert ActionForms.cast(" 7 ", :integer) == 7
      assert ActionForms.cast("1.5", :float) == 1.5
      assert ActionForms.cast("true", :boolean) == true
      assert ActionForms.cast("YES", :boolean) == true
      assert ActionForms.cast("false", :boolean) == false
      assert ActionForms.cast(~s({"a":1}), :map) == %{"a" => 1}
      assert ActionForms.cast("hello", :string) == "hello"
    end

    test "unparseable values fall back to the type's zero value rather than raising" do
      assert ActionForms.cast("not-a-number", :integer) == 0
      assert ActionForms.cast("", :integer) == 0
      assert ActionForms.cast("not-a-float", :float) == 0.0
      assert ActionForms.cast("not json", :map) == %{}
      assert ActionForms.cast("[1,2]", :map) == %{}
    end

    test "passes through a value that is already typed" do
      assert ActionForms.cast(42, :integer) == 42
      assert ActionForms.cast(nil, :string) == nil
    end

    test "an undeclared type is left alone" do
      assert ActionForms.cast("anything", :term) == "anything"
      assert ActionForms.cast("anything", nil) == "anything"
    end
  end

  describe "default_params/1" do
    test "opens the form with a value the contract will accept" do
      defaults =
        ActionForms.default_params(
          action([
            %{name: "score", type: :integer},
            %{name: "name", type: :string},
            %{name: "flag", type: :boolean},
            %{name: "blob", type: :map}
          ])
        )

      assert defaults == %{"score" => "1", "name" => "", "flag" => "true", "blob" => "{}"}
    end

    test "no action means no params" do
      assert ActionForms.default_params(nil) == %{}
    end
  end

  describe "build_payload/2" do
    test "produces a typed payload keyed by the declared param names" do
      payload =
        ActionForms.build_payload(
          action([%{name: "player_id", type: :string}, %{name: "score", type: :integer}]),
          %{"player_id" => "p1", "score" => "12"}
        )

      assert payload == %{player_id: "p1", score: 12}
    end

    test "a param missing from the form becomes its zero value" do
      payload = ActionForms.build_payload(action([%{name: "score", type: :integer}]), %{})
      assert payload == %{score: 0}
    end

    test "an optional field left empty is not sent, so the action's own default applies" do
      action = action([%{name: "limit", type: :integer, optional: true}, %{name: "since", type: :integer, optional: true}, %{name: "id", type: :string}])

      assert ActionForms.build_payload(action, %{"limit" => "", "since" => "5", "id" => ""}) == %{since: 5, id: ""}
      assert ActionForms.default_params(action) == %{"limit" => "", "since" => "", "id" => ""}
    end

    test "no action means an empty payload" do
      assert ActionForms.build_payload(nil, %{"x" => "1"}) == %{}
    end
  end

  describe "parse_scopes/1" do
    test "splits and trims a comma-separated list" do
      assert ActionForms.parse_scopes("studio, player") == ["studio", "player"]
    end

    test "empty means admin, so the console is not rejected before the action runs" do
      assert ActionForms.parse_scopes("") == ["admin"]
      assert ActionForms.parse_scopes(nil) == ["admin"]
      assert ActionForms.parse_scopes(" , ") == ["admin"]
    end
  end

  describe "service/2 and action/2" do
    setup do
      catalog = [
        %{name: "alpha", actions: [%{name: "one"}, %{name: "two"}]},
        %{name: "beta", actions: [%{name: "three"}]}
      ]

      %{catalog: catalog}
    end

    test "finds by name, falling back to the first", %{catalog: catalog} do
      assert ActionForms.service(catalog, "beta").name == "beta"
      assert ActionForms.service(catalog, "nope").name == "alpha"
      assert ActionForms.service(catalog, nil).name == "alpha"
    end

    test "an action inside a service, falling back to the first", %{catalog: catalog} do
      alpha = ActionForms.service(catalog, "alpha")

      assert ActionForms.action(alpha, "two").name == "two"
      assert ActionForms.action(alpha, "nope").name == "one"
      assert ActionForms.action(alpha, nil).name == "one"
    end

    test "no service means no action" do
      assert ActionForms.action(nil, "one") == nil
    end

    test "an empty catalog is handled", do: assert(ActionForms.service([], "x") == nil)
  end
  describe "what an action does, from its name" do
    test "reads, changes and destructive actions are told apart" do
      assert ActionForms.action_kind(:list_users) == :read
      assert ActionForms.action_kind("get_config") == :read
      assert ActionForms.action_kind(:error_groups) == :read
      assert ActionForms.action_kind(:table_columns) == :read
      assert ActionForms.action_kind(:introspect) == :read
      assert ActionForms.action_kind(:reset_table) == :destructive
      assert ActionForms.action_kind(:set_locks) == :write
      assert ActionForms.action_kind(:delete_user) == :destructive
      # any word of the name counts, not only the first
      assert ActionForms.action_kind(:user_purge) == :destructive
      assert ActionForms.action_kind(:stop_capture) == :destructive
      # a word that merely contains a verb is not that verb
      assert ActionForms.action_kind(:listener_status) == :write
    end

    test "actions are grouped look, change, dangerous, in the contract's order, and empty groups are dropped" do
      actions = [%{name: :delete_user}, %{name: :register}, %{name: :list_users}, %{name: :get_user}]

      assert [{:read, "Look", reads}, {:write, "Change", writes}, {:destructive, "Dangerous", danger}] =
               ActionForms.group_actions(actions)

      assert Enum.map(reads, & &1.name) == [:list_users, :get_user]
      assert Enum.map(writes, & &1.name) == [:register]
      assert Enum.map(danger, & &1.name) == [:delete_user]

      assert [{:write, "Change", _}] = ActionForms.group_actions([%{name: :register}])
    end
  end
end
