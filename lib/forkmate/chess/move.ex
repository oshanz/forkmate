defmodule Forkmate.Chess.Move do
  @moduledoc """
  Represents a chess move from one square to another with optional promotion piece.
  """

  alias Forkmate.Chess.Square

  @type promotion_piece :: :queen | :rook | :bishop | :knight
  @type t :: %__MODULE__{
          from: Square.index(),
          to: Square.index(),
          promotion: promotion_piece() | nil
        }

  @enforce_keys [:from, :to]
  defstruct [:from, :to, :promotion]

  @spec new(
          Square.index() | Square.name(),
          Square.index() | Square.name(),
          promotion_piece() | nil
        ) ::
          t()
  def new(from, to, promotion \\ nil)

  def new(from, to, promotion) when is_binary(from) and is_binary(to) do
    new(Square.from_name(from), Square.from_name(to), normalize_promotion(promotion))
  end

  def new(from, to, promotion) when is_integer(from) and is_integer(to) do
    %__MODULE__{
      from: from,
      to: to,
      promotion: normalize_promotion(promotion)
    }
  end

  @doc """
  Like `new/3`, but returns `:error` instead of raising when a square is not a
  valid index or name.
  """
  @spec parse(term(), term(), term()) :: {:ok, t()} | :error
  def parse(from, to, promotion \\ nil) do
    with from_sq when is_integer(from_sq) <- to_index(from),
         to_sq when is_integer(to_sq) <- to_index(to) do
      {:ok, new(from_sq, to_sq, promotion)}
    else
      _ -> :error
    end
  end

  defp to_index(sq) when is_binary(sq), do: Square.from_name(sq)
  defp to_index(sq) when is_integer(sq), do: if(Square.valid?(sq), do: sq)
  defp to_index(_), do: nil

  @spec to_uci(t()) :: String.t()
  def to_uci(%__MODULE__{from: from, to: to, promotion: promo}) do
    promo_str =
      case promo do
        :queen -> "q"
        :rook -> "r"
        :bishop -> "b"
        :knight -> "n"
        nil -> ""
      end

    Square.to_name(from) <> Square.to_name(to) <> promo_str
  end

  @spec from_uci(String.t()) :: {:ok, t()} | :error
  def from_uci(<<from::binary-size(2), to::binary-size(2), promo::binary>>) do
    with from_sq when is_integer(from_sq) <- Square.from_name(from),
         to_sq when is_integer(to_sq) <- Square.from_name(to),
         {:ok, promotion} <- parse_promo(promo) do
      {:ok, %__MODULE__{from: from_sq, to: to_sq, promotion: promotion}}
    else
      _ -> :error
    end
  end

  def from_uci(_), do: :error

  defp parse_promo(""), do: {:ok, nil}
  defp parse_promo("q"), do: {:ok, :queen}
  defp parse_promo("r"), do: {:ok, :rook}
  defp parse_promo("b"), do: {:ok, :bishop}
  defp parse_promo("n"), do: {:ok, :knight}
  defp parse_promo(_), do: :error

  defp normalize_promotion(nil), do: nil
  defp normalize_promotion(p) when p in [:queen, :rook, :bishop, :knight], do: p
  defp normalize_promotion("q"), do: :queen
  defp normalize_promotion("r"), do: :rook
  defp normalize_promotion("b"), do: :bishop
  defp normalize_promotion("n"), do: :knight
  defp normalize_promotion("Q"), do: :queen
  defp normalize_promotion("R"), do: :rook
  defp normalize_promotion("B"), do: :bishop
  defp normalize_promotion("N"), do: :knight
  defp normalize_promotion(_), do: nil
end
