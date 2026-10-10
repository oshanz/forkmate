defmodule Forkmate.Chess.EngineTest do
  use ExUnit.Case, async: true

  alias Forkmate.Chess.{Engine, Move, Position}

  @mate_fen "r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4"

  for impl <- [Forkmate.Chess.Engine.Elixir] do
    describe "#{inspect(impl)}" do
      @impl_mod impl

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
  end

  describe "facade" do
    test "delegates to the configured implementation" do
      assert length(Engine.legal_moves(Position.start())) == 20
    end
  end
end
