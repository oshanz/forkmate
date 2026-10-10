defmodule Forkmate.Bots.Stockfish.UCITest do
  use ExUnit.Case, async: true

  alias Forkmate.Bots.Stockfish.UCI

  @fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  test "search_commands/2 sets every option, then position and go" do
    assert UCI.search_commands(@fen, :medium) == [
             "setoption name Skill Level value 20",
             "setoption name UCI_LimitStrength value true",
             "setoption name UCI_Elo value 1400",
             "position fen " <> @fen,
             "go movetime 300"
           ]
  end

  test "easy and max do not limit strength by Elo" do
    easy = UCI.search_commands(@fen, :easy)
    assert "setoption name Skill Level value 0" in easy
    assert "setoption name UCI_LimitStrength value false" in easy
    assert List.last(easy) == "go movetime 50"

    max = UCI.search_commands(@fen, :max)
    assert "setoption name Skill Level value 20" in max
    assert "setoption name UCI_LimitStrength value false" in max
    assert List.last(max) == "go movetime 1000"
  end

  test "hard uses Elo 2000" do
    assert "setoption name UCI_Elo value 2000" in UCI.search_commands(@fen, :hard)
  end

  test "parse_bestmove/1" do
    assert UCI.parse_bestmove("bestmove e2e4 ponder e7e5") == {:ok, "e2e4"}
    assert UCI.parse_bestmove("bestmove e7e8q") == {:ok, "e7e8q"}
    assert UCI.parse_bestmove("bestmove (none)") == {:error, :no_move}
    assert UCI.parse_bestmove("info depth 3 score cp 20") == :ignore
    assert UCI.parse_bestmove("readyok") == :ignore
  end
end
