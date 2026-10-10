defmodule Forkmate.Bots.Stockfish do
  @moduledoc """
  `Forkmate.Bots.Bot` implementation backed by a pool of Stockfish UCI
  processes (see `Forkmate.Bots.Stockfish.Pool`).
  """

  @behaviour Forkmate.Bots.Bot

  alias Forkmate.Bots.Stockfish.{Pool, UCI, Worker}

  @impl true
  def available?, do: UCI.executable() != nil

  @impl true
  def best_move(fen, level) do
    index = rem(System.unique_integer([:positive]), Pool.size())
    Worker.best_move(Pool.worker_name(index), fen, level)
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end
end
