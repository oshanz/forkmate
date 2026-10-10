defmodule Forkmate.Games do
  @moduledoc """
  The Games context. High-level boundary for dispatching game commands
  and querying game read models.
  """

  import Ecto.Query

  alias Forkmate.Chess.{Engine, Position, Square}
  alias Forkmate.CommandedApp
  alias Forkmate.Games.Commands.{AcceptDraw, DeclineDraw, MakeMove, OfferDraw, Resign, StartGame}
  alias Forkmate.Games.ReadModels.{Game, Node}
  alias Forkmate.Repo

  # --- Command Dispatch ---

  @spec start_game(map()) :: {:ok, String.t()} | {:error, term()}
  def start_game(attrs) do
    game_id = Map.get(attrs, :game_id) || Ecto.UUID.generate()
    white_player_id = Map.get(attrs, :white_player_id)
    black_player_id = Map.get(attrs, :black_player_id)
    initial_fen = Map.get(attrs, :initial_fen)

    cmd = %StartGame{
      game_id: game_id,
      white_player_id: white_player_id,
      black_player_id: black_player_id,
      initial_fen: initial_fen
    }

    case CommandedApp.dispatch(cmd, consistency: :strong) do
      :ok -> {:ok, game_id}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec make_move(map()) :: :ok | {:error, term()}
  def make_move(attrs) do
    cmd = %MakeMove{
      game_id: Map.get(attrs, :game_id),
      from_node_id: Map.get(attrs, :from_node_id),
      node_id: Map.get(attrs, :node_id),
      from: Map.get(attrs, :from),
      to: Map.get(attrs, :to),
      promotion: Map.get(attrs, :promotion),
      player_id: Map.get(attrs, :player_id)
    }

    CommandedApp.dispatch(cmd, consistency: :strong)
  end

  @spec resign(String.t(), String.t()) :: :ok | {:error, term()}
  def resign(game_id, player_id) do
    cmd = %Resign{game_id: game_id, player_id: player_id}
    CommandedApp.dispatch(cmd, consistency: :strong)
  end

  @spec offer_draw(String.t(), String.t()) :: :ok | {:error, term()}
  def offer_draw(game_id, player_id) do
    cmd = %OfferDraw{game_id: game_id, player_id: player_id}
    CommandedApp.dispatch(cmd, consistency: :strong)
  end

  @spec accept_draw(String.t(), String.t()) :: :ok | {:error, term()}
  def accept_draw(game_id, player_id) do
    cmd = %AcceptDraw{game_id: game_id, player_id: player_id}
    CommandedApp.dispatch(cmd, consistency: :strong)
  end

  @spec decline_draw(String.t(), String.t()) :: :ok | {:error, term()}
  def decline_draw(game_id, player_id) do
    cmd = %DeclineDraw{game_id: game_id, player_id: player_id}
    CommandedApp.dispatch(cmd, consistency: :strong)
  end

  # --- Read Model Queries ---

  @spec get_game(String.t()) :: Game.t() | nil
  def get_game(game_id) do
    Repo.get(Game, game_id)
  end

  @spec get_game!(String.t()) :: Game.t()
  def get_game!(game_id) do
    Repo.get!(Game, game_id)
  end

  @spec list_nodes(String.t()) :: [Node.t()]
  def list_nodes(game_id) do
    Repo.all(
      from(n in Node,
        where: n.game_id == ^game_id,
        order_by: [asc: n.ply, asc: n.inserted_at]
      )
    )
  end

  @spec get_node(String.t(), String.t()) :: Node.t() | nil
  def get_node(game_id, node_id) do
    Repo.one(
      from(n in Node,
        where: n.game_id == ^game_id and n.id == ^node_id
      )
    )
  end

  @doc """
  Returns the line of nodes from root down to `current_node_id`.
  """
  @spec get_line_nodes([Node.t()], String.t()) :: [Node.t()]
  def get_line_nodes(all_nodes, current_node_id) do
    by_id = Map.new(all_nodes, &{&1.id, &1})

    Stream.iterate(Map.get(by_id, current_node_id), fn
      nil -> nil
      %{parent_id: nil} -> nil
      node -> Map.get(by_id, node.parent_id)
    end)
    |> Stream.take_while(&(&1 != nil))
    |> Enum.to_list()
    |> Enum.reverse()
  end

  @doc """
  Finds node IDs that have more than 1 child.
  """
  @spec find_fork_node_ids([Node.t()]) :: [String.t()]
  def find_fork_node_ids(all_nodes) do
    all_nodes
    |> Enum.filter(&(&1.parent_id != nil))
    |> Enum.group_by(& &1.parent_id)
    |> Enum.filter(fn {_parent_id, children} -> length(children) > 1 end)
    |> Enum.map(&elem(&1, 0))
  end

  # --- Rules Helpers for UI ---

  @doc """
  Returns legal target square names for a selected square in a given node.
  """
  @spec legal_targets(Node.t(), String.t() | nil) :: [String.t()]
  def legal_targets(%Node{fen: fen}, selected_square) when is_binary(selected_square) do
    case {Position.from_fen(fen), Square.from_name(selected_square)} do
      {{:ok, pos}, from_idx} when from_idx != nil ->
        pos
        |> Engine.legal_moves()
        |> Enum.filter(&(&1.from == from_idx))
        |> Enum.map(&Square.to_name(&1.to))
        |> Enum.uniq()

      _ ->
        []
    end
  end

  def legal_targets(_node, _), do: []

  @doc """
  Returns promotion target square names for a selected square in a given node.
  """
  @spec promotion_targets(Node.t(), String.t() | nil) :: [String.t()]
  def promotion_targets(%Node{fen: fen}, selected_square) when is_binary(selected_square) do
    case {Position.from_fen(fen), Square.from_name(selected_square)} do
      {{:ok, pos}, from_idx} when from_idx != nil ->
        pos
        |> Engine.legal_moves()
        |> Enum.filter(&(&1.from == from_idx and &1.promotion != nil))
        |> Enum.map(&Square.to_name(&1.to))
        |> Enum.uniq()

      _ ->
        []
    end
  end

  def promotion_targets(_node, _), do: []

  @doc """
  Checks if a move from selected to target is a promotion move.
  """
  def promotion_move?(%Node{fen: fen}, from_sq, to_sq) do
    with {:ok, pos} <- Position.from_fen(fen),
         from_idx when from_idx != nil <- Square.from_name(from_sq),
         to_idx when to_idx != nil <- Square.from_name(to_sq) do
      Enum.any?(Engine.legal_moves(pos), fn m ->
        m.from == from_idx and m.to == to_idx and m.promotion != nil
      end)
    else
      _ -> false
    end
  end

  @doc """
  Returns the side to move for a node (:white or :black).
  """
  def turn_color(%Node{fen: fen}) do
    case Position.from_fen(fen) do
      {:ok, pos} -> pos.active_color
      _ -> :white
    end
  end
end
