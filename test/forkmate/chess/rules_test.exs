defmodule Forkmate.Chess.RulesTest do
  use ExUnit.Case, async: true

  alias Forkmate.Chess.{Move, Position, Rules}

  describe "perft - initial position" do
    setup do
      [pos: Position.start()]
    end

    test "depth 1", %{pos: pos} do
      assert Rules.perft(pos, 1) == 20
    end

    test "depth 2", %{pos: pos} do
      assert Rules.perft(pos, 2) == 400
    end

    test "depth 3", %{pos: pos} do
      assert Rules.perft(pos, 3) == 8_902
    end
  end

  describe "perft - tricky positions" do
    test "position 2 (Kiwipete)" do
      fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
      pos = Position.from_fen!(fen)
      assert Rules.perft(pos, 1) == 48
      assert Rules.perft(pos, 2) == 2_039
    end

    test "position 3" do
      fen = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"
      pos = Position.from_fen!(fen)
      assert Rules.perft(pos, 1) == 14
      assert Rules.perft(pos, 2) == 191
      assert Rules.perft(pos, 3) == 2_812
    end

    test "position 4" do
      fen = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1"
      pos = Position.from_fen!(fen)
      assert Rules.perft(pos, 1) == 6
      assert Rules.perft(pos, 2) == 264
    end

    test "position 5" do
      fen = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8"
      pos = Position.from_fen!(fen)
      assert Rules.perft(pos, 1) == 44
      assert Rules.perft(pos, 2) == 1_486
    end

    test "position 6" do
      fen = "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10"
      pos = Position.from_fen!(fen)
      assert Rules.perft(pos, 1) == 46
      assert Rules.perft(pos, 2) == 2_079
    end
  end

  describe "SAN formatting and move application" do
    test "pawn moves and captures" do
      pos = Position.start()
      {:ok, pos1, meta1} = Rules.apply_move(pos, Move.new("e2", "e4"))
      assert meta1.san == "e4"
      assert meta1.outcome == :ongoing

      {:ok, pos2, meta2} = Rules.apply_move(pos1, Move.new("d7", "d5"))
      assert meta2.san == "d5"

      {:ok, _pos3, meta3} = Rules.apply_move(pos2, Move.new("e4", "d5"))
      assert meta3.san == "exd5"
    end

    test "castling kingside and queenside" do
      # White can castle kingside
      fen = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
      pos = Position.from_fen!(fen)

      {:ok, _pos, meta_ks} = Rules.apply_move(pos, Move.new("e1", "g1"))
      assert meta_ks.san == "O-O"

      {:ok, _pos, meta_qs} = Rules.apply_move(pos, Move.new("e1", "c1"))
      assert meta_qs.san == "O-O-O"
    end

    test "pawn promotion with check" do
      # Black king on e8 is not possible, put king on e2 or h8 (same rank as e8)
      fen = "7k/4P3/8/8/8/8/8/4K3 w - - 0 1"
      pos = Position.from_fen!(fen)

      {:ok, _pos, meta} = Rules.apply_move(pos, Move.new("e7", "e8", :queen))
      assert meta.san == "e8=Q+"
      assert meta.is_check
    end

    test "fool's mate checkmate" do
      # 1. f3 e5 2. g4 Qh4#
      pos0 = Position.start()
      {:ok, pos1, _} = Rules.apply_move(pos0, Move.new("f2", "f3"))
      {:ok, pos2, _} = Rules.apply_move(pos1, Move.new("e7", "e5"))
      {:ok, pos3, _} = Rules.apply_move(pos2, Move.new("g2", "g4"))
      {:ok, pos4, meta4} = Rules.apply_move(pos3, Move.new("d8", "h4"))

      assert meta4.san == "Qh4#"
      assert meta4.is_check
      assert meta4.is_checkmate
      assert meta4.outcome == {:checkmate, :black}
      assert Rules.outcome(pos4) == {:checkmate, :black}
    end

    test "stalemate" do
      # Black king on a8, White queen on c7, White king on b6 -> Black to move is stalemate
      fen = "k7/2Q5/1K6/8/8/8/8/8 b - - 0 1"
      pos = Position.from_fen!(fen)

      assert Rules.legal_moves(pos) == []
      assert not Rules.in_check?(pos, :black)
      assert Rules.outcome(pos) == :stalemate
    end

    test "insufficient material" do
      # King vs King
      fen = "8/8/8/4k3/8/8/4K3/8 w - - 0 1"
      pos = Position.from_fen!(fen)
      assert Rules.outcome(pos) == :insufficient_material

      # King and Bishop vs King
      fen_kb = "8/8/8/4k3/8/5B2/4K3/8 w - - 0 1"
      pos_kb = Position.from_fen!(fen_kb)
      assert Rules.outcome(pos_kb) == :insufficient_material
    end

    test "threefold repetition" do
      pos0 = Position.start()
      {:ok, pos1, _} = Rules.apply_move(pos0, Move.new("g1", "f3"))
      {:ok, pos2, _} = Rules.apply_move(pos1, Move.new("g8", "f6"))
      {:ok, pos3, _} = Rules.apply_move(pos2, Move.new("f3", "g1"))
      {:ok, pos4, _} = Rules.apply_move(pos3, Move.new("f6", "g8"))
      # Pos 4 is same as Pos 0 (2nd time)
      {:ok, pos5, _} = Rules.apply_move(pos4, Move.new("g1", "f3"))
      {:ok, pos6, _} = Rules.apply_move(pos5, Move.new("g8", "f6"))
      {:ok, pos7, _} = Rules.apply_move(pos6, Move.new("f3", "g1"))
      {:ok, pos8, _} = Rules.apply_move(pos7, Move.new("f6", "g8"))
      # Pos 8 is same as Pos 0 and Pos 4 (3rd time)

      history = [pos7, pos6, pos5, pos4, pos3, pos2, pos1, pos0]
      assert Rules.outcome(pos8, history) == :threefold_repetition
    end
  end
end
