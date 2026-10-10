defmodule Forkmate.Bots.PlayerOrphanGameTest do
  use Forkmate.DataCase

  alias Ecto.Adapters.SQL.Sandbox
  alias Forkmate.Bots.{Player, Seat}
  alias Forkmate.CommandedApp
  alias Forkmate.Games.Commands.StartGame

  # No GameProjection here: the game has events but no read model, like a game
  # replayed from the event store after its read model was rolled back or lost.
  setup do
    Sandbox.mode(Forkmate.Repo, {:shared, self()})
    start_supervised!(CommandedApp)
    start_supervised!({Task.Supervisor, name: Forkmate.Bots.TaskSupervisor})
    start_supervised!(Player)
    :ok
  end

  test "bot does not move in a game that has no read model" do
    game_id = Ecto.UUID.generate()

    :ok =
      CommandedApp.dispatch(%StartGame{
        game_id: game_id,
        white_player_id: Seat.new(:easy),
        black_player_id: "Player 1"
      })

    Process.sleep(1_500)
    assert game_id |> Forkmate.EventStore.stream_forward() |> Enum.count() == 1
  end
end
