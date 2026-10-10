defmodule Forkmate.Games.Game do
  @moduledoc """
  Commanded aggregate for a chess game.

  Each game is represented as a tree of positions in a single event stream.
  Making a move from an existing node that already has a continuation automatically
  creates a new branch.
  """

  alias Forkmate.Chess.{Move, Position, Rules}
  alias Forkmate.Games.Commands.{AcceptDraw, DeclineDraw, MakeMove, OfferDraw, Resign, StartGame}

  alias Forkmate.Games.Events.{
    BranchCreated,
    DrawDeclined,
    DrawOffered,
    GameEnded,
    GameStarted,
    MoveMade
  }

  defmodule Node do
    @moduledoc false
    defstruct [
      :id,
      :parent_id,
      :ply,
      :san,
      :fen,
      :position,
      :mover,
      :status,
      children: []
    ]
  end

  defstruct game_id: nil,
            root_node_id: nil,
            white_player_id: nil,
            black_player_id: nil,
            game_status: :not_started,
            draw_offered_by: nil,
            nodes: %{}

  # --- Command Execution ---

  @spec execute(%__MODULE__{}, struct()) :: {:ok, [struct()]} | {:error, term()}
  def execute(%__MODULE__{game_status: :not_started}, %StartGame{} = cmd) do
    root_node_id = Ecto.UUID.generate()
    initial_fen = cmd.initial_fen || Position.start_fen()

    case Position.from_fen(initial_fen) do
      {:ok, _pos} ->
        {:ok,
         [
           %GameStarted{
             game_id: cmd.game_id,
             root_node_id: root_node_id,
             white_player_id: cmd.white_player_id,
             black_player_id: cmd.black_player_id,
             initial_fen: initial_fen
           }
         ]}

      {:error, reason} ->
        {:error, {:invalid_fen, reason}}
    end
  end

  def execute(%__MODULE__{game_status: status}, %StartGame{}) when status != :not_started do
    {:error, :game_already_started}
  end

  def execute(%__MODULE__{game_status: :not_started}, _cmd) do
    {:error, :game_not_started}
  end

  def execute(%__MODULE__{game_status: :ended}, _cmd) do
    {:error, :game_ended}
  end

  def execute(%__MODULE__{} = game, %MakeMove{} = cmd) do
    with {:ok, parent_node} <- fetch_playable_node(game, cmd.from_node_id),
         :ok <- validate_player_turn(game, parent_node, cmd.player_id),
         :ok <- validate_new_node_id(game, cmd.node_id),
         {:ok, move} <- parse_move(cmd),
         {:ok, next_position, meta} <- Rules.apply_move(parent_node.position, move) do
      build_move_events(game, parent_node, cmd, next_position, meta)
    end
  end

  def execute(%__MODULE__{} = game, %Resign{} = cmd) do
    cond do
      cmd.player_id == game.white_player_id ->
        {:ok,
         [
           %GameEnded{
             game_id: game.game_id,
             node_id: nil,
             reason: :resignation,
             winner: :black,
             scope: :game
           }
         ]}

      cmd.player_id == game.black_player_id ->
        {:ok,
         [
           %GameEnded{
             game_id: game.game_id,
             node_id: nil,
             reason: :resignation,
             winner: :white,
             scope: :game
           }
         ]}

      true ->
        {:error, :not_a_player}
    end
  end

  def execute(%__MODULE__{} = game, %OfferDraw{} = cmd) do
    cond do
      cmd.player_id not in [game.white_player_id, game.black_player_id] ->
        {:error, :not_a_player}

      game.draw_offered_by != nil ->
        {:error, :draw_already_offered}

      true ->
        {:ok, [%DrawOffered{game_id: game.game_id, player_id: cmd.player_id}]}
    end
  end

  def execute(%__MODULE__{} = game, %AcceptDraw{} = cmd) do
    cond do
      game.draw_offered_by == nil ->
        {:error, :no_draw_offer}

      game.draw_offered_by == cmd.player_id ->
        {:error, :cannot_accept_own_draw_offer}

      cmd.player_id not in [game.white_player_id, game.black_player_id] ->
        {:error, :not_a_player}

      true ->
        {:ok,
         [
           %GameEnded{
             game_id: game.game_id,
             node_id: nil,
             reason: :agreed_draw,
             winner: nil,
             scope: :game
           }
         ]}
    end
  end

  def execute(%__MODULE__{} = game, %DeclineDraw{} = cmd) do
    cond do
      game.draw_offered_by == nil ->
        {:error, :no_draw_offer}

      game.draw_offered_by == cmd.player_id ->
        {:error, :cannot_decline_own_draw_offer}

      cmd.player_id not in [game.white_player_id, game.black_player_id] ->
        {:error, :not_a_player}

      true ->
        {:ok, [%DrawDeclined{game_id: game.game_id, player_id: cmd.player_id}]}
    end
  end

  # --- Event Application ---

  def apply(%__MODULE__{} = game, %GameStarted{} = event) do
    root_node = %Node{
      id: event.root_node_id,
      parent_id: nil,
      ply: 0,
      san: nil,
      fen: event.initial_fen,
      position: Position.from_fen!(event.initial_fen),
      mover: nil,
      status: :open,
      children: []
    }

    %__MODULE__{
      game
      | game_id: event.game_id,
        root_node_id: event.root_node_id,
        white_player_id: event.white_player_id,
        black_player_id: event.black_player_id,
        game_status: :active,
        draw_offered_by: nil,
        nodes: %{event.root_node_id => root_node}
    }
  end

  def apply(%__MODULE__{} = game, %BranchCreated{}) do
    game
  end

  def apply(%__MODULE__{} = game, %MoveMade{} = event) do
    event = %{event | mover: to_color(event.mover)}
    parent_node = Map.fetch!(game.nodes, event.parent_node_id)
    updated_parent = %{parent_node | children: [event.node_id | parent_node.children]}

    new_node = %Node{
      id: event.node_id,
      parent_id: event.parent_node_id,
      ply: event.ply,
      san: event.san,
      fen: event.fen,
      position: Position.from_fen!(event.fen),
      mover: event.mover,
      status: :open,
      children: []
    }

    nodes =
      game.nodes
      |> Map.put(event.parent_node_id, updated_parent)
      |> Map.put(event.node_id, new_node)

    mover_player = player_for_color(game, event.mover)

    new_draw_offer =
      if game.draw_offered_by == mover_player, do: nil, else: game.draw_offered_by

    %__MODULE__{game | nodes: nodes, draw_offered_by: new_draw_offer}
  end

  def apply(%__MODULE__{} = game, %GameEnded{} = event) do
    end_game(game, %{event | scope: to_scope(event.scope), reason: to_reason(event.reason)})
  end

  def apply(%__MODULE__{} = game, %DrawOffered{player_id: player_id}) do
    %__MODULE__{game | draw_offered_by: player_id}
  end

  def apply(%__MODULE__{} = game, %DrawDeclined{}) do
    %__MODULE__{game | draw_offered_by: nil}
  end

  defp end_game(%__MODULE__{} = game, %GameEnded{scope: :game}) do
    %__MODULE__{game | game_status: :ended, draw_offered_by: nil}
  end

  defp end_game(%__MODULE__{} = game, %GameEnded{scope: :branch, node_id: node_id, reason: reason})
       when is_binary(node_id) do
    case Map.get(game.nodes, node_id) do
      nil ->
        game

      node ->
        status =
          case reason do
            :checkmate -> :checkmate
            :stalemate -> :stalemate
            :resignation -> :resigned
            _ -> :draw
          end

        updated_node = %{node | status: status}
        %__MODULE__{game | nodes: Map.put(game.nodes, node_id, updated_node)}
    end
  end

  # --- Internal Helpers ---

  defp parse_move(cmd) do
    case Move.parse(cmd.from, cmd.to, cmd.promotion) do
      {:ok, move} -> {:ok, move}
      :error -> {:error, :illegal_move}
    end
  end

  defp validate_new_node_id(_game, nil), do: :ok

  defp validate_new_node_id(game, node_id) do
    if Map.has_key?(game.nodes, node_id), do: {:error, :node_id_taken}, else: :ok
  end

  # Events read back from the event store are JSON-deserialized, so atom-valued
  # fields arrive as strings.
  defp to_color(color) when color in [:white, :black], do: color
  defp to_color("white"), do: :white
  defp to_color("black"), do: :black

  defp to_scope(scope) when scope in [:game, :branch], do: scope
  defp to_scope("game"), do: :game
  defp to_scope("branch"), do: :branch

  defp to_reason(reason) when is_atom(reason), do: reason
  defp to_reason(reason) when is_binary(reason), do: String.to_existing_atom(reason)

  defp player_for_color(game, :white), do: game.white_player_id
  defp player_for_color(game, :black), do: game.black_player_id

  defp fetch_playable_node(game, node_id) do
    case Map.get(game.nodes, node_id) do
      nil ->
        {:error, :unknown_node}

      %Node{status: status} when status in [:checkmate, :stalemate, :resigned, :draw] ->
        {:error, :node_already_ended}

      %Node{} = node ->
        {:ok, node}
    end
  end

  defp validate_player_turn(game, node, player_id) do
    expected_player = player_for_color(game, node.position.active_color)
    if player_id == expected_player, do: :ok, else: {:error, :not_your_turn}
  end

  defp build_move_events(game, parent_node, cmd, next_position, meta) do
    new_node_id = cmd.node_id || Ecto.UUID.generate()

    branch_events =
      if parent_node.children != [] do
        [
          %BranchCreated{
            game_id: game.game_id,
            node_id: new_node_id,
            parent_node_id: cmd.from_node_id
          }
        ]
      else
        []
      end

    move_event = %MoveMade{
      game_id: game.game_id,
      node_id: new_node_id,
      parent_node_id: cmd.from_node_id,
      ply: parent_node.ply + 1,
      san: meta.san,
      fen: Position.to_fen(next_position),
      mover: parent_node.position.active_color,
      from: meta.from,
      to: meta.to,
      promotion: meta.promotion,
      check: Rules.check_square(next_position),
      is_checkmate: meta.is_checkmate
    }

    outcome_events =
      case meta.outcome do
        {:checkmate, winner} ->
          [
            %GameEnded{
              game_id: game.game_id,
              node_id: new_node_id,
              reason: :checkmate,
              winner: winner,
              scope: :branch
            }
          ]

        :stalemate ->
          [
            %GameEnded{
              game_id: game.game_id,
              node_id: new_node_id,
              reason: :stalemate,
              winner: nil,
              scope: :branch
            }
          ]

        :fifty_move ->
          [
            %GameEnded{
              game_id: game.game_id,
              node_id: new_node_id,
              reason: :fifty_move,
              winner: nil,
              scope: :branch
            }
          ]

        :insufficient_material ->
          [
            %GameEnded{
              game_id: game.game_id,
              node_id: new_node_id,
              reason: :insufficient_material,
              winner: nil,
              scope: :branch
            }
          ]

        :ongoing ->
          history = get_ancestry_positions(game.nodes, cmd.from_node_id)

          if Rules.outcome(next_position, history) == :threefold_repetition do
            [
              %GameEnded{
                game_id: game.game_id,
                node_id: new_node_id,
                reason: :repetition,
                winner: nil,
                scope: :branch
              }
            ]
          else
            []
          end
      end

    {:ok, branch_events ++ [move_event] ++ outcome_events}
  end

  defp get_ancestry_positions(nodes, node_id) do
    Stream.iterate(Map.get(nodes, node_id), fn
      %{parent_id: nil} -> nil
      %{parent_id: parent_id} -> Map.get(nodes, parent_id)
    end)
    |> Stream.take_while(&(&1 != nil))
    |> Enum.map(& &1.position)
  end
end
