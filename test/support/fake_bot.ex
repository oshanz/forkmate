defmodule Forkmate.Bots.FakeBot do
  @moduledoc false
  @behaviour Forkmate.Bots.Bot

  alias Forkmate.Chess.{Engine, Move, Position}

  @impl true
  def available?, do: true

  @impl true
  def best_move(fen, _level) do
    with {:ok, pos} <- Position.from_fen(fen),
         [move | _] <- Engine.legal_moves(pos) do
      {:ok, Move.to_uci(move)}
    else
      _ -> {:error, :no_move}
    end
  end
end
