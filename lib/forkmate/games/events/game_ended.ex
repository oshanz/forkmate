defmodule Forkmate.Games.Events.GameEnded do
  @moduledoc """
  Emitted when a game or branch ends.

  - `scope`: `:game` or `:branch`
  - `reason`: `:checkmate`, `:stalemate`, `:resignation`, `:agreed_draw`, `:fifty_move`, `:repetition`, or `:timeout`
  - `winner`: `:white`, `:black`, or `nil`
  """

  @derive Jason.Encoder
  defstruct [:game_id, :node_id, :reason, :winner, :scope]
end
