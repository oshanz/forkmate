defmodule Forkmate.Bots.Bot do
  @moduledoc """
  Behaviour for computer opponents. Implementations return a move in UCI
  notation for the position given as FEN.
  """

  alias Forkmate.Bots.Seat

  @callback best_move(fen :: String.t(), Seat.level()) :: {:ok, String.t()} | {:error, term()}
  @callback available?() :: boolean()
end
