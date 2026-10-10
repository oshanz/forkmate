defmodule ForkmateWeb.PageController do
  use ForkmateWeb, :controller

  alias Forkmate.Bots
  alias Forkmate.Bots.Seat
  alias Forkmate.Games

  @human "Player 1"

  def home(conn, _params) do
    render(conn, :home, levels: Seat.levels())
  end

  def create_game(conn, %{"mode" => "bot"} = params) do
    with {:ok, level} <- Seat.parse_level(params["level"]),
         {:ok, color} <- resolve_color(params["color"]),
         :ok <- ensure_bot_available(),
         {:ok, game_id} <- Games.start_game(seats(color, Seat.new(level))) do
      redirect(conn, to: ~p"/games/#{game_id}")
    else
      {:error, reason} ->
        conn
        |> put_flash(:error, error_message(reason))
        |> redirect(to: ~p"/")
    end
  end

  def create_game(conn, _params) do
    game_id = Ecto.UUID.generate()

    case Games.start_game(%{
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

  defp resolve_color("white"), do: {:ok, :white}
  defp resolve_color("black"), do: {:ok, :black}
  defp resolve_color("random"), do: {:ok, Enum.random([:white, :black])}
  defp resolve_color(_), do: {:error, :invalid_color}

  defp ensure_bot_available do
    if Bots.available?(), do: :ok, else: {:error, :bot_unavailable}
  end

  defp seats(:white, bot_id), do: %{white_player_id: @human, black_player_id: bot_id}
  defp seats(:black, bot_id), do: %{white_player_id: bot_id, black_player_id: @human}

  defp error_message(:bot_unavailable), do: "Computer opponent unavailable."

  defp error_message(reason) when reason in [:invalid_level, :invalid_color],
    do: "Invalid computer game options."

  defp error_message(reason), do: "Failed to create game: #{inspect(reason)}"
end
