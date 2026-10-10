defmodule Forkmate.Games.ReadModels.Node do
  @moduledoc """
  Read model schema for a game tree node.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "game_nodes" do
    field :game_id, :string
    field :parent_id, :string
    field :ply, :integer
    field :san, :string
    field :fen, :string
    field :mover, :string
    field :status, :string, default: "open"
    field :from_square, :string
    field :to_square, :string
    field :promotion, :string
    field :check_square, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(node, attrs) do
    node
    |> cast(attrs, [
      :id,
      :game_id,
      :parent_id,
      :ply,
      :san,
      :fen,
      :mover,
      :status,
      :from_square,
      :to_square,
      :promotion,
      :check_square
    ])
    |> validate_required([:id, :game_id, :ply, :fen])
  end

  @doc """
  Converts this node struct into the format expected by ForkmateWeb.GameComponents.
  """
  def to_component_map(%__MODULE__{} = node) do
    %{
      id: node.id,
      parent_id: node.parent_id,
      ply: node.ply,
      san: node.san,
      fen: node.fen,
      mover: mover_atom(node.mover),
      status: status_atom(node.status),
      last_move: last_move(node),
      check: node.check_square
    }
  end

  defp mover_atom("white"), do: :white
  defp mover_atom("black"), do: :black
  defp mover_atom(_), do: nil

  defp status_atom("checkmate"), do: :checkmate
  defp status_atom("stalemate"), do: :stalemate
  defp status_atom("resigned"), do: :resigned
  defp status_atom("draw"), do: :draw
  defp status_atom(_), do: :open

  defp last_move(%__MODULE__{from_square: f, to_square: t}) when is_binary(f) and is_binary(t) do
    {f, t}
  end

  defp last_move(_), do: nil
end
