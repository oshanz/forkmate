defmodule ForkmateWeb.Storybook.Game.GameControls do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.GameComponents.game_controls/1

  def variations do
    [
      %Variation{id: :default},
      %Variation{id: :draw_pending, attributes: %{draw_pending: true}},
      %Variation{id: :game_over, attributes: %{disabled: true}}
    ]
  end
end
