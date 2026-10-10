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

  describe "POST /games with mode=bot" do
    alias Forkmate.Bots.Seat
    alias Forkmate.Games

    test "human as white", %{conn: conn} do
      conn = post(conn, ~p"/games", %{"mode" => "bot", "level" => "medium", "color" => "white"})
      assert %{id: game_id} = redirected_params(conn)
      game = Games.get_game(game_id)
      assert game.white_player_id == "Player 1"
      assert game.black_player_id == Seat.new(:medium)
    end

    test "human as black", %{conn: conn} do
      conn = post(conn, ~p"/games", %{"mode" => "bot", "level" => "hard", "color" => "black"})
      assert %{id: game_id} = redirected_params(conn)
      game = Games.get_game(game_id)
      assert game.white_player_id == Seat.new(:hard)
      assert game.black_player_id == "Player 1"
    end

    test "random colour gives the human exactly one seat", %{conn: conn} do
      conn = post(conn, ~p"/games", %{"mode" => "bot", "level" => "easy", "color" => "random"})
      assert %{id: game_id} = redirected_params(conn)
      game = Games.get_game(game_id)
      assert Seat.human_color(game.white_player_id, game.black_player_id) in [:white, :black]
    end

    test "rejects an unknown level", %{conn: conn} do
      conn = post(conn, ~p"/games", %{"mode" => "bot", "level" => "godlike", "color" => "white"})
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid"
    end

    test "rejects an unknown colour", %{conn: conn} do
      conn = post(conn, ~p"/games", %{"mode" => "bot", "level" => "easy", "color" => "green"})
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid"
    end

    test "rejects missing options", %{conn: conn} do
      conn = post(conn, ~p"/games", %{"mode" => "bot"})
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid"
    end

    test "refuses when the bot is unavailable", %{conn: conn} do
      previous = Application.get_env(:forkmate, :bot)
      Application.put_env(:forkmate, :bot, Forkmate.Bots.UnavailableBot)
      on_exit(fn -> Application.put_env(:forkmate, :bot, previous) end)

      conn = post(conn, ~p"/games", %{"mode" => "bot", "level" => "easy", "color" => "white"})
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "unavailable"
    end
  end

  test "home page offers the computer game form", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ "Play vs computer"
    assert html =~ ~s(name="level")
    assert html =~ ~s(name="color")
  end
end
