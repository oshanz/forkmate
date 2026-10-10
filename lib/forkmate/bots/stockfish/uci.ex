defmodule Forkmate.Bots.Stockfish.UCI do
  @moduledoc """
  Pure helpers for talking UCI to Stockfish: level presets, command lists and
  `bestmove` parsing.
  """

  alias Forkmate.Bots.Seat

  # {Skill Level, limit strength?, Elo, movetime in ms}
  @presets %{
    easy: {0, false, nil, 50},
    medium: {20, true, 1400, 300},
    hard: {20, true, 2000, 600},
    max: {20, false, nil, 1000}
  }

  @spec search_commands(String.t(), Seat.level()) :: [String.t()]
  def search_commands(fen, level) do
    {skill, limit?, elo, movetime} = Map.fetch!(@presets, level)

    [
      "setoption name Skill Level value #{skill}",
      "setoption name UCI_LimitStrength value #{limit?}"
    ] ++
      if(elo, do: ["setoption name UCI_Elo value #{elo}"], else: []) ++
      ["position fen " <> fen, "go movetime #{movetime}"]
  end

  @spec parse_bestmove(String.t()) :: {:ok, String.t()} | {:error, :no_move} | :ignore
  def parse_bestmove("bestmove (none)" <> _), do: {:error, :no_move}

  def parse_bestmove("bestmove " <> rest) do
    case String.split(rest, " ", parts: 2) do
      [move | _] when move != "" -> {:ok, move}
      _ -> {:error, :no_move}
    end
  end

  def parse_bestmove(_line), do: :ignore

  @doc """
  Path of the Stockfish binary: `STOCKFISH_PATH`, else `stockfish` on `PATH`.
  Returns `nil` when neither resolves to an existing file.
  """
  @spec executable() :: String.t() | nil
  def executable do
    path = System.get_env("STOCKFISH_PATH") || System.find_executable("stockfish")
    if path && File.regular?(path), do: path
  end
end
