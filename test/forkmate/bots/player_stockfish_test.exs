defmodule Forkmate.Bots.PlayerStockfishTest do
  use Forkmate.DataCase

  alias Ecto.Adapters.SQL.Sandbox
  alias Forkmate.Bots.{Player, Seat, Stockfish}
  alias Forkmate.CommandedApp
  alias Forkmate.Games
  alias Forkmate.Games.Projections.GameProjection

  @moduletag :stockfish

  setup do
    previous = Application.get_env(:forkmate, :bot)
    Application.put_env(:forkmate, :bot, Stockfish)
    on_exit(fn -> Application.put_env(:forkmate, :bot, previous) end)

    Sandbox.mode(Forkmate.Repo, {:shared, self()})
    start_supervised!(CommandedApp)
    start_supervised!(GameProjection)
    start_supervised!({Task.Supervisor, name: Forkmate.Bots.TaskSupervisor})
    start_supervised!(Stockfish.Pool)
    start_supervised!(Player)
    :ok
  end

  test "real Stockfish plays White's opening move and replies to the human" do
    game_id = "sf-game-" <> Ecto.UUID.generate()

    {:ok, ^game_id} =
      Games.start_game(%{
        game_id: game_id,
        white_player_id: Seat.new(:easy),
        black_player_id: "Player 1"
      })

    assert wait_for(fn -> length(Games.list_nodes(game_id)) == 2 end)

    [_root, first] = Games.list_nodes(game_id)

    assert :ok =
             Games.make_move(%{
               game_id: game_id,
               from_node_id: first.id,
               from: "e7",
               to: "e5",
               player_id: "Player 1"
             })

    assert wait_for(fn -> length(Games.list_nodes(game_id)) == 4 end)
  end

  defp wait_for(fun, tries \\ 100) do
    cond do
      fun.() -> true
      tries == 0 -> false
      true -> Process.sleep(100) && wait_for(fun, tries - 1)
    end
  end
end
