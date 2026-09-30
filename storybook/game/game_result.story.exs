defmodule ForkmateWeb.Storybook.Game.GameResult do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.GameComponents.game_result/1

  def container, do: {:div, class: "max-w-lg"}

  def variations do
    [
      %Variation{id: :checkmate, attributes: %{reason: :checkmate, winner: :white}},
      %Variation{id: :resignation, attributes: %{reason: :resignation, winner: :black}},
      %Variation{id: :timeout, attributes: %{reason: :timeout, winner: :white}},
      %Variation{id: :stalemate, attributes: %{reason: :stalemate}},
      %Variation{id: :agreed_draw, attributes: %{reason: :agreed_draw}},
      %Variation{id: :repetition, attributes: %{reason: :repetition}},
      %Variation{
        id: :branch_only,
        description: "Mate ends only its branch (open question in the design doc)",
        attributes: %{reason: :checkmate, winner: :black, scope: :branch}
      }
    ]
  end
end
