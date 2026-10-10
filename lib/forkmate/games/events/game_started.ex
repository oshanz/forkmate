defmodule Forkmate.Games.Events.GameStarted do
  @moduledoc """
  Emitted when a game has been started.
  """

  @derive Jason.Encoder
  defstruct [:game_id, :root_node_id, :white_player_id, :black_player_id, :initial_fen]
end
