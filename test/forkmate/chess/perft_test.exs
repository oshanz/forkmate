defmodule Forkmate.Chess.PerftTest do
  @moduledoc """
  Perft node counts for the shakmaty NIF against the published reference values.
  """
  use ExUnit.Case, async: true

  alias Forkmate.Chess.Native

  @perft [
    {"start", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
     [{1, 20}, {2, 400}, {3, 8_902}]},
    {"kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
     [{1, 48}, {2, 2_039}]},
    {"position 3", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [{1, 14}, {2, 191}, {3, 2_812}]},
    {"position 4", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
     [{1, 6}, {2, 264}]},
    {"position 5", "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
     [{1, 44}, {2, 1_486}]},
    {"position 6", "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
     [{1, 46}, {2, 2_079}]}
  ]

  for {name, fen, counts} <- @perft, {depth, expected} <- counts do
    test "native perft #{name} depth #{depth} matches published count" do
      assert native_perft(unquote(fen), unquote(depth)) == unquote(expected)
    end
  end

  # --- helpers ---

  defp native_perft(fen, 1) do
    {:ok, moves} = Native.legal_moves(fen)
    length(moves)
  end

  defp native_perft(fen, depth) do
    {:ok, moves} = Native.legal_moves(fen)

    Enum.reduce(moves, 0, fn uci, acc ->
      {:ok, {next_fen, _san, _outcome, _check}} = Native.apply_move(fen, uci)
      acc + native_perft(next_fen, depth - 1)
    end)
  end
end
