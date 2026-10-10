defmodule Forkmate.Chess.NativeTest do
  use ExUnit.Case, async: true

  alias Forkmate.Chess.{Native, Position}

  describe "legal_moves/1" do
    test "start position has 20 moves in UCI form" do
      assert {:ok, moves} = Native.legal_moves(Position.start_fen())
      assert length(moves) == 20
      assert "e2e4" in moves
      assert "g1f3" in moves
    end

    test "castling is king-to-destination" do
      assert {:ok, moves} = Native.legal_moves("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
      assert "e1g1" in moves
      assert "e1c1" in moves
      refute "e1h1" in moves
    end

    test "promotion lists all four choices" do
      assert {:ok, moves} = Native.legal_moves("8/P6k/8/8/8/8/8/K7 w - - 0 1")

      assert Enum.sort(Enum.filter(moves, &String.starts_with?(&1, "a7a8"))) ==
               ["a7a8b", "a7a8n", "a7a8q", "a7a8r"]
    end

    test "garbage input returns an error tuple" do
      for bad <- ["", "nonsense", String.duplicate("x", 10_000)] do
        assert {:error, :invalid_fen} = Native.legal_moves(bad)
      end
    end

    test "kingless position is rejected" do
      assert {:error, :invalid_fen} = Native.legal_moves("8/8/8/8/8/8/8/8 w - - 0 1")
    end
  end
end
