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
end
