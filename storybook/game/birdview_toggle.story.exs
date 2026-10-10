defmodule ForkmateWeb.Storybook.Game.BirdviewToggle do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.GameComponents.birdview_toggle/1

  def variations do
    [
      %Variation{id: :off, attributes: %{on: false}},
      %Variation{id: :on, attributes: %{on: true}}
    ]
  end
end
