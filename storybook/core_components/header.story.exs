defmodule ForkmateWeb.Storybook.CoreComponents.Header do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.CoreComponents.header/1

  def variations do
    [
      %Variation{id: :default, slots: ["Games"]},
      %Variation{
        id: :with_subtitle_and_actions,
        slots: [
          "Games",
          "<:subtitle>Everything in progress</:subtitle>",
          "<:actions><button class=\"btn btn-primary btn-sm\">New game</button></:actions>"
        ]
      }
    ]
  end
end
