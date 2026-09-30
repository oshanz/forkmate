defmodule ForkmateWeb.Storybook.Game.DrawOffer do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.GameComponents.draw_offer/1

  def container, do: {:div, class: "max-w-lg"}

  def variations do
    [%Variation{id: :default, attributes: %{from: "Magnus"}}]
  end
end
