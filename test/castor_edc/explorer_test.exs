defmodule CastorEDC.ExplorerTest do
  use ExUnit.Case
  doctest CastorEDC.Explorer

  test "greets the world" do
    assert CastorEDC.Explorer.hello() == :world
  end
end
