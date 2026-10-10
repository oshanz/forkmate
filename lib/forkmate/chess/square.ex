defmodule Forkmate.Chess.Square do
  @moduledoc """
  Square coordinate representation and conversions.

  Squares are represented internally as integers `0..63`:
  - 0 = a1, 7 = h1
  - 56 = a8, 63 = h8

  Files are 0..7 (a..h), ranks are 0..7 (1..8).
  """

  @files ~w(a b c d e f g h)

  @type index :: 0..63
  @type name :: String.t()
  @type coords :: {0..7, 0..7}

  @spec to_coords(index()) :: coords()
  def to_coords(sq) when sq in 0..63 do
    {rem(sq, 8), div(sq, 8)}
  end

  @spec from_coords(0..7, 0..7) :: index()
  def from_coords(file, rank) when file in 0..7 and rank in 0..7 do
    file + rank * 8
  end

  @spec to_name(index()) :: name()
  def to_name(sq) when sq in 0..63 do
    file = rem(sq, 8)
    rank = div(sq, 8) + 1
    Enum.at(@files, file) <> Integer.to_string(rank)
  end

  @spec from_name(name()) :: index() | nil
  def from_name(<<file, rank>>) when file in ?a..?h and rank in ?1..?8 do
    file - ?a + (rank - ?1) * 8
  end

  def from_name(_), do: nil

  @spec valid?(index()) :: boolean()
  def valid?(sq) when is_integer(sq), do: sq in 0..63
  def valid?(_), do: false

  @spec file(index()) :: 0..7
  def file(sq), do: rem(sq, 8)

  @spec rank(index()) :: 0..7
  def rank(sq), do: div(sq, 8)

  @spec file_name(0..7) :: String.t()
  def file_name(f) when f in 0..7, do: Enum.at(@files, f)
end
