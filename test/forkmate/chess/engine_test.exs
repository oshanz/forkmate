defmodule Forkmate.Chess.EngineTest do
  use ExUnit.Case, async: true

  alias Forkmate.Chess.{Engine, Move, Position}

  @mate_fen "r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4"

  describe "Engine.Shakmaty" do
    @impl_mod Forkmate.Chess.Engine.Shakmaty

    test "legal_moves/1" do
      assert length(@impl_mod.legal_moves(Position.start())) == 20
    end

    test "apply_move/2 returns position and meta" do
      move = Move.new("e2", "e4")

      assert {:ok, %Position{active_color: :black}, meta} =
               @impl_mod.apply_move(Position.start(), move)

      assert meta.san == "e4"
      assert meta.outcome == :ongoing
      assert meta.is_check == false
      assert meta.is_checkmate == false
    end

    test "apply_move/2 rejects illegal moves" do
      assert {:error, :illegal_move} =
               @impl_mod.apply_move(Position.start(), Move.new("e2", "e5"))
    end

    test "apply_move/2 rejects king-to-rook castling squares" do
      pos = Position.from_fen!("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
      assert {:error, :illegal_move} = @impl_mod.apply_move(pos, Move.new("e1", "h1"))
    end

    test "apply_move/2 reports the mating side as winner in meta" do
      pos =
        Position.from_fen!("r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4")

      assert {:ok, _next, meta} = @impl_mod.apply_move(pos, Move.new("h5", "f7"))
      assert meta.outcome == {:checkmate, :white}
      assert meta.is_checkmate
    end

    test "check_square/1" do
      assert @impl_mod.check_square(Position.from_fen!(@mate_fen)) == "e8"
      assert @impl_mod.check_square(Position.start()) == nil
    end

    test "outcome/2 reports checkmate winner" do
      assert @impl_mod.outcome(Position.from_fen!(@mate_fen), []) == {:checkmate, :white}
    end

    test "outcome/2 detects threefold repetition from history" do
      start = Position.start()
      shuffle = ["g1f3", "g8f6", "f3g1", "f6g8"]

      positions =
        Enum.scan(shuffle ++ shuffle, start, fn uci, pos ->
          {:ok, move} = Move.from_uci(uci)
          {:ok, next, _meta} = @impl_mod.apply_move(pos, move)
          next
        end)

      # After two full shuffles the start position has occurred 3 times.
      current = List.last(positions)
      history = [start | Enum.drop(Enum.reverse(positions), 1)]
      assert @impl_mod.outcome(current, history) == :threefold_repetition
    end

    test "validate/1 accepts a normal position" do
      assert @impl_mod.validate(Position.start()) == :ok
    end
  end

  describe "facade" do
    test "delegates to the configured implementation" do
      assert length(Engine.legal_moves(Position.start())) == 20
    end
  end

  describe "Engine.Shakmaty validation" do
    import ExUnit.CaptureLog

    alias Forkmate.Chess.Engine.Shakmaty

    test "a position the NIF rejects is logged with its FEN instead of failing silently" do
      pos = Position.from_fen!("8/8/8/8/8/8/8/8 w - - 0 1")

      log =
        capture_log(fn ->
          assert Shakmaty.legal_moves(pos) == []
          assert Shakmaty.check_square(pos) == nil
          assert Shakmaty.outcome(pos, []) == :ongoing
        end)

      assert log =~ "8/8/8/8/8/8/8/8 w - - 0 1"
      assert log =~ "shakmaty rejected position"
    end

    test "rejects kingless positions" do
      pos = Position.from_fen!("8/8/8/8/8/8/8/8 w - - 0 1")
      assert {:error, :invalid_fen} = Shakmaty.validate(pos)
    end

    test "legal_moves is empty for a rejected position instead of raising" do
      pos = Position.from_fen!("8/8/8/8/8/8/8/8 w - - 0 1")
      assert Shakmaty.legal_moves(pos) == []
    end
  end
end
