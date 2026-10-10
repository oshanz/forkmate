defmodule Forkmate.Games.Events.BranchCreated do
  @moduledoc """
  Emitted when a move branches off an already continued node.
  """

  @derive Jason.Encoder
  defstruct [:game_id, :node_id, :parent_node_id]
end
