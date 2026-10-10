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
end
