defmodule Forkmate.Bots.Player do
  @moduledoc """
  Commanded event handler that plays for bot seats.

  It reacts to `GameStarted` and `MoveMade`: when the side to move is a bot, it
  asks the configured `Forkmate.Bots.Bot` for a move in a supervised task (so a
  slow search never blocks event handling) and dispatches an ordinary
  `MakeMove`. The reply's node id is derived from the node it answers, so a
  duplicate delivery fails with `:node_id_taken` instead of double-moving.
  It also declines draw offers made to a bot.
  """

  use Commanded.Event.Handler,
    application: Forkmate.CommandedApp,
    name: "Forkmate.Bots.Player",
    start_from: :current

  require Logger

  alias Forkmate.Bots
  alias Forkmate.Bots.Seat
  alias Forkmate.Chess.{Engine, Move, Position, Square}
  alias Forkmate.Games
  alias Forkmate.Games.Events.{DrawOffered, GameStarted, MoveMade}

  @task_supervisor Forkmate.Bots.TaskSupervisor
  @game_wait_attempts 20
  @game_wait_ms 50

  def handle(%GameStarted{} = event, _metadata) do
    schedule_reply(
      event.game_id,
      event.root_node_id,
      event.initial_fen,
      event.white_player_id,
      event.black_player_id
    )
  end

  def handle(%MoveMade{} = event, _metadata) do
    case Games.get_game(event.game_id) do
      nil ->
        :ok

      game ->
        schedule_reply(
          event.game_id,
          event.node_id,
          event.fen,
          game.white_player_id,
          game.black_player_id
        )
    end
  end

  def handle(%DrawOffered{} = event, _metadata) do
    with %{} = game <- Games.get_game(event.game_id),
         bot_id when is_binary(bot_id) <- opposing_bot(game, event.player_id) do
      Games.decline_draw(event.game_id, bot_id)
    end

    :ok
  end

  defp opposing_bot(game, offerer) do
    other =
      if offerer == game.white_player_id, do: game.black_player_id, else: game.white_player_id

    if Seat.bot?(other) and not Seat.bot?(offerer), do: other
  end

  defp schedule_reply(game_id, node_id, fen, white_id, black_id) do
    with {:ok, pos} <- Position.from_fen(fen),
         bot_id when is_binary(bot_id) <- bot_to_move(pos.active_color, white_id, black_id),
         {:ok, level} <- Seat.level(bot_id),
         [_ | _] <- Engine.legal_moves(pos) do
      Task.Supervisor.start_child(@task_supervisor, fn ->
        play(game_id, node_id, fen, bot_id, level)
      end)
    end

    :ok
  end

  defp bot_to_move(color, white_id, black_id) do
    id = if color == :white, do: white_id, else: black_id
    if Seat.bot?(id), do: id
  end

  defp play(game_id, node_id, fen, bot_id, level) do
    with :ok <- await_game(game_id),
         {:ok, uci} <- best_move_with_retry(fen, level),
         {:ok, %Move{} = move} <- Move.from_uci(uci),
         :ok <-
           Games.make_move(%{
             game_id: game_id,
             from_node_id: node_id,
             node_id: reply_node_id(node_id),
             from: Square.to_name(move.from),
             to: Square.to_name(move.to),
             promotion: move.promotion,
             player_id: bot_id
           }) do
      :ok
    else
      # Duplicate delivery of an event we already answered.
      {:error, :node_id_taken} ->
        :ok

      # Stale replay for a game whose read model never appears.
      {:error, :game_not_found} ->
        :ok

      other ->
        Logger.warning(
          "Bot move failed for game #{game_id} at node #{node_id}: #{inspect(other)}"
        )

        :error
    end
  end

  # The handler can see `GameStarted` before the projection has written the
  # game row, and can replay events for games whose read model is gone. Wait
  # briefly for the row, then give up without touching the game.
  defp await_game(game_id, attempts \\ @game_wait_attempts) do
    cond do
      Games.get_game(game_id) != nil ->
        :ok

      attempts == 0 ->
        {:error, :game_not_found}

      true ->
        Process.sleep(@game_wait_ms)
        await_game(game_id, attempts - 1)
    end
  end

  defp best_move_with_retry(fen, level) do
    case Bots.best_move(fen, level) do
      {:ok, _} = ok -> ok
      {:error, _} -> Bots.best_move(fen, level)
    end
  end

  defp reply_node_id(node_id) do
    <<uuid::binary-size(16), _rest::binary>> = :crypto.hash(:sha256, "bot-reply:" <> node_id)
    {:ok, id} = Ecto.UUID.load(uuid)
    id
  end
end
