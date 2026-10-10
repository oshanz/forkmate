defmodule Forkmate.Games.ReadModels.Game do
  @moduledoc """
  Read model schema for a chess game.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "games" do
    field :root_node_id, :string
    field :current_node_id, :string
    field :white_player_id, :string
    field :black_player_id, :string
    field :current_fen, :string
    field :status, :string, default: "active"
    field :winner, :string
    field :end_reason, :string
    field :draw_offered_by, :string

    has_many :nodes, Forkmate.Games.ReadModels.Node, foreign_key: :game_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(game, attrs) do
    game
    |> cast(attrs, [
      :id,
      :root_node_id,
      :current_node_id,
      :white_player_id,
      :black_player_id,
      :current_fen,
      :status,
      :winner,
      :end_reason,
      :draw_offered_by
    ])
    |> validate_required([:id, :root_node_id, :white_player_id, :black_player_id, :current_fen])
  end
end
