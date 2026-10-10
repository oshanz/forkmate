defmodule Forkmate.Games.Commands.StartGame do
  @moduledoc """
  Command to start a new chess game.
  """

  @type t :: %__MODULE__{
          game_id: String.t(),
          white_player_id: String.t(),
          black_player_id: String.t(),
          initial_fen: String.t() | nil
        }

  @enforce_keys [:game_id, :white_player_id, :black_player_id]
  defstruct [:game_id, :white_player_id, :black_player_id, :initial_fen]
end
