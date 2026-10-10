defmodule Forkmate.Chess.Piece do
  @moduledoc """
  Piece types, colors, and FEN char conversions.
  """

  @type color :: :white | :black
  @type piece_type :: :pawn | :knight | :bishop | :rook | :queen | :king
  @type t :: {color(), piece_type()}

  @to_char %{
    {:white, :pawn} => "P",
    {:white, :knight} => "N",
    {:white, :bishop} => "B",
    {:white, :rook} => "R",
    {:white, :queen} => "Q",
    {:white, :king} => "K",
    {:black, :pawn} => "p",
    {:black, :knight} => "n",
    {:black, :bishop} => "b",
    {:black, :rook} => "r",
    {:black, :queen} => "q",
    {:black, :king} => "k"
  }

  @from_char Map.new(@to_char, fn {k, v} -> {v, k} end)

  @spec to_char(t()) :: String.t()
  def to_char(piece), do: Map.fetch!(@to_char, piece)

  @spec from_char(String.t()) :: t() | nil
  def from_char(char), do: Map.get(@from_char, char)

  @spec opponent(color()) :: color()
  def opponent(:white), do: :black
  def opponent(:black), do: :white
end
