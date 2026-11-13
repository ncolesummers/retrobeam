defmodule Retrobeam.Retros.JoinCodeTest do
  use ExUnit.Case, async: true

  alias Retrobeam.Retros.JoinCode

  doctest JoinCode

  test "generate/0 returns 6 characters from the alphabet" do
    for _ <- 1..200 do
      code = JoinCode.generate()
      assert String.length(code) == 6
      assert JoinCode.valid?(code)
    end
  end

  test "the alphabet has no look-alike characters" do
    for char <- ~w(0 O 1 I L) do
      refute String.contains?(JoinCode.alphabet(), char)
    end
  end

  test "normalize/1 trims and upcases" do
    assert JoinCode.normalize(" ab3cd4\n") == "AB3CD4"
    assert JoinCode.normalize(nil) == ""
  end

  test "valid?/1 rejects the wrong length or characters" do
    refute JoinCode.valid?("ABC23")
    refute JoinCode.valid?("ABC2345")
    refute JoinCode.valid?("abc234")
    refute JoinCode.valid?(nil)
    assert JoinCode.length() == 6
  end
end
