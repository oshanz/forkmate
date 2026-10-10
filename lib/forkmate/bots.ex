defmodule Forkmate.Bots do
  @moduledoc """
  Facade over the configured `Forkmate.Bots.Bot` implementation
  (`config :forkmate, :bot, Module`).
  """

  @spec impl() :: module()
  def impl, do: Application.get_env(:forkmate, :bot, Forkmate.Bots.Stockfish)

  @spec best_move(String.t(), Forkmate.Bots.Seat.level()) :: {:ok, String.t()} | {:error, term()}
  def best_move(fen, level), do: impl().best_move(fen, level)

  @spec available?() :: boolean()
  def available?, do: impl().available?()
end
