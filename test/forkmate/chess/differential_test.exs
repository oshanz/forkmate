defmodule Forkmate.Chess.DifferentialTest do
  @moduledoc """
  Compares the in-repo `Rules` engine with the shakmaty NIF. Both must match
  published perft counts, and agree on every ply of seeded random games.
  """
  use ExUnit.Case, async: true

  alias Forkmate.Chess.{Move, Native, Position, Rules}

  @moduletag :differential

  @perft [
    {"start", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
     [{1, 20}, {2, 400}, {3, 8_902}]},
    {"kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
     [{1, 48}, {2, 2_039}]},
    {"position 3", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [{1, 14}, {2, 191}, {3, 2_812}]},
    {"position 4", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
     [{1, 6}, {2, 264}]},
    {"position 5", "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
     [{1, 44}, {2, 1_486}]}
  ]

  for {name, fen, counts} <- @perft, {depth, expected} <- counts do
    test "native perft #{name} depth #{depth} matches published count" do
      assert native_perft(unquote(fen), unquote(depth)) == unquote(expected)
    end
  end

  @games 300
  @max_plies 200

  for seed <- 1..@games do
    test "random game #{seed}: engines agree on every ply" do
      play(unquote(seed))
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

  defp play(seed) do
    :rand.seed(:exsss, {seed, seed * 7, seed * 13})
    step(Position.start(), 1, [])
  end

  defp step(_pos, ply, _trail) when ply > @max_plies, do: :ok

  defp step(pos, ply, trail) do
    fen = Position.to_fen(pos)
    old_moves = Rules.legal_moves(pos)
    {:ok, native_moves} = Native.legal_moves(fen)

    assert Enum.sort(Enum.map(old_moves, &Move.to_uci/1)) == Enum.sort(native_moves),
           context("legal moves differ", fen, nil, trail)

    if old_moves == [] do
      :ok
    else
      move = Enum.random(old_moves)
      uci = Move.to_uci(move)
      {:ok, next, meta} = Rules.apply_move(pos, move)
      {:ok, {native_fen, native_san, native_outcome, native_check}} = Native.apply_move(fen, uci)

      ctx = context("apply differs", fen, uci, trail)
      assert Position.to_fen(next) == native_fen, ctx
      assert meta.san == native_san, ctx
      assert outcome_label(meta.outcome) == native_outcome, ctx
      assert Rules.check_square(next) == native_check, ctx

      if meta.outcome == :ongoing, do: step(next, ply + 1, [uci | trail]), else: :ok
    end
  end

  defp outcome_label({:checkmate, _winner}), do: "checkmate"
  defp outcome_label(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp context(msg, fen, uci, trail) do
    "#{msg}: fen=#{fen} move=#{inspect(uci)} trail(last first)=#{inspect(Enum.take(trail, 10))}"
  end
end
