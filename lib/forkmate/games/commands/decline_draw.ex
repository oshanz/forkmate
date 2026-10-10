defmodule Forkmate.Games.Commands.DeclineDraw do
  @moduledoc """
  Command to decline an open draw offer.
  """

  @type t :: %__MODULE__{
          game_id: String.t(),
          player_id: String.t()
        }

  @enforce_keys [:game_id, :player_id]
  defstruct [:game_id, :player_id]
end
