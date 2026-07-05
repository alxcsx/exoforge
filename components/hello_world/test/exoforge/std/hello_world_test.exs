defmodule Exoforge.Std.HelloWorldTest do
  use ExUnit.Case
  doctest Exoforge.Std.HelloWorld

  test "greets the world" do
    assert Exoforge.Std.HelloWorld.hello() == :world
  end
end
