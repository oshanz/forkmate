defmodule ForkmateWeb.Storybook.Game.Clock do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.GameComponents.clock/1

  def variations do
    [
      %Variation{id: :stopped, attributes: %{seconds: 300}},
      %Variation{id: :running, attributes: %{seconds: 245, running: true}},
      %Variation{id: :low, attributes: %{seconds: 9, running: true}}
    ]
  end
end
