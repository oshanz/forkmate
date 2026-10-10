defmodule Forkmate.Bots.StockfishTest do
  use ExUnit.Case, async: false

  alias Forkmate.Bots.Seat
  alias Forkmate.Bots.Stockfish
  alias Forkmate.Chess.{Engine, Move, Position}

  @moduletag :stockfish

  setup do
    start_supervised!(Stockfish.Pool)
    :ok
  end

  for level <- [:easy, :medium, :hard, :max] do
    test "returns a legal move at level #{level}" do
      pos = Position.from_fen!(Position.start_fen())
      assert {:ok, uci} = Stockfish.best_move(Position.start_fen(), unquote(level))
      assert {:ok, move} = Move.from_uci(uci)
      assert move in Engine.legal_moves(pos)
    end
  end

  test "finds a back-rank mate in one at max level" do
    fen = "6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1"
    assert {:ok, "a1a8"} = Stockfish.best_move(fen, :max)
  end

  test "every seat level is accepted" do
    for level <- Seat.levels() do
      assert {:ok, _} = Stockfish.best_move(Position.start_fen(), level)
    end
  end
end
