defmodule Forkmate.Games.Projections.GameProjection do
  @moduledoc """
  Projects game events into Postgres read models (games and game_nodes tables).
  Broadcasts updates on `Forkmate.PubSub` after each committed transaction.
  """

  use Commanded.Projections.Ecto,
    application: Forkmate.CommandedApp,
    repo: Forkmate.Repo,
    name: "Forkmate.Games.Projections.GameProjection",
    consistency: :strong

  import Ecto.Query

  alias Forkmate.Games.Events.{
    BranchCreated,
    DrawDeclined,
    DrawOffered,
    GameEnded,
    GameStarted,
    MoveMade
  }

  alias Forkmate.Games.ReadModels.{Game, Node}

  project(%GameStarted{} = event, _metadata, fn multi ->
    game_changeset =
      Game.changeset(%Game{}, %{
        id: event.game_id,
        root_node_id: event.root_node_id,
        current_node_id: event.root_node_id,
        white_player_id: event.white_player_id,
        black_player_id: event.black_player_id,
        current_fen: event.initial_fen,
        status: "active"
      })

    root_node_changeset =
      Node.changeset(%Node{}, %{
        id: event.root_node_id,
        game_id: event.game_id,
        parent_id: nil,
        ply: 0,
        san: nil,
        fen: event.initial_fen,
        mover: nil,
        status: "open"
      })

    multi
    |> Ecto.Multi.insert(:game, game_changeset)
    |> Ecto.Multi.insert(:root_node, root_node_changeset)
  end)

  project(%BranchCreated{}, _metadata, fn multi ->
    multi
  end)

  project(%MoveMade{} = event, _metadata, fn multi ->
    node_changeset =
      Node.changeset(%Node{}, %{
        id: event.node_id,
        game_id: event.game_id,
        parent_id: event.parent_node_id,
        ply: event.ply,
        san: event.san,
        fen: event.fen,
        mover: to_string(event.mover),
        status: "open",
        from_square: event.from,
        to_square: event.to,
        promotion: event.promotion && to_string(event.promotion),
        check_square: event.check
      })

    update_game_query =
      from(g in Game,
        where: g.id == ^event.game_id,
        update: [set: [current_node_id: ^event.node_id, current_fen: ^event.fen]]
      )

    # A move withdraws only the mover's own pending draw offer, as in the aggregate.
    clear_draw_offer_query =
      case to_string(event.mover) do
        "white" ->
          from(g in Game,
            where: g.id == ^event.game_id and g.draw_offered_by == g.white_player_id,
            update: [set: [draw_offered_by: nil]]
          )

        "black" ->
          from(g in Game,
            where: g.id == ^event.game_id and g.draw_offered_by == g.black_player_id,
            update: [set: [draw_offered_by: nil]]
          )
      end

    multi
    |> Ecto.Multi.insert(:new_node, node_changeset)
    |> Ecto.Multi.update_all(:update_game, update_game_query, [])
    |> Ecto.Multi.update_all(:clear_draw_offer, clear_draw_offer_query, [])
  end)

  project(%GameEnded{} = event, _metadata, fn multi ->
    scope = to_string(event.scope)
    reason = to_string(event.reason)

    if scope == "game" do
      winner_str = event.winner && to_string(event.winner)

      update_game_query =
        from(g in Game,
          where: g.id == ^event.game_id,
          update: [
            set: [
              status: "ended",
              winner: ^winner_str,
              end_reason: ^reason,
              draw_offered_by: nil
            ]
          ]
        )

      Ecto.Multi.update_all(multi, :end_game, update_game_query, [])
    else
      status_str =
        case reason do
          "checkmate" -> "checkmate"
          "stalemate" -> "stalemate"
          "resignation" -> "resigned"
          "fifty_move" -> "fifty_move"
          "repetition" -> "repetition"
          "insufficient_material" -> "insufficient_material"
          _ -> "draw"
        end

      update_node_query =
        from(n in Node,
          where: n.id == ^event.node_id,
          update: [set: [status: ^status_str]]
        )

      Ecto.Multi.update_all(multi, :end_node, update_node_query, [])
    end
  end)

  project(%DrawOffered{} = event, _metadata, fn multi ->
    update_game_query =
      from(g in Game,
        where: g.id == ^event.game_id,
        update: [set: [draw_offered_by: ^event.player_id]]
      )

    Ecto.Multi.update_all(multi, :draw_offered, update_game_query, [])
  end)

  project(%DrawDeclined{} = event, _metadata, fn multi ->
    update_game_query =
      from(g in Game,
        where: g.id == ^event.game_id,
        update: [set: [draw_offered_by: nil]]
      )

    Ecto.Multi.update_all(multi, :draw_declined, update_game_query, [])
  end)

  @impl Commanded.Projections.Ecto
  def after_update(event, _metadata, _changes) do
    game_id = Map.get(event, :game_id)

    if game_id do
      Phoenix.PubSub.broadcast(
        Forkmate.PubSub,
        "game:" <> game_id,
        {:game_updated, game_id, event}
      )
    end

    :ok
  end
end
