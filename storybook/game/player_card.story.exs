defmodule ForkmateWeb.Storybook.Game.PlayerCard do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.GameComponents.player_card/1

  def container, do: {:div, class: "max-w-sm"}

  def variations do
    [
      %Variation{
        id: :idle,
        attributes: %{name: "Magnus", rating: 2830, color: :black, seconds: 312}
      },
      %Variation{
        id: :to_move,
        description: "Highlighted when it is this player's turn",
        attributes: %{name: "Hikaru", rating: 2795, color: :white, active: true, seconds: 287}
      },
      %Variation{
        id: :low_time,
        attributes: %{name: "Hikaru", rating: 2795, color: :white, active: true, seconds: 14}
      },
      %Variation{
        id: :offline,
        attributes: %{name: "guest-4821", color: :black, online: false, seconds: 600}
      },
      %Variation{
        id: :untimed,
        description: "Correspondence or untimed games show no clock",
        attributes: %{name: "Ada", rating: 1650, color: :white}
      }
    ]
  end
end
