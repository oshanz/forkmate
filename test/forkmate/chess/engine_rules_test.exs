defmodule Forkmate.Chess.EngineRulesTest do
  use ExUnit.Case, async: true

  alias Forkmate.Chess.{Engine, Move, Position}

  describe "SAN formatting and move application" do
    test "pawn moves and captures" do
      pos = Position.start()
      {:ok, pos1, meta1} = Engine.apply_move(pos, Move.new("e2", "e4"))
      assert meta1.san == "e4"
      assert meta1.outcome == :ongoing

      {:ok, pos2, meta2} = Engine.apply_move(pos1, Move.new("d7", "d5"))
      assert meta2.san == "d5"

      {:ok, _pos3, meta3} = Engine.apply_move(pos2, Move.new("e4", "d5"))
      assert meta3.san == "exd5"
    end

    test "castling kingside and queenside" do
      # White can castle kingside
      fen = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
      pos = Position.from_fen!(fen)

      {:ok, _pos, meta_ks} = Engine.apply_move(pos, Move.new("e1", "g1"))
      assert meta_ks.san == "O-O"

      {:ok, _pos, meta_qs} = Engine.apply_move(pos, Move.new("e1", "c1"))
      assert meta_qs.san == "O-O-O"
    end

    test "pawn promotion with check" do
      # Black king on e8 is not possible, put king on e2 or h8 (same rank as e8)
      fen = "7k/4P3/8/8/8/8/8/4K3 w - - 0 1"
      pos = Position.from_fen!(fen)

      {:ok, _pos, meta} = Engine.apply_move(pos, Move.new("e7", "e8", :queen))
      assert meta.san == "e8=Q+"
      assert meta.is_check
    end

    test "fool's mate checkmate" do
      # 1. f3 e5 2. g4 Qh4#
      pos0 = Position.start()
      {:ok, pos1, _} = Engine.apply_move(pos0, Move.new("f2", "f3"))
      {:ok, pos2, _} = Engine.apply_move(pos1, Move.new("e7", "e5"))
      {:ok, pos3, _} = Engine.apply_move(pos2, Move.new("g2", "g4"))
      {:ok, pos4, meta4} = Engine.apply_move(pos3, Move.new("d8", "h4"))

      assert meta4.san == "Qh4#"
      assert meta4.is_check
      assert meta4.is_checkmate
      assert meta4.outcome == {:checkmate, :black}
      assert Engine.outcome(pos4) == {:checkmate, :black}
    end

    test "stalemate" do
      # Black king on a8, White queen on c7, White king on b6 -> Black to move is stalemate
      fen = "k7/2Q5/1K6/8/8/8/8/8 b - - 0 1"
      pos = Position.from_fen!(fen)

      assert Engine.legal_moves(pos) == []
      assert Engine.check_square(pos) == nil
      assert Engine.outcome(pos) == :stalemate
    end

    test "insufficient material" do
      # King vs King
      fen = "8/8/8/4k3/8/8/4K3/8 w - - 0 1"
      pos = Position.from_fen!(fen)
      assert Engine.outcome(pos) == :insufficient_material

      # King and Bishop vs King
      fen_kb = "8/8/8/4k3/8/5B2/4K3/8 w - - 0 1"
      pos_kb = Position.from_fen!(fen_kb)
      assert Engine.outcome(pos_kb) == :insufficient_material
    end

    test "threefold repetition" do
      pos0 = Position.start()
      {:ok, pos1, _} = Engine.apply_move(pos0, Move.new("g1", "f3"))
      {:ok, pos2, _} = Engine.apply_move(pos1, Move.new("g8", "f6"))
      {:ok, pos3, _} = Engine.apply_move(pos2, Move.new("f3", "g1"))
      {:ok, pos4, _} = Engine.apply_move(pos3, Move.new("f6", "g8"))
      # Pos 4 is same as Pos 0 (2nd time)
      {:ok, pos5, _} = Engine.apply_move(pos4, Move.new("g1", "f3"))
      {:ok, pos6, _} = Engine.apply_move(pos5, Move.new("g8", "f6"))
      {:ok, pos7, _} = Engine.apply_move(pos6, Move.new("f3", "g1"))
      {:ok, pos8, _} = Engine.apply_move(pos7, Move.new("f6", "g8"))
      # Pos 8 is same as Pos 0 and Pos 4 (3rd time)

      history = [pos7, pos6, pos5, pos4, pos3, pos2, pos1, pos0]
      assert Engine.outcome(pos8, history) == :threefold_repetition
    end
  end
end
