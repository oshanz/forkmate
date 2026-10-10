defmodule Forkmate.Chess.Engine.Shakmaty do
  @moduledoc """
  Engine implementation backed by the shakmaty NIF (`Forkmate.Chess.Native`).

  Repetition detection stays in Elixir because shakmaty positions carry no history.
  """

  @behaviour Forkmate.Chess.Engine

  alias Forkmate.Chess.{Move, Native, Piece, Position, Square}

  @impl true
  def legal_moves(%Position{} = pos) do
    case Native.legal_moves(Position.to_fen(pos)) do
      {:ok, ucis} -> Enum.flat_map(ucis, &parse_uci/1)
      {:error, _reason} -> []
    end
  end

  @impl true
  def apply_move(%Position{} = pos, %Move{} = move) do
    case Native.apply_move(Position.to_fen(pos), Move.to_uci(move)) do
      {:ok, {fen, san, outcome, check_square}} ->
        {:ok, Position.from_fen!(fen), meta(pos, move, san, outcome, check_square)}

      {:error, :invalid_uci} ->
        {:error, :illegal_move}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def check_square(%Position{} = pos) do
    case Native.check_square_of(Position.to_fen(pos)) do
      {:ok, square} -> square
      {:error, _reason} -> nil
    end
  end

  @impl true
  def outcome(%Position{} = pos, history) do
    case Native.outcome(Position.to_fen(pos)) do
      {:ok, "ongoing"} -> if repetition?(pos, history), do: :threefold_repetition, else: :ongoing
      {:ok, label} -> outcome_term(label, Piece.opponent(pos.active_color))
      {:error, _reason} -> :ongoing
    end
  end

  @impl true
  def validate(%Position{} = pos) do
    case Native.legal_moves(Position.to_fen(pos)) do
      {:ok, _moves} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # --- helpers ---

  defp parse_uci(uci) do
    case Move.from_uci(uci) do
      {:ok, move} -> [move]
      :error -> []
    end
  end

  defp meta(pos, move, san, outcome, check_square) do
    %{
      san: san,
      from: Square.to_name(move.from),
      to: Square.to_name(move.to),
      promotion: move.promotion,
      captured_piece: Map.get(pos.board, move.to),
      is_check: check_square != nil,
      is_checkmate: outcome == "checkmate",
      # The mover wins on checkmate; `pos` is the position before the move.
      outcome: outcome_term(outcome, pos.active_color)
    }
  end

  defp outcome_term("checkmate", winner), do: {:checkmate, winner}
  defp outcome_term("stalemate", _winner), do: :stalemate
  defp outcome_term("insufficient_material", _winner), do: :insufficient_material
  defp outcome_term("fifty_move", _winner), do: :fifty_move
  defp outcome_term("ongoing", _winner), do: :ongoing

  defp repetition?(pos, history) do
    key = position_key(pos)
    Enum.count([pos | history], &(position_key(&1) == key)) >= 3
  end

  defp position_key(%Position{} = p), do: {p.board, p.active_color, p.castling, p.en_passant}
end
