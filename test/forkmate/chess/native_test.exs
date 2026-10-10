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

  describe "apply_move/2" do
    test "scholar's mate: SAN has #, outcome checkmate, check square" do
      fen = "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4"

      assert {:ok, {new_fen, "Qxf7#", "checkmate", "e8"}} = Native.apply_move(fen, "h5f7")
      assert new_fen == "r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4"
    end

    test "double pawn push sets the en passant square (EnPassantMode::Always)" do
      assert {:ok, {fen, "e4", "ongoing", nil}} =
               Native.apply_move(Position.start_fen(), "e2e4")

      assert fen == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
    end

    test "en passant capture" do
      fen = "rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3"

      assert {:ok, {new_fen, "exf6", "ongoing", nil}} = Native.apply_move(fen, "e5f6")
      assert new_fen == "rnbqkbnr/ppp1p1pp/5P2/3p4/8/8/PPPP1PPP/RNBQKBNR b KQkq - 0 3"
    end

    test "castling" do
      fen = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"

      assert {:ok, {new_fen, "O-O", "ongoing", nil}} = Native.apply_move(fen, "e1g1")
      assert new_fen == "r3k2r/8/8/8/8/8/8/R4RK1 b kq - 1 1"
    end

    test "promotion" do
      fen = "8/P6k/8/8/8/8/8/K7 w - - 0 1"

      assert {:ok, {new_fen, "a8=Q", "ongoing", nil}} = Native.apply_move(fen, "a7a8q")
      assert new_fen == "Q7/7k/8/8/8/8/8/K7 b - - 0 1"
    end

    test "move that causes stalemate" do
      # White Qg6 leaves the king on h8 with no moves and not in check.
      fen = "7k/8/5K2/8/8/8/8/6Q1 w - - 0 1"

      assert {:ok, {_fen, "Qg6", "stalemate", nil}} = Native.apply_move(fen, "g1g6")
    end

    test "errors" do
      assert {:error, :illegal_move} = Native.apply_move(Position.start_fen(), "e2e5")
      assert {:error, :invalid_uci} = Native.apply_move(Position.start_fen(), "zz")
      assert {:error, :invalid_uci} = Native.apply_move(Position.start_fen(), "e2e4e5")
      assert {:error, :invalid_fen} = Native.apply_move("nonsense", "e2e4")
    end
  end

  describe "outcome/1" do
    test "classifies terminal and ongoing positions" do
      assert {:ok, "ongoing"} = Native.outcome(Position.start_fen())

      assert {:ok, "checkmate"} =
               Native.outcome(
                 "r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4"
               )

      assert {:ok, "stalemate"} = Native.outcome("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
      assert {:ok, "insufficient_material"} = Native.outcome("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
      assert {:ok, "fifty_move"} = Native.outcome("4k3/8/8/8/8/8/8/R3K3 w - - 100 80")
      assert {:error, :invalid_fen} = Native.outcome("nonsense")
    end
  end

  describe "check_square_of/1" do
    test "reports the checked king's square" do
      assert {:ok, "e8"} =
               Native.check_square_of(
                 "r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4"
               )

      assert {:ok, nil} = Native.check_square_of(Position.start_fen())
    end
  end
end
