defmodule ForkmateWeb.Storybook.Game.FullscreenToggle do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.GameComponents.fullscreen_toggle/1

  def variations do
    [
      %Variation{
        id: :default,
        description: "Dispatches `forkmate:fullscreen` on the target element",
        attributes: %{target: "#storybook-fullscreen-target"}
      }
    ]
  end
end
