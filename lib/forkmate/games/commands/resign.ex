defmodule Forkmate.Games.Commands.Resign do
  @moduledoc """
  Command for a player to resign the game.
  """

  @type t :: %__MODULE__{
          game_id: String.t(),
          player_id: String.t()
        }

  @enforce_keys [:game_id, :player_id]
  defstruct [:game_id, :player_id]
end
