defmodule ForkmateWeb.PageControllerTest do
  use ForkmateWeb.ConnCase

  alias Ecto.Adapters.SQL.Sandbox
  alias Forkmate.CommandedApp
  alias Forkmate.Games.Projections.GameProjection

  setup do
    Sandbox.mode(Forkmate.Repo, {:shared, self()})
    start_supervised!(CommandedApp)
    start_supervised!(GameProjection)
    :ok
  end

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Forkmate Chess"
  end

  test "POST /games creates a game and redirects to /games/:id", %{conn: conn} do
    conn = post(conn, ~p"/games")
    assert %{id: game_id} = redirected_params(conn)
    assert redirected_to(conn) == ~p"/games/#{game_id}"
  end
end
