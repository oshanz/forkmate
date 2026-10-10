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
      game_query(event.game_id, current_node_id: event.node_id, current_fen: event.fen)

    # A move withdraws only the mover's own pending draw offer, as in the aggregate.
    seat = if to_string(event.mover) == "white", do: :white_player_id, else: :black_player_id

    clear_draw_offer_query =
      from(g in Game,
        where: g.id == ^event.game_id and g.draw_offered_by == field(g, ^seat),
        update: [set: [draw_offered_by: nil]]
      )

    multi
    |> Ecto.Multi.insert(:new_node, node_changeset)
    |> Ecto.Multi.update_all(:update_game, update_game_query, [])
    |> Ecto.Multi.update_all(:clear_draw_offer, clear_draw_offer_query, [])
  end)

  project(%GameEnded{} = event, _metadata, fn multi ->
    reason = to_string(event.reason)

    if to_string(event.scope) == "game" do
      Ecto.Multi.update_all(
        multi,
        :end_game,
        game_query(event.game_id,
          status: "ended",
          winner: event.winner && to_string(event.winner),
          end_reason: reason,
          draw_offered_by: nil
        ),
        []
      )
    else
      update_node_query =
        from(n in Node,
          where: n.id == ^event.node_id,
          update: [set: [status: ^node_status(reason)]]
        )

      Ecto.Multi.update_all(multi, :end_node, update_node_query, [])
    end
  end)

  project(%DrawOffered{} = event, _metadata, fn multi ->
    Ecto.Multi.update_all(
      multi,
      :draw_offered,
      game_query(event.game_id, draw_offered_by: event.player_id),
      []
    )
  end)

  project(%DrawDeclined{} = event, _metadata, fn multi ->
    Ecto.Multi.update_all(
      multi,
      :draw_declined,
      game_query(event.game_id, draw_offered_by: nil),
      []
    )
  end)

  defp game_query(game_id, set) do
    from(g in Game, where: g.id == ^game_id, update: [set: ^set])
  end

  defp node_status("resignation"), do: "resigned"

  defp node_status(reason)
       when reason in ~w(checkmate stalemate fifty_move repetition insufficient_material),
       do: reason

  defp node_status(_reason), do: "draw"

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
