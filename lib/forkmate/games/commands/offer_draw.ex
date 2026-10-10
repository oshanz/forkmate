defmodule Forkmate.Games.Commands.OfferDraw do
  @moduledoc """
  Command to offer a draw to the opponent.
  """

  @type t :: %__MODULE__{
          game_id: String.t(),
          player_id: String.t()
        }

  @enforce_keys [:game_id, :player_id]
  defstruct [:game_id, :player_id]
end
