defmodule Forkmate.Games.Events.MoveMade do
  @moduledoc """
  Emitted when a legal move has been played from a node.
  """

  @derive Jason.Encoder
  defstruct [
    :game_id,
    :node_id,
    :parent_node_id,
    :ply,
    :san,
    :fen,
    :mover,
    :from,
    :to,
    :promotion,
    :check,
    :is_checkmate
  ]
end
