defmodule Forkmate.Games.Commands.MakeMove do
  @moduledoc """
  Command to play a move from a specific node in the game tree.
  """

  @type t :: %__MODULE__{
          game_id: String.t(),
          from_node_id: String.t(),
          node_id: String.t() | nil,
          from: String.t(),
          to: String.t(),
          promotion: atom() | nil,
          player_id: String.t()
        }

  @enforce_keys [:game_id, :from_node_id, :from, :to, :player_id]
  defstruct [:game_id, :from_node_id, :node_id, :from, :to, :promotion, :player_id]
end
