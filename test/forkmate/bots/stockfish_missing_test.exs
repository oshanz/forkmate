defmodule Forkmate.Bots.StockfishMissingTest do
  use ExUnit.Case, async: false

  alias Forkmate.Bots.Stockfish
  alias Forkmate.Chess.Position

  setup do
    previous = System.get_env("STOCKFISH_PATH")
    System.put_env("STOCKFISH_PATH", "/nonexistent/stockfish")

    on_exit(fn ->
      if previous,
        do: System.put_env("STOCKFISH_PATH", previous),
        else: System.delete_env("STOCKFISH_PATH")
    end)

    start_supervised!(Stockfish.Pool)
    :ok
  end

  test "is unavailable and returns an error instead of crashing when the binary is missing" do
    refute Stockfish.available?()
    assert {:error, :stockfish_not_found} = Stockfish.best_move(Position.start_fen(), :easy)
    # The worker survived the failed request.
    assert {:error, :stockfish_not_found} = Stockfish.best_move(Position.start_fen(), :easy)
  end
end
