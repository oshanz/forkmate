defmodule Forkmate.Chess.SquareTest do
  use ExUnit.Case, async: true
  alias Forkmate.Chess.Square

  describe "square conversions" do
    test "name to index and back" do
      assert Square.from_name("a1") == 0
      assert Square.to_name(0) == "a1"

      assert Square.from_name("e4") == 28
      assert Square.to_name(28) == "e4"

      assert Square.from_name("h8") == 63
      assert Square.to_name(63) == "h8"
    end

    test "file and rank coordinates" do
      assert Square.to_coords(0) == {0, 0}
      assert Square.to_coords(28) == {4, 3}
      assert Square.from_coords(4, 3) == 28
      assert Square.file(28) == 4
      assert Square.rank(28) == 3
      assert Square.file_name(4) == "e"
    end

    test "invalid names" do
      assert Square.from_name("i1") == nil
      assert Square.from_name("a9") == nil
      assert Square.from_name("") == nil
      assert Square.from_name("foo") == nil
    end
  end
end
