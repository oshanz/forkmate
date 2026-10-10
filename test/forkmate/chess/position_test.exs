defmodule Forkmate.Chess.PositionTest do
  use ExUnit.Case, async: true
  alias Forkmate.Chess.Position

  @start_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  describe "FEN parsing and generation" do
    test "start position round trip" do
      pos = Position.start()
      assert Position.to_fen(pos) == @start_fen
    end

    test "custom position with en passant and halfmove" do
      fen = "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2"
      assert {:ok, pos} = Position.from_fen(fen)
      assert Position.to_fen(pos) == fen
      assert pos.en_passant == 42
      assert pos.halfmove_clock == 0
      assert pos.fullmove_number == 2
    end

    test "position with no castling rights" do
      fen = "4k3/8/8/8/8/8/8/4K3 w - - 15 32"
      assert {:ok, pos} = Position.from_fen(fen)
      assert Position.to_fen(pos) == fen
      assert Enum.empty?(pos.castling)
    end

    test "invalid FEN rejected" do
      assert {:error, _} = Position.from_fen("not a fen")
      assert {:error, _} = Position.from_fen("8/8/8/8/8/8/8 w - - 0 1")
    end
  end
end
