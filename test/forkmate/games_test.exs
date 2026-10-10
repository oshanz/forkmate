defmodule Forkmate.GamesTest do
  use Forkmate.DataCase

  alias Ecto.Adapters.SQL.Sandbox
  alias Forkmate.CommandedApp
  alias Forkmate.Games
  alias Forkmate.Games.Projections.GameProjection

  setup do
    Sandbox.mode(Forkmate.Repo, {:shared, self()})
    start_supervised!(CommandedApp)
    start_supervised!(GameProjection)
    :ok
  end

  @white "player-1"
  @black "player-2"

  test "starts a game and projects to read models" do
    game_id = "test-game-" <> Ecto.UUID.generate()

    assert {:ok, ^game_id} =
             Games.start_game(%{
               game_id: game_id,
               white_player_id: @white,
               black_player_id: @black
             })

    game = Games.get_game(game_id)
    assert game != nil
    assert game.status == "active"
    assert game.white_player_id == @white
    assert game.black_player_id == @black

    nodes = Games.list_nodes(game_id)
    assert length(nodes) == 1
    [root] = nodes
    assert root.ply == 0
    assert root.fen == game.current_fen
  end

  test "makes moves and handles branching" do
    game_id = "test-game-" <> Ecto.UUID.generate()

    {:ok, _} =
      Games.start_game(%{
        game_id: game_id,
        white_player_id: @white,
        black_player_id: @black
      })

    [root] = Games.list_nodes(game_id)

    # 1. White plays e4
    assert :ok =
             Games.make_move(%{
               game_id: game_id,
               from_node_id: root.id,
               from: "e2",
               to: "e4",
               player_id: @white
             })

    game = Games.get_game(game_id)
    nodes = Games.list_nodes(game_id)
    assert length(nodes) == 2

    e4_node = Enum.find(nodes, &(&1.san == "e4"))
    assert e4_node != nil
    assert game.current_node_id == e4_node.id

    line = Games.get_line_nodes(nodes, e4_node.id)
    assert length(line) == 2
    assert Enum.map(line, & &1.san) == [nil, "e4"]

    # 2. Branch: White also plays d4 from root
    assert :ok =
             Games.make_move(%{
               game_id: game_id,
               from_node_id: root.id,
               from: "d2",
               to: "d4",
               player_id: @white
             })

    nodes = Games.list_nodes(game_id)
    assert length(nodes) == 3

    d4_node = Enum.find(nodes, &(&1.san == "d4"))
    assert d4_node != nil

    # Root should now be detected as a fork point
    assert Games.find_fork_node_ids(nodes) == [root.id]
  end

  test "resign updates game status" do
    game_id = "test-game-" <> Ecto.UUID.generate()

    {:ok, _} =
      Games.start_game(%{
        game_id: game_id,
        white_player_id: @white,
        black_player_id: @black
      })

    assert :ok = Games.resign(game_id, @white)

    game = Games.get_game(game_id)
    assert game.status == "ended"
    assert game.winner == "black"
    assert game.end_reason == "resignation"
  end

  test "legal_targets and turn_color helpers" do
    game_id = "test-game-" <> Ecto.UUID.generate()

    {:ok, _} =
      Games.start_game(%{
        game_id: game_id,
        white_player_id: @white,
        black_player_id: @black
      })

    [root] = Games.list_nodes(game_id)

    assert Games.turn_color(root) == :white
    targets = Games.legal_targets(root, "e2")
    assert Enum.sort(targets) == ["e3", "e4"]
    assert Games.promotion_targets(root, "e2") == []
  end

  test "a draw offer survives a move by the player who did not offer" do
    game_id = "test-game-" <> Ecto.UUID.generate()

    {:ok, _} =
      Games.start_game(%{game_id: game_id, white_player_id: @white, black_player_id: @black})

    [root] = Games.list_nodes(game_id)

    assert :ok = Games.offer_draw(game_id, @black)

    assert :ok =
             Games.make_move(%{
               game_id: game_id,
               from_node_id: root.id,
               from: "e2",
               to: "e4",
               player_id: @white
             })

    assert Games.get_game(game_id).draw_offered_by == @black
  end

  test "a draw offer is cleared when the offering player moves" do
    game_id = "test-game-" <> Ecto.UUID.generate()

    {:ok, _} =
      Games.start_game(%{game_id: game_id, white_player_id: @white, black_player_id: @black})

    [root] = Games.list_nodes(game_id)

    assert :ok = Games.offer_draw(game_id, @white)

    assert :ok =
             Games.make_move(%{
               game_id: game_id,
               from_node_id: root.id,
               from: "e2",
               to: "e4",
               player_id: @white
             })

    assert Games.get_game(game_id).draw_offered_by == nil
  end

  test "a drawn branch records why it ended" do
    game_id = "test-game-" <> Ecto.UUID.generate()

    {:ok, _} =
      Games.start_game(%{
        game_id: game_id,
        white_player_id: @white,
        black_player_id: @black,
        initial_fen: "4k3/8/8/8/8/8/4K3/R7 w - - 99 80"
      })

    [root] = Games.list_nodes(game_id)

    assert :ok =
             Games.make_move(%{
               game_id: game_id,
               from_node_id: root.id,
               from: "a1",
               to: "a2",
               player_id: @white
             })

    assert [_, %{status: "fifty_move"}] = Games.list_nodes(game_id)
  end
end
