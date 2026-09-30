defmodule ForkmateWeb.Storybook.CoreComponents.Button do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.CoreComponents.button/1

  def variations do
    [
      %Variation{
        id: :default,
        slots: ["Send!"]
      },
      %Variation{
        id: :primary,
        attributes: %{variant: "primary"},
        slots: ["Send!"]
      }
    ]
  end
end
