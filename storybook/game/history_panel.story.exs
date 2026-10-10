defmodule ForkmateWeb.Storybook.Game.HistoryPanel do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.GameComponents.history_panel/1

  def container, do: {:div, class: "flex h-96 max-w-sm flex-col"}

  @moves for ply <- 1..30,
             do: %{id: "n#{ply}", ply: ply, san: Enum.at(~w(e4 e5 Nf3 Nc6 Bb5 a6), rem(ply, 6))}

  def variations do
    [
      %Variation{
        id: :short,
        description: "A few moves",
        attributes: %{moves: Enum.take(@moves, 5), current: "n5"}
      },
      %Variation{
        id: :long,
        description: "A long game; the list scrolls inside the panel",
        attributes: %{moves: @moves, current: "n30", forks: ["n3", "n10"]}
      }
    ]
  end
end
