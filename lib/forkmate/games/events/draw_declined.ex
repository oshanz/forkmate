defmodule Forkmate.Games.Events.DrawDeclined do
  @moduledoc """
  Emitted when a draw offer has been declined.
  """

  @derive Jason.Encoder
  defstruct [:game_id, :player_id]
end
