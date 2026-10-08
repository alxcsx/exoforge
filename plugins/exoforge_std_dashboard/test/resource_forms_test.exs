defmodule Exoforge.Std.Dashboard.ResourceFormsTest do
  use ExUnit.Case, async: true

  alias Exoforge.Std.Dashboard.ResourceForms

  # The shape a manifest carries, which is what the form is built from.
  defp resource do
    %{
      name: :snake_scores,
      primary_key: :player_id,
      columns: [
        %{name: :player_id, type: :string, label: "Player ID"},
        %{name: :score, type: :integer, label: "High Score", badge: false},
        %{name: :verified, type: :boolean, label: "Verified"},
        %{name: :ratio, type: :float, label: "Ratio"}
      ]
    }
  end

  test "a column's declared default wins over the type's placeholder" do
    columns = ResourceForms.columns(%{
      name: :counters,
      primary_key: :id,
      columns: [
        %{name: :id, type: :integer},
        %{name: :status, type: :string, default: "active"}
      ]
    })

    defaults = ResourceForms.defaults(columns)

    # The plugin said what the value should be, and the schema heard it - which is why a column with
    # a default is not simply absent from every row the form writes.
    assert defaults["status"] == "active"
    assert defaults["id"] == "1"
  end

  test "columns come from the schema, with the primary key marked" do
    columns = ResourceForms.columns(resource())

    assert Enum.map(columns, & &1.key) == [:player_id, :score, :verified, :ratio]
    assert Enum.find(columns, & &1.primary_key).key == :player_id
    refute Enum.find(columns, &(&1.key == :score)).primary_key
    assert Enum.find(columns, &(&1.key == :score)).label == "High Score"
  end

  test "a resource with no columns falls back to nothing rather than guessing" do
    assert ResourceForms.columns(nil) == []
    assert ResourceForms.columns(%{name: :x}) == []
  end

  test "submitted strings become the types the schema declares" do
    columns = ResourceForms.columns(resource())

    attributes =
      ResourceForms.attributes(
        %{"player_id" => "p1", "score" => "42", "verified" => "true", "ratio" => "1.5"},
        columns
      )

    assert attributes == %{"player_id" => "p1", "score" => 42, "verified" => true, "ratio" => 1.5}
  end

  test "a blank input is left out, so the store's own default applies" do
    columns = ResourceForms.columns(resource())

    attributes = ResourceForms.attributes(%{"player_id" => "p1", "score" => "  "}, columns)

    # The boolean is still there: an unchecked box means false, which is a value. Only the blank
    # score is dropped, so the store's default for it applies.
    assert attributes == %{"player_id" => "p1", "verified" => false}
  end

  test "an unchecked boolean is false, not missing" do
    columns = ResourceForms.columns(resource())

    # A checkbox that is off submits nothing at all, which is different from "no opinion".
    attributes = ResourceForms.attributes(%{"player_id" => "p1"}, columns)

    assert attributes["verified"] == false
  end

  test "the primary key is required and nothing else is" do
    columns = ResourceForms.columns(resource())

    assert ResourceForms.errors(%{"score" => "1"}, columns) ==
             %{"player_id" => "Player ID is required"}

    assert ResourceForms.errors(%{"player_id" => "p1", "score" => ""}, columns) == %{}
  end

  test "editing pre-fills the form from the row" do
    columns = ResourceForms.columns(resource())

    values = ResourceForms.values_for(%{"player_id" => "p1", "score" => 42, "verified" => true}, columns)

    assert values["player_id"] == "p1"
    assert values["score"] == "42"
    assert values["verified"] == "true"
    # A column the row has no value for starts empty rather than at a default that would overwrite it.
    assert values["ratio"] == ""
  end
end
