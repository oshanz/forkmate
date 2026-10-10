defmodule Forkmate.Games.Router do
  @moduledoc """
  Command routing for the Game aggregate.
  """
  use Commanded.Commands.Router

  identify(Forkmate.Games.Game, by: :game_id)

  dispatch(
    [
      Forkmate.Games.Commands.StartGame,
      Forkmate.Games.Commands.MakeMove,
      Forkmate.Games.Commands.Resign,
      Forkmate.Games.Commands.OfferDraw,
      Forkmate.Games.Commands.AcceptDraw,
      Forkmate.Games.Commands.DeclineDraw
    ],
    to: Forkmate.Games.Game
  )
end
