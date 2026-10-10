defmodule Forkmate.Chess.Engine do
  @moduledoc """
  Behaviour and facade for the chess rules authority.

  The implementation is chosen with `config :forkmate, :chess_engine, Module`.
  `Forkmate.Chess.Engine.Elixir` wraps the in-repo `Rules` module;
  `Forkmate.Chess.Engine.Shakmaty` uses the shakmaty NIF.
  """

  alias Forkmate.Chess.{Move, Piece, Position, Square}

  @type outcome ::
          :ongoing
          | {:checkmate, Piece.color()}
          | :stalemate
          | :insufficient_material
          | :fifty_move
          | :threefold_repetition

  @callback legal_moves(Position.t()) :: [Move.t()]
  @callback apply_move(Position.t(), Move.t()) :: {:ok, Position.t(), map()} | {:error, term()}
  @callback check_square(Position.t()) :: Square.name() | nil
  @callback outcome(Position.t(), [Position.t()]) :: outcome()
  @callback validate(Position.t()) :: :ok | {:error, term()}

  @spec impl() :: module()
  def impl, do: Application.get_env(:forkmate, :chess_engine, __MODULE__.Elixir)

  def legal_moves(pos), do: impl().legal_moves(pos)
  def apply_move(pos, move), do: impl().apply_move(pos, move)
  def check_square(pos), do: impl().check_square(pos)
  def outcome(pos, history \\ []), do: impl().outcome(pos, history)
  def validate(pos), do: impl().validate(pos)
end
