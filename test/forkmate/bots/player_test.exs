defmodule Forkmate.Bots.PlayerTest do
  use Forkmate.DataCase

  import ExUnit.CaptureLog

  alias Ecto.Adapters.SQL.Sandbox
  alias Forkmate.Bots.{Player, Seat}
  alias Forkmate.CommandedApp
  alias Forkmate.Games
  alias Forkmate.Games.Projections.GameProjection

  @human "Player 1"

  setup do
    Sandbox.mode(Forkmate.Repo, {:shared, self()})
    start_supervised!(CommandedApp)
    start_supervised!(GameProjection)
    start_supervised!({Task.Supervisor, name: Forkmate.Bots.TaskSupervisor})
    start_supervised!(Player)
    :ok
  end

  defp new_game(white, black, attrs \\ %{}) do
    game_id = "bot-game-" <> Ecto.UUID.generate()

    {:ok, ^game_id} =
      Games.start_game(
        Map.merge(%{game_id: game_id, white_player_id: white, black_player_id: black}, attrs)
      )

    game_id
  end

  defp eventually(fun, tries \\ 100) do
    case fun.() do
      result when result not in [nil, false] ->
        result

      _ when tries > 0 ->
        Process.sleep(50)
        eventually(fun, tries - 1)

      other ->
        flunk("condition not met, last value: #{inspect(other)}")
    end
  end

  defp node_count(game_id), do: length(Games.list_nodes(game_id))

  defp human_move(game_id, from_node_id, from, to) do
    Games.make_move(%{
      game_id: game_id,
      from_node_id: from_node_id,
      from: from,
      to: to,
      player_id: @human
    })
  end

  test "bot plays White's first move on game start" do
    game_id = new_game(Seat.new(:easy), @human)
    eventually(fn -> node_count(game_id) == 2 end)
  end

  test "bot replies after the human moves, then stops" do
    game_id = new_game(@human, Seat.new(:easy))
    [root] = Games.list_nodes(game_id)

    assert :ok = human_move(game_id, root.id, "e2", "e4")

    eventually(fn -> node_count(game_id) == 3 end)
    Process.sleep(300)
    assert node_count(game_id) == 3
  end

  test "bot replies from a new branch when the human rewinds and plays differently" do
    game_id = new_game(@human, Seat.new(:easy))
    [root] = Games.list_nodes(game_id)

    :ok = human_move(game_id, root.id, "e2", "e4")
    eventually(fn -> node_count(game_id) == 3 end)

    :ok = human_move(game_id, root.id, "d2", "d4")
    eventually(fn -> node_count(game_id) == 5 end)
  end

  test "bot does not reply when it has no legal moves" do
    # Black (the bot) is stalemated: no legal moves, so no Stockfish call.
    fen = "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"

    log =
      capture_log(fn ->
        game_id = new_game(@human, Seat.new(:easy), %{initial_fen: fen})
        Process.sleep(300)
        assert node_count(game_id) == 1
      end)

    refute log =~ "Bot move failed"
  end

  test "bot declines a draw offered by the human" do
    game_id = new_game(@human, Seat.new(:easy))
    assert :ok = Games.offer_draw(game_id, @human)

    eventually(fn -> Games.get_game(game_id).draw_offered_by == nil end)
  end

  test "human-vs-human games are left alone" do
    game_id = new_game(@human, "Player 2")
    [root] = Games.list_nodes(game_id)
    :ok = human_move(game_id, root.id, "e2", "e4")
    Process.sleep(300)
    assert node_count(game_id) == 2
  end
end
