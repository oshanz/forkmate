defmodule ForkmateWeb.PageController do
  use ForkmateWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def create_game(conn, _params) do
    game_id = Ecto.UUID.generate()

    case Forkmate.Games.start_game(%{
           game_id: game_id,
           white_player_id: "Player 1",
           black_player_id: "Player 2"
         }) do
      {:ok, _} ->
        redirect(conn, to: ~p"/games/#{game_id}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to create game: #{inspect(reason)}")
        |> redirect(to: ~p"/")
    end
  end
end
