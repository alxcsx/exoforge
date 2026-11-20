defmodule Exoforge.VersionStampTest do
  use ExUnit.Case, async: true

  alias Exoforge.VersionStamp

  test "an extension version encodes so that order is numeric order" do
    assert VersionStamp.encode("2.1.0") == 2_001_000
    assert VersionStamp.encode("0.1.0") == 1_000
    assert VersionStamp.encode("10.20.30") == 10_020_030
    assert VersionStamp.encode("1.10.0") > VersionStamp.encode("1.2.0")
  end

  test "anything that is not MAJOR.MINOR.PATCH encodes to 0" do
    for bad <- ["nonsense", "1.2", "1.2.3.4", "1.1000.0", "-1.0.0", "", nil, 5] do
      assert VersionStamp.encode(bad) == 0, inspect(bad)
    end
  end

  test "a pre-release or build suffix is the release for ordering purposes" do
    assert VersionStamp.encode("1.4.0-beta.1") == 1_004_000
    assert VersionStamp.encode("1.4.0+build5") == 1_004_000
  end

  test "decode is the inverse, and a stamp of 0 has no version" do
    assert VersionStamp.decode(2_001_000) == "2.1.0"
    assert VersionStamp.decode(VersionStamp.encode("10.20.30")) == "10.20.30"
    assert VersionStamp.decode(0) == nil
  end
end
