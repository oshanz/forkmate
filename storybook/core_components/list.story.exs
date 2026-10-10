defmodule ForkmateWeb.Storybook.CoreComponents.List do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.CoreComponents.list/1

  def variations do
    [
      %Variation{
        id: :default,
        slots: [
          ~s[<:item title="Opponent">Stockfish (medium)</:item>],
          ~s(<:item title="Colour">White</:item>),
          ~s(<:item title="Moves">23</:item>)
        ]
      }
    ]
  end
end
