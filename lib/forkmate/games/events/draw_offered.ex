defmodule Forkmate.Games.Events.DrawOffered do
  @moduledoc """
  Emitted when a draw offer has been made.
  """

  @derive Jason.Encoder
  defstruct [:game_id, :player_id]
end
