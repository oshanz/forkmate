defmodule ForkmateWeb.Storybook.CoreComponents.Icon do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.CoreComponents.icon/1

  def variations do
    [
      %Variation{id: :eye, attributes: %{name: "hero-eye"}},
      %Variation{id: :large, attributes: %{name: "hero-flag", class: "size-10 text-primary"}},
      %Variation{
        id: :fullscreen,
        attributes: %{name: "hero-arrows-pointing-out", class: "size-8"}
      }
    ]
  end
end
