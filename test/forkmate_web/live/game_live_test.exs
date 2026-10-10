defmodule ForkmateWeb.GameLiveTest do
  use ForkmateWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Forkmate.CommandedApp
  alias Forkmate.Games
  alias Forkmate.Games.Projections.GameProjection

  setup do
    Sandbox.mode(Forkmate.Repo, {:shared, self()})
    start_supervised!(CommandedApp)
    start_supervised!(GameProjection)

    game_id = "live-game-" <> Ecto.UUID.generate()

    {:ok, ^game_id} =
      Games.start_game(%{
        game_id: game_id,
        white_player_id: "Player 1",
        black_player_id: "Player 2"
      })

    {:ok, game_id: game_id}
  end

  test "mounts and renders game components", %{conn: conn, game_id: game_id} do
    {:ok, view, _html} = live(conn, ~p"/games/#{game_id}")

    assert has_element?(view, "#main-chess-board")
    assert has_element?(view, "#game-branch-graph")
  end

  test "making a move updates the board", %{conn: conn, game_id: game_id} do
    {:ok, view, _html} = live(conn, ~p"/games/#{game_id}")

    # White selects e2
    view
    |> element("rect[phx-value-square='e2']")
    |> render_click()

    # White moves to e4
    view
    |> element("rect[phx-value-square='e4']")
    |> render_click()

    # Board now shows last move e2 to e4
    assert has_element?(view, "button[phx-click='select_node']", "e4")
  end

  test "rewinding and branching from an earlier node", %{conn: conn, game_id: game_id} do
    {:ok, view, _html} = live(conn, ~p"/games/#{game_id}")

    # 1. White plays e2-e4
    view |> element("rect[phx-value-square='e2']") |> render_click()
    view |> element("rect[phx-value-square='e4']") |> render_click()
    assert has_element?(view, "button[phx-click='select_node']", "e4")

    # 2. White clicks the root node in branch graph to rewind
    nodes = Games.list_nodes(game_id)
    root = hd(nodes)

    view
    |> element("g[phx-value-id='#{root.id}']")
    |> render_click()

    # 3. White plays d2-d4 from root to start a branch
    view |> element("rect[phx-value-square='d2']") |> render_click()
    view |> element("rect[phx-value-square='d4']") |> render_click()

    # Both e4 and d4 should now exist in the tree
    updated_nodes = Games.list_nodes(game_id)
    assert length(updated_nodes) == 3
    assert Enum.any?(updated_nodes, &(&1.san == "e4"))
    assert Enum.any?(updated_nodes, &(&1.san == "d4"))
  end

  test "toggling guide mode and birdview", %{conn: conn, game_id: game_id} do
    {:ok, view, _html} = live(conn, ~p"/games/#{game_id}")

    # Guide toggle
    view |> element("button[phx-click='toggle_guide']") |> render_click()
    assert has_element?(view, "button[aria-pressed='true']", "Guide on")

    # Birdview toggle
    view |> element("button[phx-click='toggle_birdview']") |> render_click()
    assert has_element?(view, "button[role='switch'][aria-checked='true']", "Bird view")
  end

  test "resigning ends the game", %{conn: conn, game_id: game_id} do
    {:ok, view, _html} = live(conn, ~p"/games/#{game_id}")

    view |> element("button[phx-click='resign']") |> render_click()
    assert has_element?(view, "[role='status']", "Black wins")
  end

  test "the view follows a move played from the node being viewed", %{
    conn: conn,
    game_id: game_id
  } do
    {:ok, view, _html} = live(conn, ~p"/games/#{game_id}")

    view |> element("rect[phx-value-square='e2']") |> render_click()
    view |> element("rect[phx-value-square='e4']") |> render_click()

    [root | _] = Games.list_nodes(game_id)
    view |> element("g[phx-value-id='#{root.id}']") |> render_click()

    view |> element("rect[phx-value-square='d2']") |> render_click()
    view |> element("rect[phx-value-square='d4']") |> render_click()

    d4 = Enum.find(Games.list_nodes(game_id), &(&1.san == "d4"))
    assert :sys.get_state(view.pid).socket.assigns.current_node_id == d4.id
  end

  test "an unknown node param falls back to the game's current node", %{
    conn: conn,
    game_id: game_id
  } do
    [root] = Games.list_nodes(game_id)

    play = fn from_node_id, from, to, player_id ->
      :ok =
        Games.make_move(%{
          game_id: game_id,
          from_node_id: from_node_id,
          from: from,
          to: to,
          player_id: player_id
        })
    end

    play.(root.id, "e2", "e4", "Player 1")
    e4 = Enum.find(Games.list_nodes(game_id), &(&1.san == "e4"))
    play.(e4.id, "e7", "e5", "Player 2")
    play.(root.id, "d2", "d4", "Player 1")

    game = Games.get_game(game_id)
    {:ok, view, _html} = live(conn, ~p"/games/#{game_id}?node=bogus")

    assert :sys.get_state(view.pid).socket.assigns.current_node_id == game.current_node_id
  end

  test "a branch drawn by the fifty-move rule is not reported as stalemate", %{conn: conn} do
    game_id = "live-fifty-" <> Ecto.UUID.generate()

    {:ok, ^game_id} =
      Games.start_game(%{
        game_id: game_id,
        white_player_id: "Player 1",
        black_player_id: "Player 2",
        initial_fen: "4k3/8/8/8/8/8/4K3/R7 w - - 99 80"
      })

    [root] = Games.list_nodes(game_id)

    :ok =
      Games.make_move(%{
        game_id: game_id,
        from_node_id: root.id,
        from: "a1",
        to: "a2",
        player_id: "Player 1"
      })

    {:ok, _view, html} = live(conn, ~p"/games/#{game_id}")

    assert html =~ "Fifty-move rule"
    refute html =~ "Stalemate"
  end
end
